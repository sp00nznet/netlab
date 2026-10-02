#!/bin/bash
# Play a steps file against a running program on this Linux desktop (the
# Linux test box), with xdotool and ImageMagick. netlab play/qa copies it to
# the machine and runs it there:
#   play.sh <steps> <out-dir> <window-title or ""> <process> <run.log>
# Steps, one per line (# comments):
#   wait <s>                  key <combo>       type <text>
#   click <x> <y>             (inside the program's window)
#   pad <mask> [hold]         (a game's pad mailbox: $PAD)
#   expect-window <title> [s] expect-log <text> [s]   (a trailing number is the timeout)
#   snap <name.png>
# Exits 1 at the first expect that times out, after a snap of the moment.
set -u -f   # -f: a step like "type 5 * 3" must not glob
steps=$1 out=$2 title=$3 proc=$4 log=$5
export DISPLAY=${DISPLAY:-:0} XAUTHORITY=${XAUTHORITY:-$HOME/.Xauthority}
mkdir -p "$out"

win() {
  local w=
  [ -n "$title" ] && w=$(xdotool search --onlyvisible --name "$title" 2>/dev/null | tail -1)
  if [ -z "$w" ]; then
    for p in $(pgrep -f "$proc"); do
      w=$(xdotool search --onlyvisible --pid "$p" 2>/dev/null | tail -1)
      [ -n "$w" ] && break
    done
  fi
  echo "$w"
}
focus() { W=$(win); [ -n "$W" ] && xdotool windowactivate --sync "$W" 2>/dev/null; }
# xdotool's names for the keys the steps call by their everyday names.
keysym() {
  echo "$1" | sed -E 's/\benter\b/Return/g; s/\besc\b/Escape/g; s/\bdel\b/Delete/g;
    s/\bpgup\b/Prior/g; s/\bpgdn\b/Next/g; s/\bup\b/Up/g; s/\bdown\b/Down/g;
    s/\bleft\b/Left/g; s/\bright\b/Right/g; s/\btab\b/Tab/g; s/\bspace\b/space/g;
    s/\bbackspace\b/BackSpace/g; s/\bhome\b/Home/g; s/\bend\b/End/g; s/\bf([0-9]+)\b/F\1/g'
}
fail() { echo "FAIL line $n: $*"; snap "fail-$n.png" >/dev/null 2>&1; exit 1; }
snap() { W=$(win); [ -n "$W" ] || { echo "snap: no window"; return 1; }; import -window "$W" "$out/$1" && echo "snap $1"; }

n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  line=${line%$'\r'}; line=${line%%#*}; set -- $line
  [ $# -gt 0 ] || continue
  cmd=$1; shift
  case $cmd in
  wait) sleep "$1" ;;
  key) focus; xdotool key --clearmodifiers "$(keysym "$1")" ;;
  type) focus; xdotool type --delay 40 "$*" ;;
  click) focus; xdotool mousemove --window "$W" "$1" "$2" click 1 ;;
  pad)
    [ -n "${PAD:-}" ] || fail "pad: the machine has no PAD mailbox"
    printf '%s %s\n' "$1" "${2:-}" > "$PAD"
    for i in $(seq 100); do [ -s "$PAD" ] || break; sleep 0.1; done ;;
  expect-window|expect-log)
    # The text may have spaces; a trailing number is the timeout.
    a=("$@") t=30
    if [ ${#a[@]} -gt 1 ] && [[ ${a[-1]} =~ ^[0-9]+$ ]]; then t=${a[-1]}; unset 'a[-1]'; fi
    text="${a[*]}"
    if [ "$cmd" = expect-window ]; then has() { xdotool search --onlyvisible --name "$text" >/dev/null 2>&1; }
    else has() { grep -aqF -- "$text" "$log" 2>/dev/null; }; fi
    for i in $(seq "$t"); do has && break; sleep 1; done
    has || fail "${cmd#expect-} '$text' not there after ${t}s"
    echo "ok   ${cmd#expect-} '$text'" ;;
  snap) snap "$1" || fail "snap $1" ;;
  *) fail "unknown step '$cmd'" ;;
  esac
done < "$steps"
echo "PASS"
