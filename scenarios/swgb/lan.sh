#!/bin/bash
# lan.sh <host machine> <joiner machine> [WxH] [out-dir]
# Star Wars: Galactic Battlegrounds, recompiled, against itself over the LAN
# on pcrecomp's DirectPlay (runtime/native32/dplay32.c, TCP and UDP 47700):
# the host creates a game from the Multiplayer screen, the joiner finds it
# (Show Games) and joins, both are ready and the host starts it. Passes when
# the joiner joined, both reached the game (the watchdog's "[state] ... mode
# 4") and neither faulted. The pictures are the game's own frames, a minute
# and three minutes in; WxH plays at that size on both (the remaster's
# --res), else 800x600.
#
# Each side runs from a scheduled task in its logged-on session (the battle
# stalls in an SSH session) with the game's --keys script. Windows machines
# only, each with C:\netlab\swgb holding game\ (the installed game), and
# work\Battlegrounds.exe, disc 2 mounted, and TCP and UDP 47700 open inbound.
# The build is the checkout's build-farm-o1\ (--slot o1 -- -DGEN_OPT=/O1),
# else build-farm\.
#
#   scenarios/swgb/lan.sh testbox2 testbox3
#   scenarios/swgb/lan.sh testbox2 testbox3 1920x1080
NETLAB=$(cd "$(dirname "$0")/../.." && pwd)
[ -n "$2" ] || { sed -n '2,20p' "$0"; exit 2; }
if [ -z "$SWGB_LAN_LOCKED" ]; then   # both machines, for the whole run
  SWGB_LAN_LOCKED=1 exec "$NETLAB/netlab" lock "$1" "$2" -- bash "$0" "$@"
fi
RES=$3
OUT=${4:-$NETLAB/local/scenarios/swgb-lan-$(date +%Y%m%d-%H%M%S)}
CHECKOUT=$(awk '$1 == "swgb-recomp" {print $2}' "$NETLAB/local/checkouts")
[ -n "$CHECKOUT" ] || { echo "no swgb-recomp checkout in local/checkouts"; exit 2; }
EXE=$CHECKOUT/build-farm-o1/swgbrecomp.exe
[ -f "$EXE" ] || EXE=$CHECKOUT/build-farm/swgbrecomp.exe
[ -f "$EXE" ] || { echo "build swgb-recomp first"; exit 2; }
mkdir -p "$OUT/host" "$OUT/joiner"

m() { ( . "$NETLAB/local/machines/$1.env"; eval "echo \"\${$2}\"" ); }
r() { timeout 90 ssh -o BatchMode=yes "$(m "$1" SSH)" "$2"; }

# The menus are 800x600 at any size: Multiplayer, a player's name (typed into
# the New Player dialog), then Create, or Show Games + the first game + Join;
# I'm Ready!; the host's Start Game.
MP="20:move:275:410,21:click:275:410,30:%s,31:o,33:move:323:352,34:click:323:352"
HOSTKEYS="$(printf "$MP" h),45:move:600:453,46:click:600:453,76:move:88:517,77:click:88:517,84:move:118:568,85:click:118:568"
JOINKEYS="$(printf "$MP" j),55:move:600:203,56:click:600:203,63:move:600:240,64:click:600:240,66:move:600:403,67:click:600:403,72:move:88:517,73:click:88:517"

setup() {   # setup <role> <machine> <keys>
  local role=$1 mc=$2 dir='C:\netlab\swgb'
  r "$mc" "Get-Process swgbrecomp -EA 0 | Stop-Process -Force; Remove-Item C:\\netlab\\swgb\\out\\lan-$role* -EA 0" >/dev/null
  timeout 600 scp -q -o BatchMode=yes "$EXE" "$(m "$mc" SSH):C:/netlab/swgb/build/swgbrecomp.exe" || exit 1
  printf '@echo off\r\ncd /d %s\r\nif not exist out mkdir out\r\nset PCRECOMP_MUTE=1\r\nset PCRECOMP_DPLOG=1\r\nbuild\\swgbrecomp.exe --run --headless %s --watchdog 280 --keys "%s,140:shot=out\\lan-%s-1.bmp,260:shot=out\\lan-%s-2.bmp" > out\\lan-%s.log 2>&1\r\n' \
    "$dir" "${RES:+--res $RES}" "$3" "$role" "$role" "$role" > "$OUT/$role/run.cmd"
  timeout 60 scp -q -o BatchMode=yes "$OUT/$role/run.cmd" "$(m "$mc" SSH):C:/netlab/swgb/run-lan.cmd" || exit 1
  r "$mc" "schtasks /Create /TN netlab-swgb-lan /TR C:\\netlab\\swgb\\run-lan.cmd /SC ONCE /ST 23:59 /IT /F | Out-Null" >/dev/null
}
setup host "$1" "$HOSTKEYS"
setup joiner "$2" "$JOINKEYS"
r "$1" "schtasks /Run /TN netlab-swgb-lan" >/dev/null
sleep 3
r "$2" "schtasks /Run /TN netlab-swgb-lan" >/dev/null
echo "host on $1, joiner on $2${RES:+, $RES}"
sleep 270
for mc in "$1" "$2"; do
  for i in $(seq 1 30); do [ "$(r "$mc" "(Get-ScheduledTask -TaskName netlab-swgb-lan).State" | tr -d '\r')" = Running ] || break; sleep 5; done
done

fetch() { timeout 300 scp -q -o BatchMode=yes "$(m "$2" SSH):C:/netlab/swgb/out/lan-$1*" "$OUT/$1/"; }
fetch host "$1"; fetch joiner "$2"
fail=0
grep -q "node 2 joined" "$OUT/host/lan-host.log" || { echo "FAIL: the joiner never reached the host"; fail=1; }
grep -q "\] joined " "$OUT/joiner/lan-joiner.log" || { echo "FAIL: the joiner did not join"; fail=1; }
for role in host joiner; do
  grep -q "=== fault" "$OUT/$role/lan-$role.log" && { echo "FAIL: $role faulted"; fail=1; }
  grep -q "\[state\] .* mode 4" "$OUT/$role/lan-$role.log" || { echo "FAIL: $role never reached the game"; fail=1; }
  grep -h "not provided" "$OUT/$role/lan-$role.log" | sort -u | sed "s/^/  $role: /"
done
echo "pictures: $OUT/<role>/lan-*.bmp"
[ $fail = 0 ] && echo "PASS: SWGB LAN, host and joiner both in the game${RES:+ at $RES}" || exit 1
