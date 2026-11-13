#!/bin/bash
# lan.sh <host machine> <joiner machine> [out-dir]
# X-Wing Alliance, recompiled (xwa2's xwarecomp), against itself over the LAN
# on the recomp's own DirectPlay (src/runtime/dplay.c, TCP 47700): the host
# picks Combat Simulator > Multiplayer > Host Game > TCP/IP > Begin; the joiner
# picks Join Game > TCP/IP, types the host's address and begins; in the
# lobby the host assigns both to craft and both ready. Passes when
# the joiner joined the host's session, both fly the skirmish in 3D, and
# neither faulted. The pictures are
# the game's own frames, every 15 s.
#
# Each side runs from a scheduled task (the logged-on desktop) and is driven
# by the game's --keys script. Windows machines with the Steam game at
# XWA2_GAME and the Steamless-unwrapped exe at XWA2_EXE. SSH calls are retried.
#
#   scenarios/xwa/lan.sh testbox testbox2
#   HOSTMORE="<more host keys>" JOINMORE="<more joiner keys>" scenarios/xwa/lan.sh testbox testbox2
NETLAB=$(cd "$(dirname "$0")/../.." && pwd)
[ -n "$2" ] || { sed -n '2,15p' "$0"; exit 2; }
OUT=${3:-$NETLAB/local/scenarios/xwa-lan-$(date +%Y%m%d-%H%M%S)}
CHECKOUT=$(awk '$1 == "xwa2" {print $2}' "$NETLAB/local/checkouts")
[ -n "$CHECKOUT" ] || { echo "no xwa2 checkout in local/checkouts"; exit 2; }
EXE=xwarecomp.exe
[ -f "$CHECKOUT/build/$EXE" ] || { echo "build $CHECKOUT/build/$EXE first"; exit 2; }
mkdir -p "$OUT/host" "$OUT/joiner"

m() { ( . "$NETLAB/local/machines/$1.env"; eval "echo \"\${$2}\"" ); }
r() {
  local ssh=$(m "$1" SSH) jump=$(m "$1" JUMP) o i
  for i in 1 2 3 4 5; do
    o=$(timeout 90 ssh -o BatchMode=yes ${jump:+-J "$jump"} "$ssh" "$2" 2>&1)
    echo "$o" | grep -q "exec request failed" || { echo "$o"; return 0; }
    sleep 3
  done
  echo "$o"; return 1
}
c() { local i; for i in 1 2 3; do timeout 600 scp -q -o BatchMode=yes "$@" && return 0; sleep 3; done; echo "copy failed: $*"; return 1; }

WATCHDOG=${WATCHDOG:-330}
# In the skirmish lobby the host drags both players onto the two teams' craft,
# the joiner readies, then the host's Ready launches. (Times count from the
# multiplayer screen; the joiner reaches it about 45 s after the host.)
HOSTMORE=${HOSTMORE-"100:move:493:129,100.5:press:493:129,101:move:300:115,101.5:move:200:101,102:release:200:101,106:move:493:129,106.5:press:493:129,107:move:300:200,107.5:move:180:236,108:release:180:236,145:move:553:460,150:click:553:460,170:click:553:460,190:click:553:460,210:click:553:460,230:click:553:460,250:click:553:460"}
JOINMORE=${JOINMORE-"70:move:553:460,80:click:553:460"}
# (The address field keeps the last one typed: it is cleared first.)
# Intro (or straight to the concourse), the family room, the Combat Simulator door,
# Multiplayer.
NAV="on:intro_final.snm|concourse.lst,2:move:620:20,2.2:click:620:20,on:familyroom.cbm,3:move:100:150,4:click:100:150,9:click:100:150,on:podopen.cbm,6:move:320:200,7:click:320:200,on:multiplayer.cbm"
HOSTKEYS="$NAV,3:move:185:110,4:click:185:110,7:move:268:383,8:click:268:383,11:move:550:463,12:click:550:463${HOSTMORE:+,$HOSTMORE}"
HOSTADDR=$(m "$1" SSH); HOSTADDR=${HOSTADDR#*@}
JOINKEYS="$NAV,3:move:454:100,4:click:454:100,7:move:268:383,8:click:268:383,9:move:460:150,9.5:click:460:150,9.7:bksp,9.9:bksp,10.1:bksp,10.3:bksp,10.5:bksp,10.7:bksp,10.9:bksp,11.1:bksp,11.3:bksp,11.5:bksp,11.7:bksp,11.9:bksp,12.1:bksp,12.3:bksp,12.5:bksp,12.7:bksp,12.9:bksp,13.1:bksp,13.3:bksp,13.5:bksp,14:type:$HOSTADDR,18:move:550:463,18.5:click:550:463${JOINMORE:+,$JOINMORE}"
SHOTS() { local s="" t; for t in $(seq 15 15 $((WATCHDOG - 20))); do s="$s,$t:shot=$1\\$2-$t.png"; done; echo "${s#,}"; }

# setup <role> <machine> <keys>: the shots count from the multiplayer screen
setup() {
  local role=$1 mc=$2 dir=C:/netlab/xwa2
  r "$mc" "Get-Process xwarecomp -EA 0 | Stop-Process -Force; New-Item -ItemType Directory -Force C:\\netlab\\xwa2 | Out-Null;
           Remove-Item C:\\netlab\\xwa2\\$role-*.png, C:\\netlab\\xwa2\\run.log -EA 0;
           Remove-NetFirewallRule -DisplayName 'netlab xwa2' -EA 0;
           New-NetFirewallRule -DisplayName 'netlab xwa2' -Direction Inbound -Action Allow -Program 'C:\\netlab\\xwa2\\$EXE' -Profile Any | Out-Null" >/dev/null
  c "$CHECKOUT/build/$EXE" "$(m "$mc" SSH):$dir/$EXE" || exit 1
  printf '@echo off\r\ncd /d C:\\netlab\\xwa2\r\nset XVT_DPLOG=1\r\nC:\\netlab\\xwa2\\%s --run --exe %s --game %s --watchdog %s --keys "%s,%s" > C:\\netlab\\xwa2\\run.log 2>&1\r\n' \
    "$EXE" "$(m "$mc" XWA2_EXE)" "$(m "$mc" XWA2_GAME)" "$WATCHDOG" "$3" "$(SHOTS 'C:\netlab\xwa2' "$role")" > "$OUT/$role/run.cmd"
  c "$OUT/$role/run.cmd" "$(m "$mc" SSH):$dir/run.cmd" || exit 1
  r "$mc" "schtasks /Create /TN netlab-xwa2 /TR C:\\netlab\\xwa2\\run.cmd /SC ONCE /ST 23:59 /IT /F | Out-Null" >/dev/null
}

setup host "$1" "$HOSTKEYS"
setup joiner "$2" "$JOINKEYS"
stop_all() { for mc in "$1" "$2"; do r "$mc" "Get-Process xwarecomp -EA 0 | Stop-Process -Force" >/dev/null; done; }
trap 'stop_all "$1" "$2"' EXIT
r "$1" "schtasks /Run /TN netlab-xwa2" >/dev/null
echo "host on $1 ($HOSTADDR)"
for i in $(seq 1 60); do r "$1" "Select-String -Quiet -Path C:\netlab\xwa2\run.log -Pattern 'hosting'" | grep -q True && break; sleep 3; done
r "$2" "schtasks /Run /TN netlab-xwa2" >/dev/null; echo "joiner on $2"
for i in $(seq 1 $((WATCHDOG / 5 + 20))); do r "$1" "Get-Process xwarecomp -EA 0" | grep -q xwarecomp || break; sleep 5; done
sleep 3

for role in host joiner; do mc=$1; [ $role = joiner ] && mc=$2
  c "$(m "$mc" SSH):C:/netlab/xwa2/$role-*.png" "$OUT/$role/" 2>/dev/null; c "$(m "$mc" SSH):C:/netlab/xwa2/run.log" "$OUT/$role/run.log"; done

fail=0
grep -q "node 2 joined" "$OUT/host/run.log" || { echo "FAIL: the joiner never reached the host"; fail=1; }
grep -q "\] joined " "$OUT/joiner/run.log" || { echo "FAIL: the joiner did not join"; fail=1; }
for role in host joiner; do
  grep -q "=== fault" "$OUT/$role/run.log" && { echo "FAIL: $role faulted"; fail=1; }
  grep -qE "frames: [1-9][0-9]* with 3D|first 3D frame" "$OUT/$role/run.log" || { echo "FAIL: $role never flew"; fail=1; }
  grep -h "not provided" "$OUT/$role/run.log" | sort -u | sed "s/^/  $role: /"
done
echo "pictures: $OUT/<role>/*.png"
[ $fail = 0 ] && echo "PASS: XWA LAN, host and joiner fly the skirmish together" || exit 1
