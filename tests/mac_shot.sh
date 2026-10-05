#!/bin/bash
# Visual review shots: boot the app on demo data and capture named states.
# Not a gate (tests/mac_proof.sh is); this is for looking at the design.
#
# Usage: tests/mac_shot.sh [binary] [outdir] [name=keys ...]
#   keys use macwin escapes (\e Esc, \r Return, \U \D arrows). Each step
#   runs from the state the previous one left. Default steps cover the main
#   screens: boot, palette, search, help, entry, reader, terminal.
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
APP=$ROOT/${1:-build/shell_pty.new}
OUT=${2:-$ROOT/proofs/shots_$(date +%Y%m%d_%H%M%S)}
shift 2 2>/dev/null
MACWIN=$ROOT/build/macwin
if [ ! -x "$MACWIN" ] || [ tools/macwin.m -nt "$MACWIN" ]; then
  clang -fobjc-arc -framework AppKit -framework ApplicationServices tools/macwin.m -o "$MACWIN" || exit 2
fi
mkdir -p "$OUT/wd"
cat > "$OUT/wd/items.txt" <<'EOF'
1|Walnut floating shelves
1|Kitchen lighting refresh
2|Elden Ring: bleed build
2|Balatro seed notes
3|Lisbon flights Nov 14
v2|4|Pure Bend|compare the native and Bun numbers|1759240000000|shell-os://articles/pure-bend
EOF
# Esc in NORMAL mode quits, so every Esc below closes something.
if [ $# -eq 0 ]; then
  set -- "01_boot=" "02_palette=;tab" "03_palette_down=\\D" "04_search=\\e/sh" "05_help=\\e?" \
    "06_entry=\\eanew shelf brackets" "07_reader=\\er" "08_reader_next=n" "09_note=s" \
    "10_note_typed=check the numbers" "11_terminal=\\e\\et" "12_terminal_ls=ls -la\\r"
fi
(cd "$OUT/wd" && exec "$APP" > "$OUT/app.log" 2>&1) &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT
for _ in $(seq 1 40); do WID=$("$MACWIN" wid $PID 2>/dev/null); [ "${WID:-0}" != 0 ] && break; sleep 0.25; done
sleep 1.5
for step in "$@"; do
  name=${step%%=*}; keys=${step#*=}
  [ -n "$keys" ] && "$MACWIN" keys $PID "$keys"
  sleep 0.9
  screencapture -x -o -l "$("$MACWIN" wid $PID)" "$OUT/$name.png"
  echo "$OUT/$name.png"
done
"$MACWIN" keys $PID "\\e\\e\\eq" >/dev/null 2>&1; sleep 1
