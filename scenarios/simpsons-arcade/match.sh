#!/bin/sh
# match.sh <host-inst> <joiner-inst> [out-dir]
# An online match of The Simpsons Arcade Game between two driven instances:
# the host creates a match, the joiner quick-matches in, both pick a
# character, the host starts, and after a while both screens are captured.
# Which machines, networks and psnr server that means is all in the
# instances' drive/inst/*.env; see README.md here.
NETLAB=$(cd "$(dirname "$0")/../.." && pwd)
. "$NETLAB/drive/lib.sh"
. "$NETLAB/games/ps3recomp/buttons.sh"
. "$NETLAB/scenarios/simpsons-arcade/menu.sh"

host=$1 joiner=$2 out=${3:-.}
[ -n "$host" ] && [ -n "$joiner" ] || { sed -n '2,7p' "$0"; exit 2; }

start "$host"
online_menu "$host" || { echo "$host never reached Online Game"; exit 1; }
create_match "$host" || { echo "$host didn't create a match"; exit 1; }
echo "$host created the match"

start "$joiner"
online_menu "$joiner" || { echo "$joiner never reached Online Game"; exit 1; }
quick_match "$joiner" || { echo "$joiner didn't join"; exit 1; }
echo "$joiner joined"

sleep 15
press "$host" $CROSS "" 4; press "$joiner" $CROSS "" 6     # both pick their character
press "$host" $CROSS "" 30                                 # the host starts the game
echo "started"

sleep 30
snap "$host" "$out/$host.png" && snap "$joiner" "$out/$joiner.png" &&
    echo "frames: $out/$host.png $out/$joiner.png -- in a working match both show Stage 1 with both players"
