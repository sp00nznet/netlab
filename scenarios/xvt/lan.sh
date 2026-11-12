#!/bin/bash
# lan.sh <host machine> <joiner machine> [xvt|bop] [out-dir]
# X-Wing vs TIE Fighter (or Balance of Power), recompiled, against itself over
# the LAN on the recomp's own DirectPlay (xvt-recomp's src/runtime/dplay.c,
# TCP 47700): the host names a session, picks Melee and begins; the joiner
# joins by the host's address; both pick craft, and the countdown launches
# the match. Passes when the joiner joined, both are drawing the mission in
# 3D, and neither faulted. The pictures are the game's own frames.
#
# Each side is started from a scheduled task (DirectPlay games want the
# logged-on desktop) and driven by the game's --keys script, not by netlab
# play. Windows machines only, each with the game at XVT_GAME and the
# unwrapped exe at XVT_EXE (Balance of Power: XVT_GAME\BalanceOfPower and
# bop.exe beside XVT_EXE). Every SSH call is retried: the test VM's sshd now
# and then answers "exec request failed".
#
#   scenarios/xvt/lan.sh testbox testbox2
#   scenarios/xvt/lan.sh testbox testbox2 bop
NETLAB=$(cd "$(dirname "$0")/../.." && pwd)
[ -n "$2" ] || { sed -n '2,18p' "$0"; exit 2; }
GAME=${3:-xvt}
OUT=${4:-$NETLAB/local/scenarios/$GAME-lan-$(date +%Y%m%d-%H%M%S)}
CHECKOUT=$(awk '$1 == "xvt" {print $2}' "$NETLAB/local/checkouts")
[ -n "$CHECKOUT" ] || { echo "no xvt checkout in local/checkouts"; exit 2; }
mkdir -p "$OUT/host" "$OUT/joiner"

# m <machine> <var>: a machine file's variable.
m() { ( . "$NETLAB/local/machines/$1.env"; eval "echo \"\${$2}\"" ); }
r() {   # r <machine> <powershell>: retried
  local ssh=$(m "$1" SSH) jump=$(m "$1" JUMP) o i
  for i in 1 2 3 4 5; do
    o=$(timeout 90 ssh -o BatchMode=yes ${jump:+-J "$jump"} "$ssh" "$2" 2>&1)
    echo "$o" | grep -q "exec request failed" || { echo "$o"; return 0; }
    sleep 3
  done
  echo "$o"; return 1
}
c() {   # c <from> <machine:path> or <machine:path> <to>: retried scp
  local i
  for i in 1 2 3; do timeout 180 scp -q -o BatchMode=yes "$@" && return 0; sleep 3; done
  echo "copy failed: $*"; return 1
}

if [ "$GAME" = bop ]; then EXE=boprecomp.exe; else EXE=xvtrecomp.exe; fi
[ -f "$CHECKOUT/build/$EXE" ] || { echo "build $CHECKOUT/build/$EXE first"; exit 2; }

LOGIN="5:esc,on:credits.txt,3:esc,on:fronttxt.txt,4:move:470:125,5:click:470:125"
SHOTS() { echo "90:shot=$1\\$2-1.png,120:shot=$1\\$2-2.png,150:shot=$1\\$2-3.png"; }
# Host: Host Game, session "net", Melee, Begin, Ready.
HOSTKEYS="$LOGIN,8:move:323:23,9:click:323:23,12:n,12.3:e,12.6:t,13:move:345:285,14:click:345:285,35:move:33:153,36:click:33:153,45:move:37:437,46:click:37:437,60:move:37:437,61:click:37:437"
# Joiner: Join Game (by Config.cfg's ipaddress), Ready.
JOINKEYS="$LOGIN,8:move:443:23,9:click:443:23,45:move:37:437,46:click:37:437"

# setup <role> <machine> <keys>
setup() {
  local role=$1 mc=$2 game exe dir=C:/netlab/xvt
  game=$(m "$mc" XVT_GAME); exe=$(m "$mc" XVT_EXE)
  if [ "$GAME" = bop ]; then game="$game\\BalanceOfPower"; exe="${exe%\\*}\\bop.exe"; fi
  r "$mc" "Get-Process xvtrecomp,boprecomp -EA 0 | Stop-Process -Force; New-Item -ItemType Directory -Force C:\\netlab\\xvt | Out-Null;
           Remove-Item C:\\netlab\\xvt\\$role-*.png, C:\\netlab\\xvt\\run.log -EA 0;
           Remove-NetFirewallRule -DisplayName 'netlab xvt $EXE' -EA 0;
           New-NetFirewallRule -DisplayName 'netlab xvt $EXE' -Direction Inbound -Action Allow -Program 'C:\\netlab\\xvt\\$EXE' -Profile Any | Out-Null" >/dev/null
  c "$CHECKOUT/build/$EXE" "$(m "$mc" SSH):$dir/$EXE" || exit 1
  printf '@echo off\r\ncd /d C:\\netlab\\xvt\r\nset XVT_DPLOG=1\r\nC:\\netlab\\xvt\\%s --run --exe %s --game %s --watchdog 300 --keys "%s,%s" > C:\\netlab\\xvt\\run.log 2>&1\r\n' \
    "$EXE" "$exe" "$game" "$3" "$(SHOTS 'C:\netlab\xvt' "$role")" > "$OUT/$role/run.cmd"
  c "$OUT/$role/run.cmd" "$(m "$mc" SSH):$dir/run.cmd" || exit 1
  r "$mc" "schtasks /Create /TN netlab-xvt /TR C:\\netlab\\xvt\\run.cmd /SC ONCE /ST 23:59 /IT /F | Out-Null" >/dev/null
}

HOSTADDR=$(m "$1" SSH); HOSTADDR=${HOSTADDR#*@}
setup host "$1" "$HOSTKEYS"
setup joiner "$2" "$JOINKEYS"
# The joiner joins the host's address.
CFG=$(m "$2" XVT_GAME); [ "$GAME" = bop ] && CFG="$CFG\\BalanceOfPower\\config2.cfg" || CFG="$CFG\\Config.cfg"
r "$2" "\$p='$CFG'; (Get-Content \$p) -replace '^ipaddress.*','ipaddress $HOSTADDR' | Set-Content -Encoding ascii \$p" >/dev/null

trap 'r "$1" "Get-Process xvtrecomp,boprecomp -EA 0 | Stop-Process -Force" >/dev/null; r "$2" "Get-Process xvtrecomp,boprecomp -EA 0 | Stop-Process -Force" >/dev/null' EXIT
r "$1" "schtasks /Run /TN netlab-xvt" >/dev/null
echo "host on $1 ($HOSTADDR), $GAME"
for i in $(seq 1 30); do r "$1" "Select-String -Quiet -Path C:\\netlab\\xvt\\run.log -Pattern 'hosting'" | grep -q True && break; sleep 3; done
r "$2" "schtasks /Run /TN netlab-xvt" >/dev/null
echo "joiner on $2"
for i in $(seq 1 60); do r "$1" "Test-Path C:\\netlab\\xvt\\host-3.png" | grep -q True && break; sleep 5; done
sleep 5

for role in host joiner; do
  mc=$1; [ $role = joiner ] && mc=$2
  c "$(m "$mc" SSH):C:/netlab/xvt/$role-*.png" "$OUT/$role/" 2>/dev/null
  c "$(m "$mc" SSH):C:/netlab/xvt/run.log" "$OUT/$role/run.log"
done

fail=0
grep -q "node 2 joined" "$OUT/host/run.log" || { echo "FAIL: nobody joined the host"; fail=1; }
grep -q "\] joined " "$OUT/joiner/run.log" || { echo "FAIL: the joiner did not join"; fail=1; }
for role in host joiner; do
  grep -q "=== fault" "$OUT/$role/run.log" && { echo "FAIL: the $role faulted"; fail=1; }
  grep -qE "frames: [1-9][0-9]* with 3D" "$OUT/$role/run.log" || { echo "FAIL: the $role never drew the mission"; fail=1; }
  grep -h "not provided" "$OUT/$role/run.log" | sort -u | sed "s/^/  $role: /"
done
echo "pictures: $OUT/{host,joiner}/*.png"
[ $fail = 0 ] && echo "PASS: $GAME LAN, host and joiner both in the match" || exit 1
