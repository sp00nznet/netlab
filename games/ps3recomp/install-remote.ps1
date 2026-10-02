# Set up a Windows box to run a ps3recomp title for driving (drive/lib.sh,
# KIND=remote). Run it on the box, e.g. over SSH:
#
#   scp games/ps3recomp/install-remote.ps1 Admin@box:C:/netlab/
#   ssh Admin@box "powershell -ExecutionPolicy Bypass -File C:/netlab/install-remote.ps1 -GameDir C:/netlab/simpsons \
#       -Exe build/simpsons.exe -Elf vfs/PS3_GAME/USRDIR/EBOOT.elf -Psnr <psnr-host> -Player player2"
#
# It writes C:\netlab\run-game.cmd (the game with the driving environment)
# and a scheduled task that runs it in the logged-on desktop session: a game
# started straight from SSH runs in session 0, with no desktop to render to.
# Run it again to change the settings.
param(
    [Parameter(Mandatory)] [string] $GameDir,
    [Parameter(Mandatory)] [string] $Exe,
    [Parameter(Mandatory)] [string] $Elf,
    [string] $Psnr = '',
    [string] $Player = '',
    [int]    $P2pPort = 3658,
    [switch] $NetTrace,
    [string] $Dir = 'C:\netlab',
    [string] $Task = 'netlab-game'
)
$ErrorActionPreference = 'Stop'
$Dir = $Dir -replace '/', '\'
New-Item -ItemType Directory -Force $Dir, "$Dir\frames" | Out-Null

$flags = @()
if ($Psnr)   { $flags += "--psnr $Psnr" }
if ($Player) { $flags += "--username $Player" }
$trace = if ($NetTrace) { 'set PS3_NET_TRACE=1' } else { 'rem PS3_NET_TRACE off' }

@"
@echo off
rem Written by recomp-netlab games/ps3recomp/install-remote.ps1.
cd /d $($GameDir -replace '/', '\')
del /q $Dir\frames\*.ppm 2>nul
type nul > $Dir\pad.txt
set PS3_VERBOSE=0
set RSX_LIVE_DRAW=1
set PAD_FILE=$Dir\pad.txt
set LD_FRAME_DUMP=$Dir\frames
set LD_FRAME_DUMP_EVERY=60
set PS3_NET_P2P_PORT=$P2pPort
$trace
$($Exe -replace '/', '\') $($Elf -replace '/', '\') $($flags -join ' ') > $Dir\game.log 2>&1
"@ | Set-Content -Path "$Dir\run-game.cmd" -Encoding ascii

# /IT: only while the user is logged on, in their session. A test box logs
# its user on automatically (vm/README.md).
schtasks /Create /TN $Task /TR "$Dir\run-game.cmd" /SC ONCE /ST 23:59 /IT /F | Out-Null

# Let other players reach the game (its P2P port, TCP and UDP).
$exePath = Join-Path ($GameDir -replace '/', '\') ($Exe -replace '/', '\')
$rule = "netlab game ($(Split-Path $exePath -Leaf))"
Remove-NetFirewallRule -DisplayName $rule -EA 0
New-NetFirewallRule -DisplayName $rule -Direction Inbound -Action Allow -Program $exePath -Profile Any | Out-Null

"task $Task runs $Dir\run-game.cmd: $Exe $($flags -join ' ')"
