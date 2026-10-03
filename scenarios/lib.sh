# scenarios/lib.sh -- several programs on several machines, played together:
# an online match, two copies of a game on a LAN, a client and its server.
# Source it from a scenario script (a plain shell script, so menus can retry):
#
#   NETLAB=...; . "$NETLAB/scenarios/lib.sh"
#   role server psnr               labserver
#   role a      simpsonsarcade-ps3 local   PLAYER=player1 PSNR=$(addr labserver)
#   role b      simpsonsarcade-ps3 testbox PLAYER=player2 PSNR=$(addr labserver)
#   up server; up a
#   wait_log a "ManagerGetStatus() -> ONLINE" 120
#   press a 0x0008 "" 10
#   snap a a.png
#   down a
#
# A role is a project (projects/) on a machine (local/machines/), with its
# own settings (K=V, for its RUN line: no spaces in V). Every step is a
# netlab play step against that role's instance; screenshots land in
# $SCEN_OUT/<role>/. Each function returns the step's result, so a scenario
# can retry: `wait_log a "joined room" 8 || press a $SQUARE`.
: "${NETLAB:?set NETLAB to the recomp-netlab checkout before sourcing scenarios/lib.sh}"
SCEN_OUT=${SCEN_OUT:-.}
declare -A _project _machine _sets

role() {   # role <name> <project> <machine> [K=V ...]
  local r=$1; _project[$r]=$2; _machine[$r]=$3; shift 3; _sets[$r]="$*"
}
# The netlab options that make a command act on <role>'s instance.
_on() {
  local r=$1 kv
  printf '%s\n' --on "${_machine[$r]}" --as "$r"
  for kv in ${_sets[$r]}; do printf '%s\n' --set "$kv"; done
}
_nl() { local cmd=$1 r=$2; shift 2; mapfile -t o < <(_on "$r"); "$NETLAB/netlab" "$cmd" "${_project[$r]}" "$@" "${o[@]}"; }

up()   { _nl run "$1"; }                        # start <role>'s program on its machine
down() { _nl stop "$1" >/dev/null 2>&1 || true; }

# One step (see drive/play.sh) against <role>.
step() {
  local r=$1 f rc=0; shift
  f=$(mktemp); echo "$*" > "$f"
  _nl play "$r" "$f" --out "$SCEN_OUT/$r" >/dev/null || rc=$?
  rm -f "$f"; return $rc
}
wait_log() { step "$1" expect-log "$2" "${3:-60}"; }        # wait_log <role> <text> [secs]
wait_window() { step "$1" expect-window "$2" "${3:-60}"; }  # wait_window <role> <title> [secs]
press() { step "$1" pad "$2" $3 && sleep "${4:-2}"; }       # press <role> <mask> [hold] [settle]
key()   { step "$1" key "$2" && sleep "${3:-1}"; }          # key <role> <combo> [settle]
click() { step "$1" click "$2" "$3" && sleep "${4:-1}"; }   # click <role> <x> <y> [settle]
type_text() { local r=$1; shift; step "$r" type "$*"; }
snap()  { step "$1" snap "$2" && echo "$SCEN_OUT/$1/$2"; }  # snap <role> <name.png>

# The LAN address of a machine, for the others to reach it: ADDR in its
# local/machines file, else the host part of its SSH.
addr() {
  local f="$NETLAB/local/machines/$1.env" a
  a=$( [ -f "$f" ] && ( . "$f"; echo "${ADDR:-${SSH#*@}}" ) )
  [ -n "$a" ] || { echo "addr: no ADDR or SSH for machine '$1'" >&2; return 1; }
  echo "$a"
}
