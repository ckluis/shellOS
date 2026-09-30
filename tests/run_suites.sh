#!/bin/bash
# Pure interpreter suites. Each test_*.bend is appended to the app bundle
# (app main renamed so the suite's main runs); test_wave2_gmail_page takes
# only sock+gmail, per its header. Pass = bend rc 0 and no FAIL lines.
# The original per-suite runners (build/wave*_test_run.sh) did not ship.
#
# Usage: tests/run_suites.sh [test_x.bend ...]   (default: all)
set -u
cd "$(dirname "$0")/.."
export BEND_NO_TELEMETRY=1
BEND="$HOME/.bend/bin/bend"
mkdir -p build/effs && cp -f effs/*.c effs/*.js build/effs/
APP="font.bend img.bend ui.bend reader.bend term.bend shell.bend pty.bend sock.bend search.bend gmail.bend ai.bend app.bend"
[ $# -gt 0 ] && SUITES="$*" || SUITES=$(ls test_*.bend)
bad=0
for t in $SUITES; do
  name=${t%.bend}
  case $t in
    test_wave2_gmail_page.bend) cat sock.bend gmail.bend "$t" > "build/${name}_all.bend" ;;
    *) { cat $APP | sed 's/^def main(/def app_main(/'; cat "$t"; } > "build/${name}_all.bend" ;;
  esac
  # Some suites define only <x>_main() -> String; their runner added main.
  if ! grep -q '^def main(' "$t"; then
    m=$(grep -oE '^def [a-z0-9_]+_main\(\) -> String' "$t" | head -1 | sed -E 's/^def ([a-z0-9_]+)\(.*/\1/')
    [ -n "$m" ] && printf '\ndef main() -> IO(Unit):\n  do IO<Unit>:\n    IO.print(%s())\n' "$m" >> "build/${name}_all.bend"
  fi
  "$BEND" "build/${name}_all.bend" > "build/${name}.log" 2>&1
  rc=$?
  p=$(grep -cE '^(PASS|ok)\b' "build/${name}.log"); f=$(grep -cE '^FAIL' "build/${name}.log")
  [ "$rc" = 0 ] && [ "$f" = 0 ] && v=PASS || { v=FAIL; bad=1; }
  printf '%-28s %s  pass=%s fail=%s rc=%s\n' "$name" "$v" "$p" "$f" "$rc"
done
exit $bad
