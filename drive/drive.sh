#!/bin/sh
# drive.sh -- the driving library from the command line, for poking at an
# instance by hand or from another tool.
#
#   drive/drive.sh start a
#   drive/drive.sh press a 0x0008            # START (games/ps3recomp/buttons.sh)
#   drive/drive.sh press a 0x0040 10 3       # DOWN, held 10 polls, then wait 3 s
#   drive/drive.sh wait a "created room" 30
#   drive/drive.sh snap a a.png
#   drive/drive.sh rsh b 'Get-Process simpsons'
#   drive/drive.sh stop a
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
. "$NETLAB/drive/lib.sh"

cmd=$1
[ -n "$cmd" ] && [ -n "$2" ] || { sed -n '2,13p' "$0"; exit 2; }
shift
case $cmd in
    start|stop|press|snap|rsh) "$cmd" "$@" ;;
    wait) wait_log "$@" ;;
    *) echo "unknown command: $cmd" >&2; exit 2 ;;
esac
