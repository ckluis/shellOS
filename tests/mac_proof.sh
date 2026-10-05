#!/bin/bash
# macOS proof run — the stand-in for the Xvfb gate on Linux.
# Boots the binary N times (default 2) in isolated working dirs, drives the
# real window with tools/macwin (keys to this pid only) and screenshots it
# with screencapture -l (this window only). Covers README step 5:
#   ;  palette opens, filters, moves selection, closes (stays responsive)
#   /  search opens, takes a query, closes
#   a  entry-bar add commits and persists to items.txt (atomic: no .tmp)
#   q  clean exit (rc 0), PTY children gone, session.txt written
#   relaunch in the same dir reloads the added item
# Exact-pid lifecycle: nothing is killed by name.
#
# Usage: tests/mac_proof.sh [binary] [boots]
#   binary defaults to build/shell_pty.new; screenshots land in proofs/mac_<stamp>/
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
APP=$ROOT/${1:-build/shell_pty.new}
BOOTS=${2:-2}
MACWIN=$ROOT/build/macwin
STAMP=$(date +%Y%m%d_%H%M%S)
OUT=$ROOT/proofs/mac_$STAMP
mkdir -p "$OUT"
LOG=$OUT/proof.log
FAIL=0
APP_PID=""

say()  { echo "$*" | tee -a "$LOG"; }
ok()   { say "ok: $1"; }
fail() { say "FAIL: $1"; FAIL=1; }
cleanup() { [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null; }
trap cleanup EXIT

[ -x "$APP" ] || { echo "no binary at $APP" >&2; exit 2; }
if [ ! -x "$MACWIN" ] || [ tools/macwin.m -nt "$MACWIN" ]; then
  clang -fobjc-arc -framework AppKit -framework ApplicationServices \
    tools/macwin.m -o "$MACWIN" || exit 2
fi

say "binary: $APP"
say "sha256: $(shasum -a 256 "$APP" | cut -d' ' -f1)"
say "boots:  $BOOTS   out: $OUT"

# shot NAME — capture only this app's window (no shadow), BMP so cmp is exact.
shot() {
  local wid; wid=$("$MACWIN" wid "$APP_PID")
  screencapture -x -o -t bmp -l "$wid" "$DIR/$1.bmp" 2>>"$LOG"
  sips -s format png "$DIR/$1.bmp" --out "$DIR/$1.png" >/dev/null 2>&1
}
differs() { cmp -s "$DIR/$1.bmp" "$DIR/$2.bmp" && fail "$3 (frames equal)" || ok "$3"; }
keys()    { "$MACWIN" keys "$APP_PID" "$1" || { fail "macwin keys '$1' rc=$?"; return 1; }; sleep "${2:-0.6}"; }

for n in $(seq 1 "$BOOTS"); do
  DIR=$OUT/boot$n
  mkdir -p "$DIR/wd"
  printf '0|alpha\n1|beta\n2|gamma\n3|delta\n' > "$DIR/wd/items.txt"
  say "--- boot $n"
  (cd "$DIR/wd" && exec "$APP" > "$DIR/app.log" 2>&1) &
  APP_PID=$!
  wid=0
  for _ in $(seq 1 40); do
    wid=$("$MACWIN" wid "$APP_PID" 2>/dev/null); [ "${wid:-0}" != 0 ] && break; sleep 0.25
  done
  [ "${wid:-0}" != 0 ] && ok "window up (pid $APP_PID, wid $wid)" || { fail "no window"; continue; }
  sleep 1.5
  KIDS=$(pgrep -P "$APP_PID" | tr '\n' ' ')
  [ -n "$KIDS" ] && ok "PTY child(ren): $KIDS" || fail "no PTY child"
  shot 00_boot

  # ; palette: open, filter, move, close
  keys ";";          shot 01_palette_open;  differs 01_palette_open 00_boot "palette opens"
  keys "tab";        shot 02_palette_filter; differs 02_palette_filter 01_palette_open "palette filters (responsive)"
  keys "\\D";        shot 03_palette_down;  differs 03_palette_down 02_palette_filter "palette selection moves (responsive)"
  keys "\\e";        shot 04_palette_closed; differs 04_palette_closed 03_palette_down "palette closes"

  # / search: open, query, close
  keys "/";          shot 05_search_open;   differs 05_search_open 04_palette_closed "search opens"
  keys "gam";        shot 06_search_query;  differs 06_search_query 05_search_open "search takes a query"
  keys "\\e";        shot 07_search_closed; differs 07_search_closed 06_search_query "search closes"

  # a entry bar: add, type, commit, persist
  # Letters only: in add mode 0-3 pick the theme, so a digit never lands in the title.
  title="proof boot $(echo "$n" | tr 0-9 a-j)"
  keys "a";          shot 08_entry_open;    differs 08_entry_open 07_search_closed "entry bar opens"
  keys "$title";     shot 09_entry_typed;   differs 09_entry_typed 08_entry_open "entry bar takes text"
  keys "\\r" 1.0;    shot 10_entry_commit;  differs 10_entry_commit 09_entry_typed "entry commits"
  grep -q "|$title\$" "$DIR/wd/items.txt" && ok "items.txt has '$title'" || fail "items.txt missing '$title'"
  [ ! -e "$DIR/wd/items.txt.tmp" ] && ok "no items.txt.tmp left" || fail "items.txt.tmp left behind"

  # q clean exit, children reaped
  keys "q" 0.2
  rc=124
  for _ in $(seq 1 40); do kill -0 "$APP_PID" 2>/dev/null || break; sleep 0.25; done
  if kill -0 "$APP_PID" 2>/dev/null; then fail "still running 10s after q"; else wait "$APP_PID"; rc=$?; fi
  APP_PID=""
  [ "$rc" = 0 ] && ok "q exits rc=0" || fail "q exit rc=$rc"
  sleep 0.5
  alive=""; for k in $KIDS; do kill -0 "$k" 2>/dev/null && alive="$alive $k"; done
  [ -z "$alive" ] && ok "PTY children gone" || fail "PTY children still alive:$alive"
  [ -s "$DIR/wd/session.txt" ] && ok "session.txt written on quit" || fail "no session.txt after quit"

  # relaunch in the same dir: the added item must reload from disk
  (cd "$DIR/wd" && exec "$APP" > "$DIR/app_relaunch.log" 2>&1) &
  APP_PID=$!
  wid=0
  for _ in $(seq 1 40); do
    wid=$("$MACWIN" wid "$APP_PID" 2>/dev/null); [ "${wid:-0}" != 0 ] && break; sleep 0.25
  done
  [ "${wid:-0}" != 0 ] && ok "relaunch window up" || fail "relaunch: no window"
  sleep 1.5
  shot 11_relaunch
  differs 11_relaunch 00_boot "relaunch shows the persisted item (frame differs from first boot)"
  keys "q" 0.2
  for _ in $(seq 1 40); do kill -0 "$APP_PID" 2>/dev/null || break; sleep 0.25; done
  if kill -0 "$APP_PID" 2>/dev/null; then fail "relaunch still running after q"; else wait "$APP_PID"; rc=$?; [ "$rc" = 0 ] && ok "relaunch q exits rc=0" || fail "relaunch q rc=$rc"; fi
  APP_PID=""
  cp "$DIR/wd/items.txt" "$DIR/items_after.txt"
  rm -f "$DIR"/*.bmp
done

if [ $FAIL = 0 ]; then say "RESULT: PASS ($BOOTS boots)"; else say "RESULT: FAIL"; fi
exit $FAIL
