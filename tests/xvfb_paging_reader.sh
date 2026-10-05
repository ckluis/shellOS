#!/bin/bash
# Xvfb regression: paging, reader nav/scroll, atomic write-back, restart reload,
# PTY child cleanup. Exact-PID lifecycle, isolated X server + working dir.
set -u
P=~/workspace/apps/shell-os/pure
APP=$P/build/shell_pty
XCLICK=$P/tools/xclick
XSHOT=$P/tools/xshot
WNAME="Shell-OS"
TMPD=$(mktemp -d /tmp/shellos_reg_XXXXXX)
XVFB_PID=""; APP_PID=""
FAIL=0
fail() { echo "FAIL: $1"; FAIL=1; }
ok()   { echo "ok: $1"; }
cleanup() {
  [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null
  [ -n "$XVFB_PID" ] && kill "$XVFB_PID" 2>/dev/null
  rm -rf "$TMPD"
}
trap cleanup EXIT
shot() { "$XSHOT" :99 "$TMPD/$1.ppm"; }
# cmp_ne f1 f2 msg / cmp_eq f1 f2 msg
cmp_ne() { cmp -s "$TMPD/$1.ppm" "$TMPD/$2.ppm" && fail "$3 (frames equal)" || ok "$3"; }
cmp_eq() { cmp -s "$TMPD/$1.ppm" "$TMPD/$2.ppm" && ok "$3" || fail "$3 (frames differ)"; }
# crop top 512 rows (sidebar+grid, excludes reader/terminal tiles) for stable compare
crop() { python3 - "$TMPD/$1.ppm" "$TMPD/$1.crop" <<'EOF'
import sys
raw = open(sys.argv[1],'rb').read()
# P6 header: P6\nW H\n255\n
h_end = raw.index(b'255\n') + 4
w = 1100
head, px = raw[:h_end], raw[h_end:]
rows = 512
open(sys.argv[2],'wb').write(head + px[:rows*w*3])
EOF
}
crop_eq() { crop "$1"; crop "$2"; cmp -s "$TMPD/$1.crop" "$TMPD/$2.crop" && ok "$3" || fail "$3 (cropped frames differ)"; }

# 8 items, theme 0 -> 2 pages (6 per page)
printf '0|alpha\n0|beta\n0|gamma\n0|delta\n0|epsilon\n0|zeta\n0|eta\n0|theta\n' > "$TMPD/items.txt"

Xvfb :99 -screen 0 1100x1100x24 > "$TMPD/xvfb.log" 2>&1 &
XVFB_PID=$!
sleep 2
(cd "$TMPD" && DISPLAY=:99 "$APP" > "$TMPD/app1.log" 2>&1 & echo $! > "$TMPD/app1.pid")
APP_PID=$(cat "$TMPD/app1.pid")
sleep 4
PTY_CHILD=$(ps --ppid "$APP_PID" -o pid= 2>/dev/null | tr -d ' \n')
echo "app=$APP_PID pty_child=$PTY_CHILD"

shot A; "$XCLICK" :99 "$WNAME" key period; sleep 1; shot B
cmp_ne B A "page 2 differs from page 1"
"$XCLICK" :99 "$WNAME" key comma; sleep 1; shot C
cmp_eq C A "paging back is deterministic"

# reader on article 1, then article 2 (short: 6 lines, no scroll expected), scroll it
"$XCLICK" :99 "$WNAME" key r; sleep 1; shot D
cmp_ne D A "reader focus changes title"
"$XCLICK" :99 "$WNAME" key n; sleep 1; shot E
cmp_ne E D "article 2 differs"
for _ in 1 2 3; do "$XCLICK" :99 "$WNAME" key Down; sleep 0.5; done; shot G
cmp_eq G E "scroll down on short article is no-op (article 2, 6 lines)"
for _ in 1 2 3; do "$XCLICK" :99 "$WNAME" key Up; sleep 0.5; done; shot H
cmp_eq H E "scroll up on short article is no-op"
"$XCLICK" :99 "$WNAME" key p; sleep 1; shot F
cmp_eq F D "article switch back deterministic"
"$XCLICK" :99 "$WNAME" key Escape; sleep 1; shot I
cmp_eq I A "esc unfocuses reader, back to initial view"

# add item -> 9 items; page 2 now shows 3 tiles (was 2)
"$XCLICK" :99 "$WNAME" key a; sleep 2
[ -f "$TMPD/items.txt.tmp" ] && fail "tmp file left behind" || ok "no tmp file left (atomic rename done)"
[ "$(wc -l < "$TMPD/items.txt")" = "9" ] && ok "items.txt has 9 lines" || fail "items.txt line count"
"$XCLICK" :99 "$WNAME" key period; sleep 1; shot J2
cmp_ne J2 B "page 2 shows new 9th item"

# quit run 1, verify exact PIDs die (app + its PTY child)
"$XCLICK" :99 "$WNAME" key q; sleep 3
kill -0 "$APP_PID" 2>/dev/null && fail "app $APP_PID survived q" || ok "app exited on q"
[ -n "$PTY_CHILD" ] && { kill -0 "$PTY_CHILD" 2>/dev/null && fail "pty child $PTY_CHILD leaked" || ok "pty child reaped"; }
APP_PID=""

# run 2: reload 9 items from disk, page 2 must match run 1's page 2 (grid region)
(cd "$TMPD" && DISPLAY=:99 "$APP" > "$TMPD/app2.log" 2>&1 & echo $! > "$TMPD/app2.pid")
APP_PID=$(cat "$TMPD/app2.pid")
sleep 4
PTY_CHILD2=$(ps --ppid "$APP_PID" -o pid= 2>/dev/null | tr -d ' \n')
"$XCLICK" :99 "$WNAME" key period; sleep 1; shot K
crop_eq K J2 "restart reload: page 2 grid identical"
"$XCLICK" :99 "$WNAME" key q; sleep 3
kill -0 "$APP_PID" 2>/dev/null && fail "run-2 app survived q" || ok "2nd run exited on q"
[ -n "$PTY_CHILD2" ] && { kill -0 "$PTY_CHILD2" 2>/dev/null && fail "run-2 pty child $PTY_CHILD2 leaked" || ok "run-2 pty child reaped"; }
APP_PID=""
[ "$FAIL" = "0" ] && echo "REGRESSION PASS" || echo "REGRESSION FAILED"
exit "$FAIL"
