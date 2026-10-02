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
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
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
function Focus {
    $h = Find-Window
    if ($h -ne [IntPtr]::Zero) { [NetlabPlay]::ShowWindow($h, 9) | Out-Null; [NetlabPlay]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 150 }
    $h
}
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
# A step's key combo (ctrl+n, alt+f4, enter, down) in SendKeys' notation.
function SendKeys-Combo([string] $combo) {
    $named = @{ enter='{ENTER}'; esc='{ESC}'; tab='{TAB}'; space=' '; backspace='{BACKSPACE}'; del='{DELETE}'
                up='{UP}'; down='{DOWN}'; left='{LEFT}'; right='{RIGHT}'; home='{HOME}'; end='{END}'
                pgup='{PGUP}'; pgdn='{PGDN}' }
    $mods = ''; $key = ''
    foreach ($part in $combo.ToLower().Split('+')) {
        switch -regex ($part) {
            '^(ctrl|control)$' { $mods += '^'; break }
            '^alt$'            { $mods += '%'; break }
            '^shift$'          { $mods += '+'; break }
            '^f([0-9]+)$'      { $key = "{F$($Matches[1])}"; break }
            default {
                if ($named.ContainsKey($part)) { $key = $named[$part] }
                elseif ('+^%~(){}[]'.Contains($part)) { $key = "{$part}" }
                else { $key = $part }
            }
        }
    }
    $mods + $key
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
        'key'   { Focus | Out-Null; [System.Windows.Forms.SendKeys]::SendWait((SendKeys-Combo $a[0])) }
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
