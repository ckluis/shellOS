# pty_io_probe2.bend — io_work REPEATED-USE test (2026-09-25 17:03 EDT run).
# Hypothesis: the fresh-boot wedge is Pty.read's io_work completion hanging
# on the SECOND (or later) use. pty_io_probe proved spawn + ONE read return
# natively; the app's tick_pty_tail (app.bend:2092) calls Pty.read(pty, 4096)
# on EVERY frame of every YesPty tab. If io_work's completion spins in
# userspace on repeat use, the signature matches exactly: frame 1 renders,
# then hang before frame 2, no syscalls, wchan=0, input dead, q ignored.
# Markers isolate WHICH read hangs: READ1-done but no READ2-done => repeat-use
# hang confirmed.
# NOTE: the pty master fd is O_NONBLOCK (pty_spawn.c:79-80), so a synchronous
# read can never block — if repeat-use hangs, the app-side fix is to do the
# read inline (like window_frame_run) instead of via io_work.
# Placed in pure/ so "./effs/..." imports resolve.
# Build (needs clang + ~300MB): ~/.bend-2.0.25/bend/bin/bend
#   pty_io_probe2.bend -o build/pty_io_probe2.new
# Run: ./build/pty_io_probe2.new ; expect READ1/2/3-done + PROBE-DONE.

import Base

def pty_spawn_raw() -> IO(Result<&1,&1, U32 & String, U32>):
  import "./effs/pty_spawn.c"
  import "./effs/pty_spawn.js"

def pty_read_raw(idx: U32, max: U32) -> IO(U32 & Result<&1,&1, U32 & String, String>):
  import "./effs/pty_read.c"
  import "./effs/pty_read.js"

def probe_reads(+idx: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print("READ1-start")
    rr1 : U32 & Result<&1,&1, U32 & String, String> <- pty_read_raw(idx, 4096)
    IO.print("READ1-done")
    IO.print("READ2-start")
    rr2 : U32 & Result<&1,&1, U32 & String, String> <- pty_read_raw(idx, 4096)
    IO.print("READ2-done")
    IO.print("READ3-start")
    rr3 : U32 & Result<&1,&1, U32 & String, String> <- pty_read_raw(idx, 4096)
    IO.print("READ3-done")
    IO.print("PROBE-DONE")

def probe_spawned(r: Result<&1,&1, U32 & String, U32>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.print("SPAWN-fail")
    case Done{idx}:
      probe_reads(idx)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("PROBE-boot")
    IO.print("SPAWN-start")
    r : Result<&1,&1, U32 & String, U32> <- pty_spawn_raw()
    IO.print("SPAWN-done")
    probe_spawned(r)
