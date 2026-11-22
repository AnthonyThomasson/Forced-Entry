# Open the Godot editor on this checkout (--editor), or play the game (no argument), on the Godot Find-FeGodot finds
# (tools/setup/lib.ps1: $env:GODOT, PATH, the setup's install folder, %LOCALAPPDATA%\Programs ...). The Herdr buttons run
# it through tools/godot_open.cmd (godot_open.sh is its bash twin). Windows PowerShell 5.1.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\godot_open.ps1 [--editor]
# It needs -ExecutionPolicy Bypass, as tools/godot_open.cmd passes: `powershell -File` alone fails under Windows' default
# (Restricted) policy, which refuses to run a script file.
. (Join-Path $PSScriptRoot 'setup\lib.ps1')
$godot = Find-FeGodot
if (-not $godot) {
    [Console]::Error.WriteLine('Godot binary not found (set GODOT=C:\path\to\Godot.exe, or run the setup bootstrap)')
    exit 2
}
$root = Split-Path -Parent $PSScriptRoot
$godotArgs = @()
if ($args -contains '--editor') { $godotArgs += '--editor' }
$godotArgs += '--path', $root
& $godot @godotArgs
exit $LASTEXITCODE
