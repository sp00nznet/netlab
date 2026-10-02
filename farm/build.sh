#!/bin/bash
# Build a game on the least-loaded farm builder (farm/builders), with its
# toolset (toolsets/<name>/build.sh). The game and the repos it builds against
# are synced to the builder's workspace; after the first sync only files
# changed since the last one go over, so the builder's ninja dir stays warm.
# The exes, pdbs and maps come back to <game-dir>/build-farm[-<slot>]/, and go
# to the share (/share/drops/<game>/<job>/) when the builder has the share.
#
# usage: farm/build.sh [--full] [--slot <name>] <toolset> <game> [dep...] [-- cmake-args...]
#   farm/build.sh cmake     ~/src/pc/forcecommander ~/src/pc/tools -- -DFOCOM_TRACE=ON
#   farm/build.sh cmake     ~/src/pc/rol ~/src/pc/pcrecomp-rol -- -DXWIN_ARCH=x86 -DGEN_OPT=/O1
#   farm/build.sh cmake     ~/src/xbox/burnout3 ~/src/xbox/xboxrecomp
#   farm/build.sh ps3recomp ~/src/ps3games/simpsons ~/src/ps3-simp
#
# Each game or dep is <dir>[@<ref>][=<name>]:
#   @<ref>   build that git ref: tracked files from the ref, untracked ones
#            (the lifted C) from the working tree as they are now
#   =<name>  land it as /work/<name> rather than under its own basename, so a
#            different checkout stands in where the game expects ../<name>
#            or, with a path (=<game>/<submodule>), in place of a submodule
# A/B: the same game against two checkouts, each in its own slot, so neither
# build dir is thrown away:
#   farm/build.sh --slot a cmake ~/src/xbox/burnout3 ~/src/xbox/xboxrecomp
#   farm/build.sh --slot b cmake ~/src/xbox/burnout3 ~/src/xbox/xr-pr=xboxrecomp
#   farm/build.sh --slot old cmake ~/src/pc/rol@v0.3 ~/src/pc/pcrecomp-rol -- ...
# A slot's first build is cold. --full resends everything.
# KEEP="<dir> ..." sends top-level dirs that are skipped by default (work, ...).
# TARGET=<target> builds that CMake target only.
set -e -o pipefail
set -f   # the exclude patterns below must reach tar unexpanded
NETLAB=$(cd "$(dirname "$0")/.." && pwd)

FULL= SLOT=
while :; do
  case $1 in
    --full) FULL=1; shift ;;
    --slot) SLOT=$2; shift 2 ;;
    *) break ;;
  esac
done
TOOLSET=$1 GAME=$2
[ -n "$GAME" ] && [ -f "$NETLAB/toolsets/$TOOLSET/build.sh" ] ||
  { echo "usage: $0 [--full] [--slot <name>] <toolset> <game> [dep...] [-- cmake-args...]" >&2; exit 2; }
shift 2
DEPS=()
while [ $# -gt 0 ] && [ "$1" != -- ]; do DEPS+=("$1"); shift; done
[ "$1" = -- ] && shift
W=/work${SLOT:+/slots/$SLOT}

# Least loaded: 1-minute load over cores. BUILDER=<ssh target> picks one.
[ -n "$BUILDER" ] || BUILDER=$(grep -v '^#' "$NETLAB/farm/builders" | while read -r b _; do
  [ -n "$b" ] || continue
  l=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$b" 'echo $(cut -d" " -f1 /proc/loadavg) $(nproc)' 2>/dev/null) &&
    echo "$l $b"
done | awk '{ print $1 / $2, $3 }' | sort -n | head -1 | cut -d' ' -f2)
[ -n "$BUILDER" ] || { echo "no builder reachable (farm/builders)" >&2; exit 1; }
echo "builder: $BUILDER, workspace $W"

# Retail data, build output and analysis dumps never go over; they're the bulk
# of a game dir and no build reads them. Dir names are anchored to the top of
# each repo (burnout3/src/game is source, forcecommander/game is data).
TOP_EXCLUDES="build build-* bin work _work _harness _drill original game disc extracted vfs pkg gamedata spu_dump runs saves scratch _local"
# KEEP="work ..." sends those dirs after all (catz keeps its lifted C in work/).
for k in $KEEP; do TOP_EXCLUDES=" $TOP_EXCLUDES "; TOP_EXCLUDES=${TOP_EXCLUDES// $k / }; done
ANY_EXCLUDES=".git __pycache__ *.iso *.ISO *.zip *.rar *.7z *.exe *.EXE *.dll *.DLL *.obj *.pdb *.ilk *.log"

# <dir>[@<ref>][=<name>] -> SPEC_DIR SPEC_REF SPEC_NAME
parse() {
  local s=${1%/}
  SPEC_NAME= SPEC_REF=
  case $s in *=*) SPEC_NAME=${s##*=}; s=${s%=*} ;; esac
  case $s in *@*) SPEC_REF=${s##*@}; s=${s%@*} ;; esac
  SPEC_DIR=${s%/}
  [ -n "$SPEC_NAME" ] || SPEC_NAME=$(basename "$SPEC_DIR")
}

STATE="$NETLAB/farm/.state"; mkdir -p "$STATE"
sync_spec() {
  parse "$1"
  local d=$SPEC_DIR n=$SPEC_NAME ref=$SPEC_REF b st since now tmp k r
  b=$(basename "$d")
  k=${n//\//_}
  st="$STATE/$BUILDER-${SLOT:-main}-$k"
  r="/tmp/farm-$$-${SLOT:-main}-$k"
  local ex=()
  for p in $TOP_EXCLUDES; do ex+=("--exclude=$b/$p"); done
  for p in $ANY_EXCLUDES; do ex+=("--exclude=$p"); done
  tmp=$(mktemp)
  if [ -n "$ref" ]; then
    # A ref is sent whole: the working tree (for its untracked files), the
    # ref's tracked files over it, and the files the ref doesn't have removed.
    git -C "$d" rev-parse --verify -q "$ref^{commit}" >/dev/null || { echo "$d: no ref $ref" >&2; exit 1; }
    (cd "$(dirname "$d")" && tar -cf "$tmp" "${ex[@]}" --transform "s,^$b,$n," "$b")
    git -C "$d" archive --prefix="$n/" "$ref" > "$tmp.ref"
    comm -23 <(git -C "$d" ls-files | sort) <(git -C "$d" ls-tree -r --name-only "$ref" | sort) > "$tmp.gone"
    echo "sync $n @ $ref ($(git -C "$d" rev-parse --short "$ref")): $(du -h "$tmp" | cut -f1) + $(du -h "$tmp.ref" | cut -f1)"
    scp -q "$tmp" "$BUILDER:$r.tar"
    scp -q "$tmp.ref" "$BUILDER:$r.ref.tar"
    scp -q "$tmp.gone" "$BUILDER:$r.gone"
    ssh "$BUILDER" "set -e; mkdir -p $W && cd $W && rm -rf '$n' &&
      tar --no-same-owner -xf $r.tar && tar --no-same-owner -xf $r.ref.tar &&
      (cd '$n' && tr -d '\r' < $r.gone | xargs -r -d '\n' rm -f) &&
      rm $r.tar $r.ref.tar $r.gone"
    rm -f "$tmp" "$tmp.ref" "$tmp.gone" "$st"   # the next plain sync of this slot starts full
    return
  fi
  since=
  local clean=
  case $n in */*)
    # A path inside another repo (a submodule): replace that dir whole, and
    # resend the repo around it in full next time, so the stand-in can't linger.
    # ponytail: files only the stand-in has stay until --full of a fresh slot
    clean="rm -rf '$W/$n' &&"
    rm -f "$STATE/$BUILDER-${SLOT:-main}-${n%%/*}" "$st" ;;
  esac
  # ponytail: mtime-based; deletions and files copied in with old mtimes are missed, --full catches them
  [ -z "$FULL" ] && [ -f "$st" ] && since="--newer-mtime=@$(cat "$st")"
  now=$(date +%s)
  (cd "$(dirname "$d")" && tar -cf "$tmp" $since "${ex[@]}" --transform "s,^$b,$n," "$b")
  echo "sync $n$([ "$n" = "$b" ] || echo " ($d)"): $(du -h "$tmp" | cut -f1)"
  # A file, not a pipe: a long tar|ssh pipe from Windows has dropped mid-stream.
  scp -q "$tmp" "$BUILDER:$r.tar"
  rm -f "$tmp"
  ssh "$BUILDER" "mkdir -p $W && $clean tar --no-same-owner -xf $r.tar -C $W && rm $r.tar"
  [ -n "$clean" ] || echo "$now" > "$st"
}
sync_spec "$GAME"
DEPNAMES=
for d in "${DEPS[@]}"; do sync_spec "$d"; DEPNAMES="$DEPNAMES$SPEC_NAME "; done

parse "$GAME"
GAME_DIR=$SPEC_DIR NAME=$SPEC_NAME
JOB=$(date +%Y%m%d-%H%M%S)-$NAME${SLOT:+-$SLOT}
mkdir -p "$NETLAB/farm/logs"
LOG="$NETLAB/farm/logs/$JOB.log"
echo "job $JOB, log $LOG"

# The toolset builds in $W/$GAME and leaves the paths it built (relative to
# $W) in $W/.artifacts-$JOB.
{
  echo "W='$W' GAME='$NAME' DEPS='$DEPNAMES' JOB='$JOB' CMAKE_ARGS='$*' TARGET='$TARGET'"
  cat "$NETLAB/toolsets/$TOOLSET/build.sh"
  cat <<'EOF'
cd "$W"
if [ -d /share ]; then
  mkdir -p "/share/drops/$GAME/$JOB"
  xargs -r -a ".artifacts-$JOB" cp -t "/share/drops/$GAME/$JOB/"
  echo "drop: tank/scratch/work/drops/$GAME/$JOB"
fi
EOF
} | ssh "$BUILDER" "mkdir -p $W && cd $W && LC_ALL=C bash -s" 2>&1 | tee "$LOG"

OUT="$GAME_DIR/build-farm${SLOT:+-$SLOT}"
mkdir -p "$OUT"
for f in $(ssh "$BUILDER" "cat $W/.artifacts-$JOB && rm $W/.artifacts-$JOB"); do
  scp -q "$BUILDER:$W/$f" "$OUT/"
  echo "-> $OUT/$(basename "$f")"
done
