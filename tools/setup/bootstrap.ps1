# The Windows bootstrap (Windows PowerShell 5.1): installs or upgrades what Forced-Entry needs, one step at a time,
# each logged as installed, upgraded or up to date. Every version is pinned in tools\setup\versions.env. Safe to
# re-run: it carries on where it stopped (a half-finished venv, weights or Godot unpack is detected and redone), a
# second run installs nothing, and a run with the network off succeeds when everything is already there (no step goes
# to the network unless it has work). tools/setup/bootstrap.sh is the Mac twin.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup\bootstrap.ps1 [-Check] [-Skip STEP,...] [-NoPath]
#     -Check      look, install nothing and touch no network: log each step as up to date or missing/outdated;
#                 exit 1 when any is
#     -Skip       leave these steps out (comma list of: git python godot skillshare hooks venv weights)
#     -NoPath     do not add the skillshare folder to the user's PATH (the tool tests use it)
# Steps, in order: git (winget Git.Git: Git Bash), python (winget Python.Python.3.12: the 3.12 the Von venv is built
# from, even when a newer Python is installed), godot (the pinned standard build, unpacked into the per-user root),
# skillshare, hooks (git hooks and the skills links: tools/install_hooks.sh through Git Bash), venv (the Von venv under
# <von home> with von-sdk), weights (the Von weights under <von home>\checkpoints\von-1.2). The per-user root is
# tools\setup\lib.ps1's Get-FeHome (FORCED_ENTRY_HOME). It needs -ExecutionPolicy Bypass (lib.ps1 says why).
# Exit codes: 0 every step is up to date or done; 1 a step failed (the log names it; re-run to carry on) or, with
# -Check, something is missing. When a step changed PATH the log ends with a note to open a new shell.
# Other environment: FE_VON_PYTHON=C:\path\python.exe builds the Von venv from that Python instead of a 3.12 (its
# version is then not checked).
param([switch]$Check, [string[]]$Skip = @(), [switch]$NoPath)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is many times faster without its progress bar
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
. (Join-Path $PSScriptRoot 'lib.ps1')
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $Root

$M = Get-FeManifest
$FeHome = Get-FeHome
$VonHome = Get-FeVonHome
$Venv = Join-Path $VonHome 'venv'
$VenvBin = Join-Path $Venv 'Scripts'
$VenvPy = Join-Path $VenvBin 'python.exe'
$VenvVon = Join-Path $VenvBin 'von.exe'
$Weights = Join-Path $VonHome 'checkpoints\von-1.2'
$WeightFiles = 'config.json', 'tokenizer.json', 'calibration.json', 'marker_calibration.json', 'model.safetensors', 'option_marker.pt'
$Marker = '.fe-revision'
$SkipSet = @($Skip | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

$script:Installed = 0; $script:Upgraded = 0; $script:UpToDate = 0; $script:Missing = 0; $script:Skipped = 0
$script:Notes = @()

function Log([string]$text) { [Console]::Out.WriteLine("bootstrap: $text"); [Console]::Out.Flush() }
function Report-Ok([string]$step, [string]$detail) { $script:UpToDate++; Log "${step}: up to date ($detail)" }
function Report-Installed([string]$step, [string]$detail) { $script:Installed++; Log "${step}: installed ($detail)" }
function Report-Upgraded([string]$step, [string]$detail) { $script:Upgraded++; Log "${step}: upgraded ($detail)" }
function Report-Missing([string]$step, [string]$detail) { $script:Missing++; Log "${step}: $detail" }
function Stop-Step([string]$step, [string]$cause) {
    Log "${step}: FAILED: $cause"
    Log 'fix the cause and run the bootstrap again; it carries on from here'
    exit 1
}

# Re-read PATH from the registry, so what winget just installed is found without a new shell.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}
function Add-Note([string]$text) { $script:Notes += $text }

function Install-WithWinget([string]$step, [string]$id) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Stop-Step $step 'winget is not available: install "App Installer" from the Microsoft Store, then run this again'
    }
    Log "${step}: winget install $id"
    & winget install --id $id --exact --source winget --silent --accept-package-agreements --accept-source-agreements
    # 0x8A15002B: already installed and nothing newer to apply, which is fine here.
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { Stop-Step $step "winget install $id failed (exit $LASTEXITCODE)" }
    Update-SessionPath
    Add-Note 'PATH changed: open a new terminal so every shell sees what was installed'
}

function Get-Download([string]$url, [string]$dest) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    $part = "$dest.part"
    try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $part -ErrorAction Stop }
    catch { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue; return $false }
    Move-Item -LiteralPath $part -Destination $dest -Force
    return $true
}
function Get-Sum([string]$algo, [string]$file) { return (Get-FileHash -Algorithm $algo -LiteralPath $file).Hash.ToLower() }
function Expand-Zip([string]$zip, [string]$dest) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $dest)
}
function New-ScratchDir {
    $d = Join-Path ([IO.Path]::GetTempPath()) ('fe-bootstrap-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    return $d
}
function Remove-Quietly([string]$path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }

# ---- git ----------------------------------------------------------------------------------------------------------
# Git Bash: bash.exe from the Git for Windows that git.exe belongs to (not the WSL launcher in System32).
function Find-GitBash {
    $candidates = @()
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) {
        $dir = Split-Path -Parent $git.Source
        for ($i = 0; $i -lt 3 -and $dir; $i++) { $candidates += (Join-Path $dir 'bin\bash.exe'); $dir = Split-Path -Parent $dir }
    }
    $candidates += (Join-Path $env:ProgramFiles 'Git\bin\bash.exe')
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe') }
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    return $null
}
function Step-Git {
    $bash = Find-GitBash
    if ($bash) {
        $version = 'git'
        if (Get-Command git -CommandType Application -ErrorAction SilentlyContinue) { $version = (& git --version) -join ' ' }
        Report-Ok 'git' "$version, Git Bash at $bash"
        return
    }
    if ($Check) { Report-Missing 'git' 'missing (Git for Windows with Git Bash)'; return }
    Install-WithWinget 'git' 'Git.Git'
    $bash = Find-GitBash
    if (-not $bash) { Stop-Step 'git' 'Git for Windows installed but Git Bash was not found: open a new terminal and run this again' }
    Report-Installed 'git' "Git Bash at $bash"
}

# ---- python (the 3.12 the Von venv is built from) -------------------------------------------------------------------
function Get-PyMinor([string]$exe) {
    # Single quotes inside: Windows PowerShell 5.1 strips double quotes from a native command's arguments.
    $v = & $exe -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $v) { return $null }
    return ([string]$v).Trim()
}
function Find-VonPython {
    if ($env:FE_VON_PYTHON) { return $env:FE_VON_PYTHON }
    $want = $M['VON_PYTHON']
    $py = Get-Command py -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($py) {
        $exe = & $py.Source "-$want" -c 'import sys; print(sys.executable)' 2>$null
        if ($LASTEXITCODE -eq 0 -and $exe) { return ([string]$exe).Trim() }
    }
    $candidates = @()
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA ('Programs\Python\Python' + $want.Replace('.', '') + '\python.exe')) }
    $named = Get-Command "python$want" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($named) { $candidates += $named.Source }
    foreach ($c in $candidates) { if ((Test-Path -LiteralPath $c) -and ((Get-PyMinor $c) -eq $want)) { return $c } }
    return $null
}
function Step-Python {
    $want = $M['VON_PYTHON']
    $py = Find-VonPython
    if ($py) { Report-Ok 'python' "$((& $py --version 2>&1) -join ' ') at $py"; return }
    if ($Check) { Report-Missing 'python' "missing (Python $want for the Von venv)"; return }
    Install-WithWinget 'python' "Python.Python.$want"
    $py = Find-VonPython
    if (-not $py) { Stop-Step 'python' "Python $want installed but not found: open a new terminal and run this again" }
    Report-Installed 'python' "$((& $py --version 2>&1) -join ' ') at $py"
}

# ---- godot (the pinned standard build; an existing build of that version, mono or not, is kept) ---------------------
function Test-GodotVersion([string]$exe) {
    $want = $M['GODOT_VERSION'].Replace('-', '.')
    $v = (& $exe --version 2>$null | Select-Object -First 1)
    if (-not $v) { return $false }
    $v = ([string]$v).Trim()
    return ($v -eq $want -or $v.StartsWith("$want."))
}
function Step-Godot {
    $want = $M['GODOT_VERSION']
    $cur = Find-FeGodot
    if ($cur -and (Test-GodotVersion $cur)) { Report-Ok 'godot' "$want at $cur"; return }
    $dir = Get-FeGodotDir
    $pinned = Find-FeGodotIn @($dir)
    if ($pinned -and (Test-GodotVersion $pinned)) {
        Report-Ok 'godot' "$want at $pinned"
        if ($cur) { Log "godot: note: $cur comes first in the lookup and is not $want; unset GODOT or remove it" }
        return
    }
    if ($Check) {
        $other = ''
        if ($cur) { $other = "; $cur is another version" }
        Report-Missing 'godot' "missing ($want$other)"
        return
    }
    $zip = $M['GODOT_WIN64_ZIP']
    $tmp = New-ScratchDir
    try {
        Log "godot: downloading $zip"
        $url = "$($M['GODOT_BASE_URL'])/$zip"
        if (-not (Get-Download $url (Join-Path $tmp $zip))) { Stop-Step 'godot' "download of $url failed (network?)" }
        if ((Get-Sum 'SHA512' (Join-Path $tmp $zip)) -ne $M['GODOT_WIN64_SHA512']) {
            Stop-Step 'godot' "$zip does not match the SHA-512 pinned in versions.env"
        }
        Remove-Quietly $dir; Remove-Quietly "$dir.partial"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dir) | Out-Null
        try { Expand-Zip (Join-Path $tmp $zip) "$dir.partial" } catch { Stop-Step 'godot' "unpacking $zip failed: $_" }
        Move-Item -LiteralPath "$dir.partial" -Destination $dir
    } finally { Remove-Quietly $tmp }
    $pinned = Find-FeGodotIn @($dir)
    if (-not $pinned -or -not (Test-GodotVersion $pinned)) { Stop-Step 'godot' "the unpacked Godot in $dir does not report $want" }
    Report-Installed 'godot' "$want at $pinned"
    if ($cur) { Log "godot: note: $cur comes first in the lookup and is not $want; unset GODOT or remove it" }
}

# ---- skillshare --------------------------------------------------------------------------------------------------
# Append a folder to the user's PATH in the registry, keeping what is there as it is: the value stays an expandable
# string and an entry like %USERPROFILE%\tools is not turned into its current expansion (which [Environment]'s getter
# and setter would do). A dummy variable set and removed afterwards makes Windows tell running programs the
# environment changed. `$KeyPath` is a subkey of HKCU (a test uses a scratch one).
function Add-UserPathEntry([string]$Dir, [string]$KeyPath = 'Environment') {
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($KeyPath)
    try {
        $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $entries = @($raw -split ';' | Where-Object { $_ })
        if ($entries | Where-Object { $_.TrimEnd('\') -eq $Dir.TrimEnd('\') }) { return }
        $key.SetValue('Path', ((@($entries) + $Dir) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } finally { $key.Close() }
    if ($KeyPath -eq 'Environment') {
        [Environment]::SetEnvironmentVariable('FE_PATH_CHANGED', '1', 'User')
        [Environment]::SetEnvironmentVariable('FE_PATH_CHANGED', $null, 'User')
    }
}

function Find-Skillshare {
    $cmd = Get-Command skillshare -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    foreach ($c in (Join-Path $FeHome 'bin\skillshare.exe'), (Join-Path $env:USERPROFILE 'go\bin\skillshare.exe')) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}
function Step-Skillshare {
    $want = $M['SKILLSHARE_VERSION']
    $bin = Find-Skillshare
    $have = $null
    if ($bin) {
        $out = (& $bin --version 2>$null) -join ' '
        if ($out -match '(\d+\.\d+\.\d+)') { $have = $Matches[1] }
        if ($have -eq $want) { Report-Ok 'skillshare' "v$want at $bin"; return }
    }
    if ($Check) {
        if ($bin) { Report-Missing 'skillshare' "outdated (v$have), needs v$want" }
        else { Report-Missing 'skillshare' "missing (needs v$want)" }
        return
    }
    $zip = $M['SKILLSHARE_WIN64_ZIP']
    # An old one is replaced where it is (so the PATH still finds the new one); else it goes into <home>\bin.
    if ($bin) { $dir = Split-Path -Parent $bin } else { $dir = Join-Path $FeHome 'bin' }
    $tmp = New-ScratchDir
    try {
        Log "skillshare: downloading $zip"
        $url = "$($M['SKILLSHARE_BASE_URL'])/$zip"
        if (-not (Get-Download $url (Join-Path $tmp $zip))) { Stop-Step 'skillshare' "download of $url failed (network?)" }
        if ((Get-Sum 'SHA256' (Join-Path $tmp $zip)) -ne $M['SKILLSHARE_WIN64_SHA256']) {
            Stop-Step 'skillshare' "$zip does not match the SHA-256 pinned in versions.env"
        }
        try { Expand-Zip (Join-Path $tmp $zip) (Join-Path $tmp 'x') } catch { Stop-Step 'skillshare' "unpacking $zip failed: $_" }
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        try { Copy-Item -LiteralPath (Join-Path $tmp 'x\skillshare.exe') -Destination (Join-Path $dir 'skillshare.exe') -Force -ErrorAction Stop }
        catch { Stop-Step 'skillshare' "could not write $dir\skillshare.exe (is skillshare running?): $_" }
    } finally { Remove-Quietly $tmp }
    if ($bin) { Report-Upgraded 'skillshare' "v$have to v$want at $dir" } else { Report-Installed 'skillshare' "v$want at $dir" }
    $onPath = @($env:Path -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -eq $dir.TrimEnd('\')) }).Count -gt 0
    if (-not $onPath) {
        $env:Path = "$dir;$env:Path"
        if ($NoPath) { return }
        Add-UserPathEntry $dir
        Add-Note "PATH changed (added $dir): open a new terminal so every shell sees skillshare"
    }
}

# ---- hooks and skills --------------------------------------------------------------------------------------------
function Step-Hooks {
    $hooksPath = (& git config core.hooksPath 2>$null)
    $skills = Join-Path $Root '.claude\skills'
    $linked = (Test-Path -LiteralPath $skills) -and (@(Get-ChildItem -LiteralPath $skills -Force -ErrorAction SilentlyContinue).Count -gt 0)
    if ($hooksPath -eq '.githooks' -and $linked) { Report-Ok 'hooks' 'core.hooksPath=.githooks, skills linked'; return }
    if ($Check) { Report-Missing 'hooks' 'missing (tools/install_hooks.sh has not run in this checkout)'; return }
    $bash = Find-GitBash
    if (-not $bash) { Stop-Step 'hooks' 'Git Bash not found (the git step installs Git for Windows)' }
    # install_hooks.sh runs sync_skills.sh, which needs skillshare on the PATH: it may have just been put elsewhere.
    $ss = Find-Skillshare
    if ($ss) { $env:Path = "$(Split-Path -Parent $ss);$env:Path" }
    & $bash 'tools/install_hooks.sh'
    if ($LASTEXITCODE -ne 0) { Stop-Step 'hooks' "tools/install_hooks.sh failed (exit $LASTEXITCODE; see above)" }
    Report-Installed 'hooks' 'git hooks enabled, skills linked'
}

# ---- the Von venv ------------------------------------------------------------------------------------------------
function Get-VenvSdkVersion {
    $out = & $VenvPy -m pip show von-sdk 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    foreach ($line in $out) { if ($line -match '^Version:\s*(\S+)') { return $Matches[1] } }
    return $null
}
# Why the venv is not usable, or '' when it is. 'rebuild: ...' needs a fresh venv, 'pip: ...' only a pip install.
function Get-VenvProblem {
    if (-not (Test-Path -LiteralPath $Venv -PathType Container)) { return 'none' }
    $cfg = Join-Path $Venv 'pyvenv.cfg'
    if (-not (Test-Path -LiteralPath $cfg)) { return "rebuild: $Venv has no pyvenv.cfg" }
    $line = Get-Content -LiteralPath $cfg | Where-Object { $_ -match '^\s*home\s*=' } | Select-Object -First 1
    $baseHome = ''
    if ($line) { $baseHome = ($line -replace '^\s*home\s*=\s*', '').Trim() }
    if (-not $baseHome -or -not (Test-Path -LiteralPath $baseHome -PathType Container)) { return "rebuild: its base Python is gone (home = $baseHome)" }
    if (-not (Test-Path -LiteralPath $VenvPy)) { return "rebuild: $VenvPy is missing" }
    $minor = Get-PyMinor $VenvPy
    if (-not $minor) { return 'rebuild: its Python does not run' }
    if (-not $env:FE_VON_PYTHON -and $minor -ne $M['VON_PYTHON']) { return "rebuild: it is Python $minor, Von needs $($M['VON_PYTHON'])" }
    $have = Get-VenvSdkVersion
    if (-not $have) { return 'pip: von-sdk is not installed' }
    if ($have -ne $M['VON_SDK_VERSION']) { return "pip: von-sdk $have, want $($M['VON_SDK_VERSION'])" }
    if (-not (Test-Path -LiteralPath $VenvVon)) { return 'rebuild: von.exe is missing' }
    & $VenvVon --version 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return 'rebuild: von --version fails' }
    return ''
}
function Step-Venv {
    $want = $M['VON_SDK_VERSION']
    $problem = Get-VenvProblem
    if (-not $problem) { Report-Ok 'venv' "von-sdk $want in $Venv"; return }
    if ($Check) {
        if ($problem -eq 'none') { $problem = 'missing' }
        Report-Missing 'venv' "$($problem -replace '^(rebuild|pip): ', '') (needs von-sdk $want in $Venv)"
        return
    }
    $py = Find-VonPython
    if (-not $py) { Stop-Step 'venv' "no Python $($M['VON_PYTHON']) to build the Von venv from (the python step installs it)" }
    $have = $null
    if ($problem.StartsWith('pip:')) {
        $have = Get-VenvSdkVersion
    } else {
        if ($problem.StartsWith('rebuild:')) { Log "venv: rebuilding ($($problem.Substring(9)))" }
        Remove-Quietly $Venv
        if (Test-Path -LiteralPath $Venv) { Stop-Step 'venv' "could not remove the old venv $Venv (is a Von server or a shell using it? stop it and run this again)" }
        New-Item -ItemType Directory -Force -Path $VonHome | Out-Null
        & $py -m venv $Venv
        if ($LASTEXITCODE -ne 0) { Stop-Step 'venv' "$py -m venv $Venv failed" }
    }
    Log "venv: pip install von-sdk==$want (a large download: PyTorch)"
    & $VenvPy -m pip install --disable-pip-version-check "von-sdk==$want"
    if ($LASTEXITCODE -ne 0) { Stop-Step 'venv' "pip install von-sdk==$want failed (network?)" }
    & $VenvVon --version 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-Step 'venv' 'von --version fails after the install' }
    if ($have) { Report-Upgraded 'venv' "von-sdk $have to $want" } else { Report-Installed 'venv' "von-sdk $want in $Venv" }
}

# ---- the Von weights ---------------------------------------------------------------------------------------------
function Test-WeightsPresent {
    foreach ($f in $WeightFiles) {
        $p = Join-Path $Weights $f
        if (-not (Test-Path -LiteralPath $p) -or (Get-Item -LiteralPath $p).Length -eq 0) { return $false }
    }
    return $true
}
function Step-Weights {
    $rev = $M['VON_WEIGHTS_REVISION']; $repo = $M['VON_WEIGHTS_REPO']
    $short = $rev.Substring(0, 12)
    $markerFile = Join-Path $Weights $Marker
    $marked = ''
    if (Test-Path -LiteralPath $markerFile) { $marked = (Get-Content -LiteralPath $markerFile -TotalCount 1).Trim() }
    if ((Test-WeightsPresent) -and $marked -eq $rev) { Report-Ok 'weights' "$repo@$short in $Weights"; return }
    if ($Check) { Report-Missing 'weights' "missing or not revision $short in $Weights"; return }
    $hf = Join-Path $VenvBin 'hf.exe'
    if (-not (Test-Path -LiteralPath $hf)) { Stop-Step 'weights' "$hf is missing: the venv step has not completed; run the bootstrap again" }
    Log "weights: hf download $repo@$short (about 3 GB; a stopped download resumes)"
    New-Item -ItemType Directory -Force -Path $Weights | Out-Null
    $env:PYTHONUTF8 = '1'   # hf's progress output has characters a Windows code page cannot encode
    & $hf download $repo --revision $rev --local-dir $Weights
    if ($LASTEXITCODE -ne 0) { Stop-Step 'weights' 'hf download failed (network?)' }
    if (-not (Test-WeightsPresent)) { Stop-Step 'weights' "hf download finished but $Weights lacks one of: $($WeightFiles -join ' ')" }
    [IO.File]::WriteAllText($markerFile, "$rev`n")
    Report-Installed 'weights' "$repo@$short in $Weights"
}

$suffix = ''
if ($Check) { $suffix = ' (check only: nothing is installed)' }
Log "per-user root: $FeHome$suffix"
foreach ($step in 'git', 'python', 'godot', 'skillshare', 'hooks', 'venv', 'weights') {
    if ($SkipSet -contains $step) { $script:Skipped++; Log "${step}: skipped"; continue }
    & "Step-$([cultureinfo]::InvariantCulture.TextInfo.ToTitleCase($step))"
}
foreach ($n in $script:Notes | Select-Object -Unique) { Log "NOTE: $n" }
$summary = "$script:Installed installed, $script:Upgraded upgraded, $script:UpToDate up to date"
if ($script:Skipped -gt 0) { $summary += ", $script:Skipped skipped" }
if ($script:Missing -gt 0) { $summary += ", $script:Missing missing or outdated" }
Log "done: $summary"
if ($script:Missing -gt 0) { exit 1 }
exit 0
