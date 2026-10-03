#!/bin/bash
# two-player-lan.sh <project> <host machine> <joiner machine> [out-dir]
# Two copies of a game on one LAN: one hosts, the other joins, both screens
# captured in the game. The starting point for any two-player LAN test (RA2 vs
# RA2): copy it, keep the roles, and replace the steps marked below with the
# game's own. As it is, it starts both and captures both windows.
#
#   scenarios/two-player-lan.sh ra2 local testbox
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
. "$NETLAB/scenarios/lib.sh"

[ -n "$3" ] || { sed -n '2,8p' "$0"; exit 2; }
SCEN_OUT=${4:-$NETLAB/local/scenarios/$1-lan-$(date +%Y%m%d-%H%M%S)}

role host   "$1" "$2" PLAYER=player1
role joiner "$1" "$3" PLAYER=player2
trap 'down host; down joiner' EXIT

up host
up joiner

# --- the game's steps go here. For a game with a menu-driven LAN lobby:
#
#   wait_window host "<window title>" 60
#   click host <x> <y> 3                    # Network / LAN
#   click host <x> <y> 3                    # Host a game
#   wait_log host "<the line that says the game is hosted>" 30 || exit 1
#
#   wait_window joiner "<window title>" 60
#   click joiner <x> <y> 3                  # Network / LAN
#   click joiner <x> <y> 5                  # the host's game in the list
#   wait_log joiner "<joined>" 30 || exit 1
#
#   click host <x> <y> 30                   # Start
# ---

sleep 30                                    # or: wait_window <role> "<title>" 60
snap host game.png
snap joiner game.png
echo "both windows: $SCEN_OUT/{host,joiner}/game.png"
