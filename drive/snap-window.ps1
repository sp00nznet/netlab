# Capture one program's main window, not the whole desktop, to a PNG:
#   powershell -File snap-window.ps1 <process name> <out.png>
# It brings the window to the front first, so nothing covers it. netlab snap
# runs it here, or on a remote machine from a task in the desktop session.
param([Parameter(Mandatory)] [string] $Proc, [Parameter(Mandatory)] [string] $Out)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class NetlabWin {
    public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
'@
# Real pixels, so the window's rectangle and the screen copy agree on a scaled display.
[NetlabWin]::SetProcessDPIAware() | Out-Null
$p = Get-Process $Proc | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { throw "no window for process '$Proc'" }
$h = $p.MainWindowHandle
[NetlabWin]::ShowWindow($h, 9) | Out-Null          # SW_RESTORE
[NetlabWin]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 400
$r = New-Object NetlabWin+RECT
[NetlabWin]::GetWindowRect($h, [ref]$r) | Out-Null
$bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
[System.Drawing.Graphics]::FromImage($bmp).CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
"$Out ($($bmp.Width)x$($bmp.Height), $($p.MainWindowTitle))"
