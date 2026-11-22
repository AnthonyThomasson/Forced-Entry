# Start the Von decision server, or check that it can start (Windows PowerShell 5.1; tools/von/boot.sh is the Mac twin
# with the same interface). It installs nothing: when the setup is missing or broken it exits fast with one cause line
# and the bootstrap command that fixes it.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\von\boot.ps1 [-Check] [-Port N] [-BindHost H] [-Device D]
#     (no flag)    start `von serve --host H --port N --device D` (defaults 127.0.0.1, 8000, cpu) from <von home>, the
#                  folder Von reads checkpoints\von-1.2 from (it has no flag or variable for that). This script stays
#                  alive as the server's parent (a tool that finds the server by walking a game's descendants, like
#                  tools/von_stop.sh, needs that chain), writes the server's output as its own, and exits with the
#                  server's exit code. The server runs in a job object that kills it when this script ends for any
#                  reason, so ending this script (a kill of its pid, Ctrl+C, closing its window) never leaves a server.
#     -Check       do not start: exit 0 when the setup is complete and `von --version` runs, else 3 with the cause
#   <von home> is Get-FeVonHome (FORCED_ENTRY_HOME); the venv is <von home>\venv, the weights <von home>\checkpoints\von-1.2
#   (tools\setup\bootstrap.ps1 builds both, pinned in tools\setup\versions.env).
# Exit codes: 0 -Check passed (a started server exits with its own code); 2 a bad argument; 3 the setup is missing or
# broken. The cause is one line on stderr, `von: <cause>. Fix: <the bootstrap command>`, and -Check says `von: ready`.
# It needs -ExecutionPolicy Bypass, as the dot-sourced tools\setup\lib.ps1 does (see there).
[CmdletBinding(PositionalBinding = $false)]
param([switch]$Check, [string]$Port = '8000', [string]$BindHost = '127.0.0.1', [string]$Device = 'cpu',
      [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
. (Join-Path $PSScriptRoot '..\setup\lib.ps1')

# Bad arguments end the run with exit code 2 and a message, as boot.sh does.
if ($Rest) {
    [Console]::Error.WriteLine("von: unknown argument: $($Rest -join ' ') (boot.ps1 [-Check] [-Port N] [-BindHost H] [-Device D])")
    exit 2
}
if ($Port -notmatch '^\d+$' -or -not $BindHost -or -not $Device) {
    [Console]::Error.WriteLine('von: -Port needs a number, -BindHost and -Device a value')
    exit 2
}

$vonHome = Get-FeVonHome
$venv = Join-Path $vonHome 'venv'
$bin = Join-Path $venv 'Scripts'
$von = Join-Path $bin 'von.exe'
$fix = 'powershell -ExecutionPolicy Bypass -File tools\setup\bootstrap.ps1'

function Stop-Broken([string]$cause) {
    [Console]::Error.WriteLine("von: $cause. Fix: $fix")
    exit 3
}

if (-not (Test-Path -LiteralPath $venv -PathType Container)) { Stop-Broken "no Von venv at $venv" }
$cfg = Join-Path $venv 'pyvenv.cfg'
if (Test-Path -LiteralPath $cfg) {
    $line = Get-Content -LiteralPath $cfg | Where-Object { $_ -match '^\s*home\s*=' } | Select-Object -First 1
    if ($line) {
        $baseHome = ($line -replace '^\s*home\s*=\s*', '').Trim()
        if (-not (Test-Path -LiteralPath $baseHome -PathType Container)) {
            Stop-Broken "the Von venv's base Python is gone (pyvenv.cfg home = $baseHome)"
        }
    }
}
$venvPython = Join-Path $bin 'python.exe'
if (-not (Test-Path -LiteralPath $venvPython)) { Stop-Broken "the Von venv's Python is missing ($venvPython)" }
& $venvPython -c 'pass' 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Stop-Broken "the Von venv's Python does not run ($bin\python.exe)" }
if (-not (Test-Path -LiteralPath $von)) { Stop-Broken "von-sdk is not installed in the Von venv ($von is missing)" }
foreach ($f in @((Get-FeManifest)['VON_WEIGHT_FILES'] -split ',')) {
    $p = Join-Path $vonHome "checkpoints\von-1.2\$f"
    if (-not (Test-Path -LiteralPath $p) -or (Get-Item -LiteralPath $p).Length -eq 0) { Stop-Broken "the Von weights are missing ($p)" }
}

if ($Check) {
    & $von --version 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-Broken "'von --version' fails in the Von venv" }
    Write-Output "von: ready ($vonHome)"
    exit 0
}

# The caller's PYTHONPATH (tools/setup/lib.sh's fe_use_python sets one) is not the server's business.
Remove-Item Env:PYTHONPATH, Env:PYTHONHOME -ErrorAction SilentlyContinue
$env:PYTHONUNBUFFERED = '1'

# A job object that kills everything in it when its last handle closes: this process holds the only one, so the
# server (the von.exe launcher, the python under it and anything that starts) dies whenever this process does.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FeJob {
    [StructLayout(LayoutKind.Sequential)] struct Basic {
        public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize; public uint ActiveProcessLimit;
        public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)] struct Io {
        public ulong a, b, c, d, e, f;
    }
    [StructLayout(LayoutKind.Sequential)] struct Extended {
        public Basic BasicLimitInformation; public Io IoInfo; public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit; public UIntPtr PeakProcessMemoryUsed; public UIntPtr PeakJobMemoryUsed;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr attrs, string name);
    [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int cls, IntPtr info, uint len);
    [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    static IntPtr job = IntPtr.Zero;
    public static bool Adopt(IntPtr process) {
        if (job == IntPtr.Zero) {
            job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero) return false;
            Extended info = new Extended();
            info.BasicLimitInformation.LimitFlags = 0x2000;  // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            int size = Marshal.SizeOf(typeof(Extended));
            IntPtr mem = Marshal.AllocHGlobal(size);
            Marshal.StructureToPtr(info, mem, false);
            bool set = SetInformationJobObject(job, 9, mem, (uint)size);  // JobObjectExtendedLimitInformation
            Marshal.FreeHGlobal(mem);
            if (!set) return false;
        }
        return AssignProcessToJobObject(job, process);
    }
}
'@

Set-Location -LiteralPath $vonHome
$server = Start-Process -FilePath $von -ArgumentList 'serve', '--host', $BindHost, '--port', $Port, '--device', $Device `
    -WorkingDirectory $vonHome -NoNewWindow -PassThru
$null = $server.Handle  # keeps the handle, so ExitCode is readable after the exit
# Best effort: a parent that is itself in a job that forbids nesting cannot bind it; say so, the server still runs.
if (-not [FeJob]::Adopt($server.Handle)) {
    [Console]::Error.WriteLine('von: warning: the server could not be bound to this script, so ending this script will not end it')
}
$server.WaitForExit()
exit $server.ExitCode
