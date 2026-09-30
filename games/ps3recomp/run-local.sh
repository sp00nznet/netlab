#!/bin/sh
# Launch a ps3recomp title on this machine, set up to be driven: buttons from
# $PAD, log to $LOG, a frame to $FRAMES every 60 flips. drive/lib.sh's
# start runs it with the instance's settings in the environment:
#   GAME_DIR EXE ELF   where the build and its ELF are
#   PSNR PLAYER        psnr server and player name (empty PSNR = offline)
#   P2P_PORT           this instance's P2P port (default 3658)
#   NET_TRACE          1 = log every packet
set -e
: "${DIR:?}" "${PAD:?}" "${LOG:?}" "${FRAMES:?}" "${GAME_DIR:?}" "${EXE:?}" "${ELF:?}"

mkdir -p "$FRAMES"
find "$FRAMES" -maxdepth 1 -name '*.ppm' -delete
: > "$PAD"

# The runtime wants native paths on Windows.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }

cd "$GAME_DIR"
export PS3_VERBOSE=0              # per-wait logging otherwise slows the game to a crawl
export RSX_LIVE_DRAW=1
export PAD_FILE="$(native "$PAD")"
export LD_FRAME_DUMP="$(native "$FRAMES")"
export LD_FRAME_DUMP_EVERY=60
export PS3_NET_P2P_PORT=${P2P_PORT:-3658}
[ -n "$NET_TRACE" ] && export PS3_NET_TRACE=1
exec "./$EXE" "$ELF" ${PSNR:+--psnr "$PSNR"} ${PLAYER:+--username "$PLAYER"} > "$LOG" 2>&1
