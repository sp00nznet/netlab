#!/bin/bash
# lan.sh <host machine> <joiner machine> [out-dir]
# Red Alert 2 / Yuri's Revenge, recompiled, against itself over the LAN: the
# host opens the LAN lobby and creates a game, the joiner finds it, joins and
# accepts, the host starts, and both are checked in the game and captured.
# Each side plays a script of presses in the game's own input
# (redalert2-recomp's tools/lan/*.args), and the pictures come from the game
# itself (frames), never from the screen.
# Both machines must share a subnet (IPXEmu finds games by broadcast): the
# test VM on the LAN, nat/vm-to-lan.sh.
#
#   scenarios/redalert2/lan.sh local testbox
NETLAB=$(cd "$(dirname "$0")/../.." && pwd)
. "$NETLAB/scenarios/lib.sh"

[ -n "$2" ] || { sed -n '2,12p' "$0"; exit 2; }
SCEN_OUT=${3:-$NETLAB/local/scenarios/ra2-lan-$(date +%Y%m%d-%H%M%S)}

# frames <role>: the newest picture the game itself wrote (its args have
# --hd-voxels-dump lan-frames), into $SCEN_OUT/<role>/game.png. Not a screen
# capture: whatever covers the window (a console, the user's own programs)
# never ends up in it.
frames() {
  local r=$1 m=${_machine[$1]} d="$SCEN_OUT/$1" f
  mkdir -p "$d"
  if [ "$m" = local ]; then
    f=$(ls -t "$(awk '$1 == "redalert2-recomp" {print $2}' "$NETLAB/local/checkouts")"/lan-frames/frame_*.bmp 2>/dev/null | head -1)
    [ -n "$f" ] && cp "$f" "$d/game.bmp"
  else
    ( . "$NETLAB/local/machines/$m.env"
      f=$(ssh -o BatchMode=yes ${JUMP:+-J "$JUMP"} "$SSH" "(Get-ChildItem '$DIR/redalert2-recomp-$r/lan-frames/frame_*.bmp' | Sort-Object LastWriteTime | Select-Object -Last 1).FullName" | tr -d '\r')
      f=${f//\\//}                      # scp wants C:/... for a Windows path
      [ -n "$f" ] && scp -q -o BatchMode=yes ${JUMP:+-o ProxyJump="$JUMP"} "$SSH:$f" "$d/game.bmp" )
  fi
  [ -f "$d/game.bmp" ] && python -c "import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2])" "$d/game.bmp" "$d/game.png" &&
    rm -f "$d/game.bmp" && echo "$d/game.png"
}

role host   redalert2-recomp "$1" RA2_ARGS=tools/lan/host.args
role joiner redalert2-recomp "$2" RA2_ARGS=tools/lan/joiner.args
trap 'down host; down joiner' EXIT

up host
wait_log host "open 0xBC" 120 || { echo "the host never got to its game screen"; exit 1; }
echo "the host created the game"

up joiner
sleep 40
frames joiner >/dev/null && mv "$SCEN_OUT/joiner/game.png" "$SCEN_OUT/joiner/lobby.png"   # before it picks a game
wait_log joiner "open 0xBD" 120 || { echo "the joiner never joined"; exit 1; }
echo "the joiner joined"

wait_log host "Capture_Mouse" 180 || { echo "the host's game never started"; frames host; frames joiner; exit 1; }
wait_log joiner "Capture_Mouse" 60 || { echo "the joiner never got into the game"; frames joiner; exit 1; }
echo "both in the game"

sleep 30                                   # a frame or two of the match
frames host && frames joiner && echo "both games: $SCEN_OUT/{host,joiner}/game.png"
