#!/usr/bin/env bash
# Small helpers for driving the live Hyprland 0.57 desktop from an agent shell.
# Usage:
#   desk.sh window CLASS          -> "X,Y WxH" of the first client with that class
#   desk.sh to X Y                -> move the pointer to logical X,Y (halving loop)
#   desk.sh click                 -> left click at the pointer
#   desk.sh scroll N              -> wheel N notches (negative scrolls down); pointer must be over the target
#   desk.sh shot "X,Y WxH" FILE   -> screenshot a logical region at scale 1
set -euo pipefail
cmd=${1:?command}; shift
case $cmd in
  window)
    hyprctl -j clients | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if c["class"] == sys.argv[1] and c["mapped"]:
        (x, y), (w, h) = c["at"], c["size"]
        print(f"{x},{y} {w}x{h}"); break
else:
    sys.exit("no window with class " + sys.argv[1])' "$1" ;;
  to)
    tx=$1 ty=$2
    # hyprctl dispatch movecursor is a no-op with the Lua config; ydotool is relative
    # and accelerated, so close half the remaining distance until within 2 px.
    for _ in $(seq 12); do
      p=$(hyprctl cursorpos); x=${p%%,*}; y=${p##*, }
      dx=$((tx - x)); dy=$((ty - y))
      [ ${dx#-} -le 2 ] && [ ${dy#-} -le 2 ] && exit 0
      sx=$((dx / 2)); sy=$((dy / 2))
      [ $sx -eq 0 ] && sx=$dx; [ $sy -eq 0 ] && sy=$dy
      ydotool mousemove -x $sx -y $sy >/dev/null 2>&1
      sleep 0.15
    done
    echo "pointer stopped at $(hyprctl cursorpos), wanted $tx, $ty" >&2; exit 1 ;;
  click) ydotool click 0xC0 >/dev/null 2>&1 ;;
  scroll) ydotool mousemove --wheel -x 0 -y "$1" >/dev/null 2>&1 ;;
  shot) grim -g "$1" -s 1 "$2" ;;
  *) echo "unknown command $cmd" >&2; exit 2 ;;
esac
