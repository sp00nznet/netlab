#!/bin/bash
# Build a game on the least-loaded farm builder (farm/builders), with its
# toolset (toolsets/<name>/build.sh). The game and the repos it builds against
# are synced to the builder's /work/<basename>; after the first sync only files
# changed since the last one go over, so the builder's ninja dir stays warm.
# The exes, pdbs and maps come back to <game-dir>/build-farm/, and go to
# the share (/share/drops/<game>/<job>/) when the builder has the share.
#
# usage: farm/build.sh [--full] <toolset> <game-dir> [dep-dir...] [-- cmake-args...]
#   farm/build.sh cmake     ~/src/pc/forcecommander ~/src/pc/tools -- -DFOCOM_TRACE=ON
#   farm/build.sh cmake     ~/src/pc/rol ~/src/pc/pcrecomp-rol -- -DXWIN_ARCH=x86 -DGEN_OPT=/O1
#   farm/build.sh cmake     ~/src/xbox/burnout3 ~/src/xbox/xboxrecomp
#   farm/build.sh ps3recomp ~/src/ps3games/simpsons ~/src/ps3-simp
# Deps land next to the game under their own basename, which is what the
# games' ../<repo> paths expect. --full resends everything.
set -e -o pipefail
set -f   # the exclude patterns below must reach tar unexpanded
NETLAB=$(cd "$(dirname "$0")/.." && pwd)

FULL=
[ "$1" = --full ] && { FULL=1; shift; }
TOOLSET=$1 GAME=$2
[ -n "$GAME" ] && [ -f "$NETLAB/toolsets/$TOOLSET/build.sh" ] ||
  { echo "usage: $0 [--full] <toolset> <game-dir> [dep-dir...] [-- cmake-args...]" >&2; exit 2; }
shift 2
DEPS=()
while [ $# -gt 0 ] && [ "$1" != -- ]; do DEPS+=("$1"); shift; done
[ "$1" = -- ] && shift

# Least loaded: 1-minute load over cores.
BUILDER=$(grep -v '^#' "$NETLAB/farm/builders" | while read -r b _; do
  [ -n "$b" ] || continue
  l=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$b" 'echo $(cut -d" " -f1 /proc/loadavg) $(nproc)' 2>/dev/null) &&
    echo "$l $b"
done | awk '{ print $1 / $2, $3 }' | sort -n | head -1 | cut -d' ' -f2)
[ -n "$BUILDER" ] || { echo "no builder reachable (farm/builders)" >&2; exit 1; }
echo "builder: $BUILDER"

# Retail data, build output and analysis dumps never go over; they're the bulk
# of a game dir and no build reads them. Dir names are anchored to the top of
# each repo (burnout3/src/game is source, forcecommander/game is data).
TOP_EXCLUDES="build build-* bin _work _harness _drill original game disc extracted vfs pkg gamedata spu_dump runs saves scratch _local"
ANY_EXCLUDES=".git __pycache__ *.iso *.ISO *.zip *.rar *.7z *.exe *.EXE *.dll *.DLL *.obj *.pdb *.ilk *.log"

STATE="$NETLAB/farm/.state"; mkdir -p "$STATE"
sync_dir() {
  local d=${1%/} n since now tmp st
  n=$(basename "$d")
  st="$STATE/$BUILDER-$n"
  since=
  # ponytail: mtime-based; deletions and files copied in with old mtimes are missed, --full catches them
  [ -z "$FULL" ] && [ -f "$st" ] && since="--newer-mtime=@$(cat "$st")"
  now=$(date +%s)
  local ex=()
  for p in $TOP_EXCLUDES; do ex+=("--exclude=$n/$p"); done
  for p in $ANY_EXCLUDES; do ex+=("--exclude=$p"); done
  tmp=$(mktemp)
  (cd "$(dirname "$d")" && tar -cf "$tmp" $since "${ex[@]}" "$n")
  echo "sync $n: $(du -h "$tmp" | cut -f1)"
  # A file, not a pipe: a long tar|ssh pipe from Windows has dropped mid-stream.
  scp -q "$tmp" "$BUILDER:/tmp/farm-$n.tar"
  rm -f "$tmp"
  ssh "$BUILDER" "mkdir -p /work && tar --no-same-owner -xf /tmp/farm-$n.tar -C /work && rm /tmp/farm-$n.tar"
  echo "$now" > "$st"
}
sync_dir "$GAME"
for d in "${DEPS[@]}"; do sync_dir "$d"; done

NAME=$(basename "${GAME%/}")
JOB=$(date +%Y%m%d-%H%M%S)-$NAME
DEPNAMES=$(for d in "${DEPS[@]}"; do basename "${d%/}"; done | tr '\n' ' ')
mkdir -p "$NETLAB/farm/logs"
LOG="$NETLAB/farm/logs/$JOB.log"
echo "job $JOB, log $LOG"

# The toolset leaves the paths it built (relative to /work) in /work/.artifacts-$JOB.
{
  echo "GAME='$NAME' DEPS='$DEPNAMES' JOB='$JOB' CMAKE_ARGS='$*'"
  cat "$NETLAB/toolsets/$TOOLSET/build.sh"
  cat <<'EOF'
cd /work
if [ -d /share ]; then
  mkdir -p "/share/drops/$GAME/$JOB"
  xargs -r -a ".artifacts-$JOB" cp -t "/share/drops/$GAME/$JOB/"
  echo "drop: tank/scratch/work/drops/$GAME/$JOB"
fi
EOF
} | ssh "$BUILDER" 'cd /work && LC_ALL=C bash -s' 2>&1 | tee "$LOG"

mkdir -p "$GAME/build-farm"
for f in $(ssh "$BUILDER" "cat /work/.artifacts-$JOB && rm /work/.artifacts-$JOB"); do
  scp -q "$BUILDER:/work/$f" "$GAME/build-farm/"
  echo "-> $GAME/build-farm/$(basename "$f")"
done
