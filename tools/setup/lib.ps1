# Dot-sourced, not run: the Windows PowerShell 5.1 side of tools/setup/lib.sh (same lookups, same order; keep them in step).
#   . "$PSScriptRoot\setup\lib.ps1"
# A script that dot-sources this file must itself be started with -ExecutionPolicy Bypass (as tools/godot_open.cmd does):
# under Windows' default (Restricted) policy `powershell -File x.ps1` refuses to run, and so does the dot-source.
#
#   Get-FeManifest              tools/setup/versions.env as a hashtable of strings
#   Get-FeHome                  the per-user root: $env:FORCED_ENTRY_HOME, else %LOCALAPPDATA%\Forced-Entry
#   Get-FeVonHome               <root>\von  (the venv and checkpoints\von-1.2; Von is started with it as its working directory)
#   Get-FeGodotDir [-Version V] <root>\godot\<V> (default: the manifest's GODOT_VERSION)
#   Find-FeGodot                the Godot binary as a string, or $null: $env:GODOT; godot / godot4 on PATH; the install
#                               folder above; %LOCALAPPDATA%\Programs, winget, Program Files, scoop
#   Find-FePython               the Python (PYTHON_MIN or newer) as a string, or $null: $env:PYTHON (below the minimum, a
#                               warning and $null); python3.14/3.13/3.12 on PATH; python3 only if it really runs and is
#                               new enough (it is the Microsoft Store stub otherwise); py -3; python
#   Get-FeBootstrapCommand      the command that runs the setup bootstrap

$FeSetupDir = $PSScriptRoot

function Get-FeManifest {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $FeSetupDir 'versions.env')) {
        if ($line.StartsWith('#') -or $line.IndexOf('=') -lt 0) { continue }
        $i = $line.IndexOf('=')
        $values[$line.Substring(0, $i)] = $line.Substring($i + 1).TrimEnd("`r")
    }
    return $values
}

function Get-FeHome {
    if ($env:FORCED_ENTRY_HOME) { return $env:FORCED_ENTRY_HOME }
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path $env:USERPROFILE 'AppData\Local' }
    return (Join-Path $base 'Forced-Entry')
}

function Get-FeVonHome { return (Join-Path (Get-FeHome) 'von') }

function Get-FeGodotDir {
    param([string]$Version)
    if (-not $Version) { $Version = (Get-FeManifest)['GODOT_VERSION'] }
    return (Join-Path (Join-Path (Get-FeHome) 'godot') $Version)
}

# The Godot binary in the first of these folders that holds one: a _console.exe first (it writes to the terminal a
# script reads), then any other Godot*.exe.
function Find-FeGodotIn {
    param([string[]]$Folders)
    foreach ($folder in $Folders) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
        foreach ($pattern in 'Godot*_console.exe', 'Godot*.exe') {
            $found = Get-ChildItem -LiteralPath $folder -Filter $pattern -File -ErrorAction SilentlyContinue |
                Sort-Object Name | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }
    return $null
}

function Find-FeGodot {
    if ($env:GODOT) { return $env:GODOT }
    foreach ($name in 'godot', 'godot4') {
        $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    $local = $env:LOCALAPPDATA
    if (-not $local) { $local = Join-Path $env:USERPROFILE 'AppData\Local' }
    $files = $env:ProgramFiles
    if (-not $files) { $files = 'C:\Program Files' }
    $folders = @(Get-FeGodotDir)
    foreach ($glob in (Join-Path $local 'Programs\Godot*'),
                      (Join-Path $local 'Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*'),
                      (Join-Path $files 'Godot*'), ($files + ' (x86)\Godot*')) {
        $folders += @(Get-ChildItem -Path $glob -Directory -ErrorAction SilentlyContinue | Sort-Object Name |
            ForEach-Object { $_.FullName })
    }
    $folders += (Join-Path $env:USERPROFILE 'scoop\apps\godot\current')
    $folders += (Join-Path $env:USERPROFILE 'scoop\apps\godot-mono\current')
    return (Find-FeGodotIn $folders)
}

# The command that installs and pins everything (what a "not found" message tells the user to run).
function Get-FeBootstrapCommand { return 'powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup\bootstrap.ps1' }

# "MAJOR.MINOR" of the Python at $Exe, or $null when it does not run (the Microsoft Store stub).
function Get-FePythonVersion {
    param([string]$Exe)
    # (No double quotes in the code: Windows PowerShell 5.1 drops them from a native command's arguments.)
    $v = & $Exe -c 'import sys; print(*sys.version_info[:2])' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $v) { return $null }
    return (([string]($v | Select-Object -First 1)).Trim() -replace '\s+', '.')
}

# $Version ("3.9") is $Minimum ("3.12") or newer.
function Test-FeVersionAtLeast {
    param([string]$Version, [string]$Minimum)
    if ($Version -notmatch '^(\d+)\.(\d+)$') { return $false }
    $have = @([int]$Matches[1], [int]$Matches[2])
    if ($Minimum -notmatch '^(\d+)\.(\d+)$') { return $true }
    $want = @([int]$Matches[1], [int]$Matches[2])
    if ($have[0] -ne $want[0]) { return ($have[0] -gt $want[0]) }
    return ($have[1] -ge $want[1])
}

# The Python at PYTHON_MIN (versions.env) or newer, as a string, or $null: $env:PYTHON when it is that (below it, a
# warning and $null); python3.14 / 3.13 / 3.12 on PATH; python3 only if it really runs and is new enough (it is the
# Microsoft Store stub otherwise); py -3; python.
function Find-FePython {
    $min = (Get-FeManifest)['PYTHON_MIN']
    if ($env:PYTHON) {
        $v = Get-FePythonVersion $env:PYTHON
        if ($v -and (Test-FeVersionAtLeast $v $min)) { return $env:PYTHON }
        if ($v) { [Console]::Error.WriteLine("warning: `$env:PYTHON ($env:PYTHON) is Python $v, below the $min the tools need; not using it") }
        else { [Console]::Error.WriteLine("warning: `$env:PYTHON ($env:PYTHON) is not a Python that runs; not using it") }
        return $null
    }
    foreach ($name in 'python3.14', 'python3.13', 'python3.12', 'python3') {
        $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) { continue }
        $v = Get-FePythonVersion $cmd.Source
        if ($v -and (Test-FeVersionAtLeast $v $min)) { return $cmd.Source }
    }
    $py = Get-Command py -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($py) {
        $exe = & $py.Source -3 -c 'import sys; print(sys.executable)' 2>$null
        if ($LASTEXITCODE -eq 0 -and $exe) {
            $exe = ([string]$exe).Trim()
            $v = Get-FePythonVersion $exe
            if ($v -and (Test-FeVersionAtLeast $v $min)) { return $exe }
        }
    }
    $python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($python) {
        $v = Get-FePythonVersion $python.Source
        if ($v -and (Test-FeVersionAtLeast $v $min)) { return $python.Source }
    }
    return $null
}
