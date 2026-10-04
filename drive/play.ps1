# Play a steps file against a running program on this Windows desktop: the
# same steps as drive/play.sh (see there). netlab play/qa runs it here, or on
# a remote machine from a task in its desktop session.
#   play.ps1 -Steps <file> -Out <dir> -Window <title or ''> -Proc <name> -Log <run.log> [-Pad <mailbox>]
# Prints "ok"/"snap" lines and PASS, or FAIL at the first expect that times
# out (exit 1).
param(
    [Parameter(Mandatory)] [string] $Steps,
    [Parameter(Mandatory)] [string] $Out,
    [string] $Window = '',
    [Parameter(Mandatory)] [string] $Proc,
    [string] $Log = '',
    [string] $Pad = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class NetlabPlay {
    public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, IntPtr e);
    [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
    [DllImport("user32.dll")] public static extern short VkKeyScan(char c);
}
'@
[NetlabPlay]::SetProcessDPIAware() | Out-Null
New-Item -ItemType Directory -Force $Out | Out-Null

function Find-Window {
    $p = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and (
            ($Window -and $_.MainWindowTitle -like "*$Window*") -or $_.ProcessName -eq $Proc) } |
         Select-Object -First 1
    if ($p) { $p.MainWindowHandle } else { [IntPtr]::Zero }
}
# Bring the window to the front, with the keyboard. Windows lets only the
# foreground thread hand the foreground on, so borrow its input queue for the
# moment. Never by sending a keystroke: a stray Alt puts a game's window in
# menu mode, which freezes it (and its online opponent sees it drop).
function Focus {
    $h = Find-Window
    if ($h -ne [IntPtr]::Zero) {
        [NetlabPlay]::ShowWindow($h, 9) | Out-Null            # SW_RESTORE
        $fg = [NetlabPlay]::GetWindowThreadProcessId([NetlabPlay]::GetForegroundWindow(), [IntPtr]::Zero)
        $me = [NetlabPlay]::GetCurrentThreadId()
        $attached = $fg -ne $me -and [NetlabPlay]::AttachThreadInput($me, $fg, $true)
        [NetlabPlay]::BringWindowToTop($h) | Out-Null
        [NetlabPlay]::SetForegroundWindow($h) | Out-Null
        if ($attached) { [NetlabPlay]::AttachThreadInput($me, $fg, $false) | Out-Null }
        # Over anything that still covers it (the console that started it, a
        # dialog), then back among the others.
        [NetlabPlay]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 3) | Out-Null   # HWND_TOPMOST, no move/size
        [NetlabPlay]::SetWindowPos($h, [IntPtr](-2), 0, 0, 0, 0, 3) | Out-Null   # HWND_NOTOPMOST
        Start-Sleep -Milliseconds 200
    }
    $h
}
# What's on screen over the window's rectangle, with the window in front: a
# capture of the window alone (PrintWindow) misses its menus and pop-ups.
function Snap([string] $name) {
    $h = Focus
    if ($h -eq [IntPtr]::Zero) { throw "snap: no window" }
    $r = New-Object NetlabPlay+RECT
    [NetlabPlay]::GetWindowRect($h, [ref]$r) | Out-Null
    $b = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
    [System.Drawing.Graphics]::FromImage($b).CopyFromScreen($r.L, $r.T, 0, 0, $b.Size)
    $b.Save((Join-Path $Out $name), [System.Drawing.Imaging.ImageFormat]::Png)
    "snap $name"
}
# A step's key combo (ctrl+n, alt+f4, enter, down, w): pressed and released
# as real key events, scan codes included. SendKeys sends none, and games
# that read scan codes (SDL, DirectInput) never see its keys.
function Send-Combo([string] $combo) {
    $named = @{ enter=0x0D; esc=0x1B; tab=0x09; space=0x20; backspace=0x08; del=0x2E
                up=0x26; down=0x28; left=0x25; right=0x27; home=0x24; end=0x23; pgup=0x21; pgdn=0x22
                ctrl=0x11; control=0x11; alt=0x12; shift=0x10 }
    $extended = 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2E
    $vks = foreach ($part in $combo.ToLower().Split('+')) {
        if ($named.ContainsKey($part)) { $named[$part] }
        elseif ($part -match '^f([0-9]+)$') { 0x6F + [int]$Matches[1] }
        else { [NetlabPlay]::VkKeyScan($part[0]) -band 0xFF }
    }
    $ev = { param($vk, $up)
        $f = $(if ($vk -in $extended) { 1 } else { 0 }) -bor $(if ($up) { 2 } else { 0 })
        [NetlabPlay]::keybd_event([byte]$vk, [byte][NetlabPlay]::MapVirtualKey($vk, 0), $f, [IntPtr]::Zero) }
    foreach ($vk in $vks) { & $ev $vk $false }
    Start-Sleep -Milliseconds 60
    [array]::Reverse($vks)
    foreach ($vk in $vks) { & $ev $vk $true }
}
function Fail([string] $why) {
    "FAIL line ${n}: $why"
    try { Snap "fail-$n.png" | Out-Null } catch { }
    exit 1
}

$n = 0
foreach ($raw in Get-Content $Steps) {
    $n++
    $line = ($raw -replace '#.*$', '').Trim()
    if (-not $line) { continue }
    $w = $line -split '\s+'
    $cmd = $w[0]; $a = @($w | Select-Object -Skip 1)
    switch ($cmd) {
        'wait'  { Start-Sleep -Milliseconds ([double]$a[0] * 1000) }
        'key'   { Focus | Out-Null; Send-Combo $a[0] }
        'type'  { Focus | Out-Null; $t = ($a -join ' ') -replace '([+^%~(){}\[\]])', '{$1}'; [System.Windows.Forms.SendKeys]::SendWait($t) }
        'click' {
            $h = Focus; if ($h -eq [IntPtr]::Zero) { Fail 'click: no window' }
            $r = New-Object NetlabPlay+RECT; [NetlabPlay]::GetWindowRect($h, [ref]$r) | Out-Null
            [NetlabPlay]::SetCursorPos($r.L + [int]$a[0], $r.T + [int]$a[1]) | Out-Null
            [NetlabPlay]::mouse_event(2, 0, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 40
            [NetlabPlay]::mouse_event(4, 0, 0, 0, [IntPtr]::Zero)
        }
        'pad' {
            if (-not $Pad) { Fail 'pad: the machine has no PAD mailbox' }
            [IO.File]::WriteAllText($Pad, "$($a[0]) $($a[1])`n")
            for ($i = 0; $i -lt 100 -and (Get-Item $Pad).Length -gt 0; $i++) { Start-Sleep -Milliseconds 100 }
        }
        { $_ -in 'expect-window', 'expect-log' } {
            # The text may have spaces; a trailing number is the timeout.
            $t = 30
            if ($a.Count -gt 1 -and $a[-1] -match '^\d+$') { $t = [int]$a[-1]; $a = $a[0..($a.Count - 2)] }
            $text = $a -join ' '
            $has = if ($cmd -eq 'expect-window') {
                { [bool](Get-Process | Where-Object { $_.MainWindowTitle -like "*$text*" }) }
            } else {
                { (Test-Path $Log) -and (Select-String -Path $Log -Pattern $text -SimpleMatch -Quiet) }
            }
            for ($i = 0; $i -lt $t -and -not (& $has); $i++) { Start-Sleep 1 }
            if (-not (& $has)) { Fail "$($cmd -replace 'expect-') '$text' not there after ${t}s" }
            "ok   $($cmd -replace 'expect-') '$text'"
        }
        'snap' { try { Snap $a[0] } catch { Fail "snap $($a[0]): $_" } }
        default { Fail "unknown step '$cmd'" }
    }
}
'PASS'
