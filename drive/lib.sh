# drive/lib.sh -- drive running game instances, on this machine or another.
#
# Source it from a scenario script:   . "$NETLAB/drive/lib.sh"
#
# An instance is a running copy of a game you can steer from outside:
# buttons go in through a mailbox file the game polls, and you watch its log
# and the frames it dumps. Each is described by drive/inst/<name>.env (see
# the examples there); the functions take the instance name:
#
#   start <inst>                  launch it (fresh log, empty mailbox)
#   stop <inst>
#   press <inst> <mask> [hold] [settle]
#                                 write a button to the mailbox, wait until
#                                 the game took it, then wait <settle> seconds
#   wait_log <inst> <text> [secs] until <text> shows up in its log (exit 1 if not)
#   snap <inst> <out.png>         the newest dumped frame, as a PNG
#   rsh <inst> <powershell>       run a command on a remote instance's machine
#
# What the game has to provide is in docs/driving.md; games/ has the recipe
# for each runtime we drive.

: "${NETLAB:?set NETLAB to the recomp-netlab checkout before sourcing drive/lib.sh}"

# Run "$@" with <inst>'s settings in the environment (a subshell, exported so
# launchers see them).
_with() {
    _f="$NETLAB/drive/inst/$1.env"
    [ -f "$_f" ] || { echo "no instance '$1' ($_f)" >&2; return 2; }
    shift
    ( set -a; . "$_f"; set +a; "$@" )
}

_ssh() { ssh -o BatchMode=yes -o ConnectTimeout=10 ${JUMP:+-J "$JUMP"} "$SSH" "$@"; }
_scp_from() { scp -q -o BatchMode=yes ${JUMP:+-o ProxyJump="$JUMP"} "$SSH:$1" "$2"; }

rsh() { _with "$1" _rsh_in "$@"; }
_rsh_in() { shift; _ssh "$@"; }

start() { _with "$1" _start_in; }
_start_in() {
    case $KIND in
    local)
        : > "$PAD"
        (eval "$START") &
        ;;
    remote)
        # A scheduled task runs the game in the logged-on desktop session;
        # games started over SSH run headless in session 0. End the task
        # first: it stays "Running" after its game is killed, and /Run then
        # silently does nothing.
        _ssh "Get-Process '$PROC' -EA 0 | Stop-Process -Force; schtasks /End /TN '$TASK' | Out-Null; \
              Start-Sleep 1; Remove-Item '$LOG' -EA 0; schtasks /Run /TN '$TASK' | Out-Null"
        ;;
    esac
}

stop() { _with "$1" _stop_in; }
_stop_in() {
    case $KIND in
    local)  eval "${STOP:-true}" ;;
    remote) _ssh "Get-Process '$PROC' -EA 0 | Stop-Process -Force; schtasks /End /TN '$TASK' | Out-Null" ;;
    esac
}

press() { _with "$1" _press_in "$@"; }
_press_in() {
    mask=$2 hold=${3:-} settle=${4:-2}
    case $KIND in
    local)
        printf '%s %s\n' "$mask" "$hold" > "$PAD"
        i=0; while [ -s "$PAD" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done
        ;;
    remote)
        _ssh "[IO.File]::WriteAllText('$PAD', '$mask $hold' + [char]10); \
              for (\$i=0; \$i -lt 100 -and (Get-Item '$PAD').Length -gt 0; \$i++) { Start-Sleep -Milliseconds 100 }"
        ;;
    esac
    sleep "$settle"
}

wait_log() { _with "$1" _wait_in "$@"; }
_wait_in() {
    text=$2 secs=${3:-60} i=0
    while [ $i -lt "$secs" ]; do
        case $KIND in
        local)  grep -aqF -- "$text" "$LOG" 2>/dev/null && return 0 ;;
        remote) _ssh "if ((Test-Path '$LOG') -and (Select-String -Path '$LOG' -Pattern '$text' -SimpleMatch -Quiet)) { exit 0 } else { exit 1 }" && return 0 ;;
        esac
        sleep 1; i=$((i+1))
    done
    return 1
}

snap() { _with "$1" _snap_in "$@"; }
_snap_in() {
    out=$2
    tmp=${TMPDIR:-/tmp}/netlab-snap-$$.ppm
    case $KIND in
    local)
        f=$(ls -t "$FRAMES"/*.ppm 2>/dev/null | head -1)
        [ -n "$f" ] || { echo "no frames in $FRAMES" >&2; return 1; }
        cp "$f" "$tmp"
        ;;
    remote)
        f=$(_ssh "(Get-ChildItem '$FRAMES' -Filter *.ppm | Sort-Object LastWriteTime | Select-Object -Last 1).Name" | tr -d '\r')
        [ -n "$f" ] || { echo "no frames in $FRAMES" >&2; return 1; }
        _scp_from "$FRAMES/$f" "$tmp"
        ;;
    esac
    ffmpeg -loglevel error -y -i "$tmp" -vf scale=640:-1 "$out" && rm -f "$tmp"
}
