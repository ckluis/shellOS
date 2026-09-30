# pty_io_probe.bend — minimal native io_work test (2026-09-25 15:03 EDT run).
# Hypothesis: the app's 96% userspace spin (frame 1 renders, then hang before
# frame 2, input dead, no syscalls) is Pty.read's io_work completion hanging
# in the NATIVE runtime. Only pty_read/sock_recv/tls_recv use io_work;
# Window.frame is synchronous (frame 1 proves it works). Markers isolate
# whether pty_read_raw (io_work) returns natively.
# Placed in pure/ so "./effs/..." imports resolve.

import Base

def pty_spawn_raw() -> IO(Result<&1,&1, U32 & String, U32>):
  import "./effs/pty_spawn.c"
  import "./effs/pty_spawn.js"

def pty_read_raw(idx: U32, max: U32) -> IO(U32 & Result<&1,&1, U32 & String, String>):
  import "./effs/pty_read.c"
  import "./effs/pty_read.js"

def probe_read(idx: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print("READ-start")
    rr : U32 & Result<&1,&1, U32 & String, String> <- pty_read_raw(idx, 4096)
    IO.print("READ-done")
    IO.print("PROBE-DONE")

def probe_spawned(r: Result<&1,&1, U32 & String, U32>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.print("SPAWN-fail")
    case Done{idx}:
      probe_read(idx)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("PROBE-boot")
    IO.print("SPAWN-start")
    r : Result<&1,&1, U32 & String, U32> <- pty_spawn_raw()
    IO.print("SPAWN-done")
    probe_spawned(r)
