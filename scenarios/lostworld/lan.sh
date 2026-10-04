#!/bin/bash
# lan.sh <joiner machine> [fields] [out-dir]
# The Lost World, recompiled, two players over the network: this PC hosts as
# player 1, the joiner machine connects as player 2, and both play a script
# (lostworld's tools/netlab/*.env: coin, start, trigger pulls). The board is
# deterministic and netplay is lockstep, so the two machines must stay
# identical: each logs a hash of guest RAM every ten seconds, and the
# scenario passes when the two logs agree line for line and neither saw a
# desync.
#
#   scenarios/lostworld/lan.sh testbox
#
# The host runs from the checkout's build\ (MSVC, SDL2) rather than through
# a role, so it keeps the firewall rule that exe already has on this PC.
NETLAB=$(cd "$(dirname "$0")/../.." && pwd)
. "$NETLAB/scenarios/lib.sh"

[ -n "$1" ] || { sed -n '2,15p' "$0"; exit 2; }
JOINER=$1
FIELDS=${2:-4000}
SCEN_OUT=${3:-$NETLAB/local/scenarios/lostworld-lan-$(date +%Y%m%d-%H%M%S)}
PORT=7777
LW=$(awk '$1 == "lostworld-recomp" {print $2}' "$NETLAB/local/checkouts")
[ -n "$LW" ] || { echo "no lostworld-recomp in local/checkouts"; exit 1; }
mkdir -p "$SCEN_OUT/host" "$SCEN_OUT/joiner"

# Stage the local build for the joiner: the exe and SDL2 next to it.
mkdir -p "$LW/build-farm"
cp "$LW/build/lostworld.exe" "$LW/build/SDL2.dll" "$LW/build-farm/"

# The joiner needs the ROM images once, in its LW_ROMS.
( . "$NETLAB/local/machines/$JOINER.env"
  [ -n "$LW_ROMS" ] || { echo "$JOINER: set LW_ROMS in local/machines/$JOINER.env"; exit 1; }
  r=${LW_ROMS//\\//}
  if ! ssh -o BatchMode=yes ${JUMP:+-J "$JUMP"} "$SSH" "if (Test-Path '$r/lw_vrom.bin') { 'yes' }" | grep -q yes; then
    echo "copying the ROM images to $JOINER (once)"
    ssh -o BatchMode=yes ${JUMP:+-J "$JUMP"} "$SSH" "New-Item -ItemType Directory -Force '$r' | Out-Null"
    scp -q -o BatchMode=yes ${JUMP:+-o ProxyJump="$JUMP"} "$LW"/roms/lw_*.bin "$SSH:$r/"
  fi ) || exit 1

# Where the joiner reaches this PC: ADDR in local/machines/local.env.
HOSTADDR=$(addr local) || exit 1

echo "host: this PC, port $PORT, $FIELDS fields"
( cd "$LW" && ./build/lostworld.exe "$FIELDS" --env tools/netlab/host.env --host "$PORT" ) \
  > "$SCEN_OUT/host/run.log" 2>&1 &
HOSTPID=$!

role joiner lostworld-recomp "$JOINER" LW_ENV=tools/netlab/joiner.env LW_JOIN=$HOSTADDR:$PORT LW_FIELDS=$FIELDS
trap 'down joiner; kill $HOSTPID 2>/dev/null' EXIT
up joiner

wait $HOSTPID
sleep 5
( . "$NETLAB/local/machines/$JOINER.env"
  d=${DIR//\\//}/lostworld-recomp-joiner
  scp -q -o BatchMode=yes ${JUMP:+-o ProxyJump="$JUMP"} "$SSH:$d/run.log" "$SCEN_OUT/joiner/run.log"
  scp -q -o BatchMode=yes ${JUMP:+-o ProxyJump="$JUMP"} "$SSH:$d/shot.ppm" "$SCEN_OUT/joiner/shot.ppm" ) || true
cp "$LW/shot.ppm" "$SCEN_OUT/host/shot.ppm" 2>/dev/null
for r in host joiner; do
  [ -f "$SCEN_OUT/$r/shot.ppm" ] && python -c "import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2])" \
    "$SCEN_OUT/$r/shot.ppm" "$SCEN_OUT/$r/game.png" && rm -f "$SCEN_OUT/$r/shot.ppm"
done

grep -h "\[netplay\] field" "$SCEN_OUT/host/run.log"   > "$SCEN_OUT/host/hashes.txt"
grep -h "\[netplay\] field" "$SCEN_OUT/joiner/run.log" > "$SCEN_OUT/joiner/hashes.txt" 2>/dev/null
n=$(wc -l < "$SCEN_OUT/host/hashes.txt")
if grep -q "DESYNC" "$SCEN_OUT/host/run.log" "$SCEN_OUT/joiner/run.log" 2>/dev/null; then
  echo "FAIL: desync"; grep -h DESYNC "$SCEN_OUT"/*/run.log; exit 1
elif [ "$n" -gt 0 ] && cmp -s "$SCEN_OUT/host/hashes.txt" "$SCEN_OUT/joiner/hashes.txt"; then
  echo "PASS: $n RAM hashes agree on both machines; pictures in $SCEN_OUT/{host,joiner}/game.png"
else
  echo "FAIL: the hashes differ or are missing"; diff "$SCEN_OUT/host/hashes.txt" "$SCEN_OUT/joiner/hashes.txt" | head; exit 1
fi
