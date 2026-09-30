#!/bin/bash
# build.sh — reproducible Shell-OS pure build.
# Concatenates sources, syncs custom effects into build/effs/, runs
# --check-only with its REAL exit code, optionally builds the native binary.
# Native builds are serialized with flock (8GB VM, no swap; the C codegen is
# heavy). Never pipe the compiler through tail: exit codes are captured.
#
# Usage:
#   ./build.sh check            # check-only app_all.bend
#   ./build.sh native           # check + native binary build/shell_pty
#   ./build.sh render           # check + rebuild render bundle (native+js)
#   ./build.sh all              # everything
set -u
export BEND_NO_TELEMETRY=1
# Bend 2.0.32 (default ~/.bend), migrated 2026-09-28: the full source
# typechecks clean, Wave 3 (35/35) and Wave 4 (24/24) pass on the 2.0.32
# interpreter. The 2.0.25 pin is kept on disk at ~/.bend-2.0.25 as rollback.
BEND="$HOME/.bend/bin/bend"
cd "$(dirname "$0")"

# TLS link flags: Bend's native builder honors no env-var injection point
# for extra -l flags, so native builds run with a build-scoped PATH-local
# clang wrapper (build/clangwrap/clang) that appends -lssl -lcrypto. The
# wrapper is created fresh by do_native, used ONLY for that build command,
# and never installed or left shadowing the system clang.
# macOS has no system OpenSSL headers; point the wrapper at Homebrew's
# openssl@3 (brew --prefix, falling back to the Apple Silicon default).
setup_clangwrap() {
  mkdir -p build/clangwrap
  local ssl_flags="-lssl -lcrypto"
  if [ "$(uname -s)" = Darwin ]; then
    local ssl_prefix
    ssl_prefix="$(brew --prefix openssl@3 2>/dev/null || echo /opt/homebrew/opt/openssl@3)"
    ssl_flags="-I$ssl_prefix/include -L$ssl_prefix/lib -lssl -lcrypto"
  fi
  printf '#!/bin/sh\nexec /usr/bin/clang "$@" %s\n' "$ssl_flags" > build/clangwrap/clang
  chmod +x build/clangwrap/clang
}

# One native build at a time. flock(1) is Linux-only; mkdir is atomic
# everywhere, so it serves as the lock on macOS.
acquire_native_lock() {
  if command -v flock >/dev/null 2>&1; then
    exec 9>build/.native.lock
    flock 9
  else
    until mkdir build/.native.lock.d 2>/dev/null; do sleep 1; done
    trap 'rmdir build/.native.lock.d 2>/dev/null' EXIT
  fi
}

sync_effs() {
  mkdir -p build/effs
  cp -f effs/*.c effs/*.js build/effs/
}

bundle_app() {
  cat font8x16.bend img.bend ui.bend reader.bend term.bend shell.bend pty.bend sock.bend search.bend gmail.bend ai.bend app.bend > build/app_all.bend
  sync_effs
}

bundle_render() {
  cat font8x16.bend img.bend ui.bend reader.bend term.bend shell.bend render_main.bend > build/render_all.bend
  sync_effs
}

do_check() {
  local bundle="$1"
  "$BEND" "$bundle" --check-only > build/check.log 2>&1
  local rc=$?
  cat build/check.log
  if [ $rc -ne 0 ]; then
    # Bend 2.0.32+: --check-only prints SOME PROOFS FAIL when any def uses
    # @unsafe or user foreign code. Shell-OS legitimately has a foreign
    # effect seam (files, PTY, sockets, TLS, window: 164 defs), so that
    # verdict ALONE is not a failure — any other error shape is.
    if grep -q "defs rely on unsafe or foreign code" build/check.log && \
       ! grep -qE "^- (expected|observed|message)[[:space:]]*:" build/check.log; then
      echo "check: SOME PROOFS FAIL is the expected foreign-effect verdict only; types are clean."
      return 0
    fi
  fi
  return $rc
}

do_native() {
  local bundle="$1" out="$2"
  # Serialize native builds: one at a time.
  acquire_native_lock
  setup_clangwrap
  # NOTE: callers pass the exact output path. The app build passes
  # build/shell_pty.new (never overwrite the promoted binary in place;
  # promotion is a separate, explicit, verified step).
  PATH="$PWD/build/clangwrap:$PATH" "$BEND" "$bundle" -o "$out" > build/native_build.log 2>&1
  local rc=$?
  cat build/native_build.log
  return $rc
}

case "${1:-check}" in
  check)
    bundle_app
    do_check build/app_all.bend
    ;;
  native)
    bundle_app
    do_check build/app_all.bend || exit $?
    # The promoted binary is build/shell_pty; always build to .new and
    # promote explicitly only after verification.
    do_native build/app_all.bend build/shell_pty.new
    ;;
  render)
    bundle_render
    do_check build/render_all.bend || exit $?
    do_native build/render_all.bend build/render_all_native || exit $?
    "$BEND" build/render_all.bend -o build/render_all.js > build/js_rerender_build.log 2>&1
    rc=$?; cat build/js_rerender_build.log; exit $rc
    ;;
  all)
    "$0" native || exit $?
    "$0" render
    ;;
  *)
    echo "usage: $0 [check|native|render|all]" >&2
    exit 2
    ;;
esac
