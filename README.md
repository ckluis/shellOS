# Shell-OS Maximal-Pure — Project Package

Packaged 2026-09-30. Read this whole file, then execute the plan in
"What we need to do" in order.

## What the project is

Shell-OS maximal-pure is a **single-app meta-OS shell** (Omarchy style)
written in **maximal-pure Bend**: all rendering, layout, UI state,
filtering, and text rasterization live in pure Bend. Effects sit behind a
**minimal named foreign-effect seam** — `effs/` (one `.c` + `.js` file per
effect: files, PTY spawn/read/write/close, sockets, TLS). Only the seam
is foreign code; everything else is pure.

- **Language:** Bend. Default toolchain `~/.bend/bin/bend`, version **2.0.34**
  (user-ordered upgrade 2026-09-29, sha256-verified). Sources were migrated
  for 2.0.32's new `Event` arms (`Look{dx,dy}`, `Scroll{x,y,dx,dy}`).
- **Native builds:** clang 18.1.3 (C codegen via Bend). Interpreter/JS
  target (Bun) used for fast iteration.
- **Build entry point:** `./build.sh` — `check | native | render | all`.
  `./build.sh check` bundles sources into `build/app_all.bend` and runs
  `--check-only`; native builds serialize via flock and **always build to
  `build/shell_pty.new`, never overwrite the working binary in place**.
- **Deep history:** `REPORT.md` in this package (315KB, full wave log).
- **Hard boundary:** never modify `~/workspace/apps/shell-os/core/`
  (the P0 backend — done, untouched).

## Where we are (verified 2026-09-30 10:04 EDT)

**Complete (all verified):**
- The 7 user-ordered accretive items: socket/TLS effect bridge, write-back
  fsync durability, real profiles (default/work/personal, isolated),
  escaped newlines in titles, terminal tabs, mouse hover states, reader
  live content.
- Entry-bar add/edit UX (Xvfb 14/14 PASS), item write-back verification
  (14/14 PASS), CRUD suite (23/23 PASS).
- `./build.sh check` rc=0 (types clean; `SOME PROOFS FAIL` is the expected
  foreign-effect-seam verdict only — never a failure by itself).
- Native render + Bun produce byte-identical PPM
  (md5 `9b78a34aeaf6d83db68a3d24636ad0ae`).
- Secrets audit clean; toolchain intact after cell roll-41
  (Bend 2.0.34 survived; clang 18.1.3 restored from the apt cache).

**The one open blocker — native rebuild:**
- The working binary `build/shell_pty` (sha256 `97ad6ad92cafcbf2…`,
  2026-09-25, included in this package) **predates** the 2026-09-25
  palette touched-flag fix and the 2026-09-28 Bend 2.0.32 migration.
  No behavior claims against current sources until a fresh binary is
  built and proven under Xvfb.
- Rebuild is **RAM-blocked**: it requires a quiet window with
  `MemAvailable ≥ 5G`. Last measured: ~1.9G. Do NOT attempt the build
  below that bar.

**Not included in this zip (to keep it lean):** `proofs/` — 74MB of
PNG/PPM Xvfb evidence on disk at `~/workspace/apps/shell-os/pure/proofs/`.
Build intermediates (`build/qtest_*`, `build/wedge_*`, PPMs) likewise
excluded; only `build/shell_pty`, `render.log`, `bun_run.log` ship.

## What we need to do (execute in order)

1. **Verify the environment.** `bend --version` → 2.0.34; `which clang` →
   18.1.3; Xvfb present; no duplicate native build in flight
   (no `build/.new` binary, no `bend`/`clang` build procs, flock free).
2. **Typecheck.** `./build.sh check` → expect rc=0. `SOME PROOFS FAIL`
   with only the "defs rely on unsafe or foreign code" line = pass.
   Any other error shape = stop and fix.
3. **Check the RAM gate.** `MemAvailable ≥ 5G` required. If below, STOP —
   do not build, report the reading, wait for a quiet window.
4. **Build the native binary.** `export TMPDIR=~/workspace/.bend-tmp`
   (the 512M /tmp tmpfs dies with ENOSPC mid-codegen),
   then `./build.sh native` → `build/shell_pty.new`, rc=0, full unpiped
   log preserved.
5. **Fresh Xvfb proofs** (at least 2 fresh boots): cover `;` (palette
   opens and stays responsive), `/` (search), `a` (entry-bar add),
   `q` (clean exit, PTY children reaped). Screenshot proofs into
   `proofs/`. Require visual proof the palette opens and remains
   responsive.
6. **Persistence + relaunch check.** Re-run the secrets audit.
   Produce a real `sha256sum -c` manifest. **Promote**
   `build/shell_pty.new` → `build/shell_pty` ONLY after all gates pass —
   never overwrite or remove the working binary first.
7. **Update `REPORT.md`** with the rebuild + proof results.
8. **Backlog (after promotion):** entry-bar UI polish, write-back
   verification under Xvfb, mouse under Xvfb, PTY-backed live terminal.
9. **Accretive proposals — DO NOT START without user approval:**
   benchmark manifest binding; reader fetch-cache durability through
   atomic writes; formal Xvfb hover suite as a regression gate.

Rules that always hold: never break a working binary before its
replacement verifies; one native build at a time; full unpiped logs and
real exit codes; never claim native-interactive without a fresh Xvfb
screenshot; never claim "fast" without measured numbers.
