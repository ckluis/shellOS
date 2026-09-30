#!/bin/bash
# tests/pty_probe.sh — build and run the standalone PTY regression natively,
# then verify no zombie children were left behind.
# Exit 0 on PASS with no zombies; nonzero otherwise.
set -u
export BEND_NO_TELEMETRY=1
BEND="$HOME/.bend/bin/bend"
cd "$(dirname "$0")/.."

cat font.bend pty.bend tests/pty_probe.bend > build/pty_probe_all.bend
mkdir -p build/effs && cp -f effs/*.c effs/*.js build/effs/
"$BEND" build/pty_probe_all.bend --check-only > build/pty_probe_check.log 2>&1 || {
  echo "CHECK FAILED"; cat build/pty_probe_check.log; exit 1; }
exec 9>build/.native.lock; flock 9
"$BEND" build/pty_probe_all.bend -o build/pty_probe > build/pty_probe_build.log 2>&1 || {
  echo "BUILD FAILED"; cat build/pty_probe_build.log; exit 1; }

sh_before=$(pgrep -x sh || true)
out=$(./build/pty_probe 2>&1)
sh_after=$(pgrep -x sh || true)
echo "$out"
case "$out" in
  PASS*) ;;
  *) echo "PROBE FAILED"; exit 1 ;;
esac
# Child-leak check: the probe's /bin/sh stays alive after `echo`, so close
# must have delivered SIGHUP to its process group. Diff sh pids around the run.
sleep 1
leaked=0
for pid in $sh_after; do
  case " $sh_before " in
    *" $pid "*) ;;
    *) if kill -0 "$pid" 2>/dev/null; then echo "LEAKED sh pid: $pid"; leaked=1; fi ;;
  esac
done
if [ "$leaked" != "0" ]; then echo "CHILD LEAK"; exit 1; fi
# Zombie check: any defunct child of a pty_probe run still around?
zombies=$(ps -eo stat,comm | grep -c "^Z.*pty_probe" || true)
if [ "$zombies" != "0" ]; then
  echo "ZOMBIES LEFT: $zombies"; exit 1
fi
echo "no zombies, no leaked children"
