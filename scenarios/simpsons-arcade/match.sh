#!/bin/bash
# match.sh <host machine> <joiner machine> <server machine> [out-dir]
# An online match of The Simpsons Arcade Game: psnr on the server machine,
# the host creates a match, the joiner quick-matches in, both pick a
# character, the host starts, and after a while both windows are captured.
# Machines are local/machines/<name>.env ("local" is this one); which network
# test that makes is in README.md here.
#
#   scenarios/simpsons-arcade/match.sh local testbox labserver captures/
NETLAB=$(cd "$(dirname "$0")/../.." && pwd)
. "$NETLAB/scenarios/lib.sh"
. "$NETLAB/games/ps3recomp/buttons.sh"
. "$NETLAB/scenarios/simpsons-arcade/menu.sh"

[ -n "$3" ] || { sed -n '2,9p' "$0"; exit 2; }
SCEN_OUT=${4:-$NETLAB/local/scenarios/simpsons-$(date +%Y%m%d-%H%M%S)}
psnr=$(addr "$3") || exit 1

role server psnr               "$3"
role host   simpsonsarcade-ps3 "$1" PLAYER=player1 PSNR=$psnr P2P_PORT=3658
role joiner simpsonsarcade-ps3 "$2" PLAYER=player2 PSNR=$psnr P2P_PORT=3659
trap 'down host; down joiner' EXIT

up server
up host
online_menu host || { echo "the host never reached Online Game"; exit 1; }
create_match host || { echo "the host didn't create a match"; exit 1; }
echo "the host created the match"

up joiner
online_menu joiner || { echo "the joiner never reached Online Game"; exit 1; }
quick_match joiner || { echo "the joiner didn't join"; exit 1; }
echo "the joiner joined"

sleep 15
press host $CROSS "" 4; press joiner $CROSS "" 6     # both pick their character
press host $CROSS "" 30                              # the host starts the game
echo "started"

sleep 30
snap host stage.png && snap joiner stage.png &&
    echo "in a working match both show Stage 1 with both players: $SCEN_OUT/{host,joiner}/stage.png"
