# pty_probe.bend — standalone PTY regression.
# Concatenated AFTER pty.bend (needs Pty defs; no `import Base` here).
# Spawns /bin/sh, writes `echo hello-pty`, sleeps 1.5s (lets the child run),
# does ONE non-blocking read, checks for the marker, closes, prints PASS/FAIL.
# Exit code is always 0; the verdict is the printed line (parsed by
# tests/pty_probe.sh, which also checks for zombies).
#
# Build: cat font.bend pty.bend tests/pty_probe.bend > build/pty_probe_all.bend
#        bend build/pty_probe_all.bend -o build/pty_probe

# (The Fail payload is U32 & String, a Type-kind pair we can't scrutinize;
# the stage name in the message is the diagnostic.)
def probe_close_print(pty: Pty, +msg: String) -> IO(Unit):
  do IO<Unit>:
    _u : Unit <- Pty.close(pty)
    IO.print(msg)

# Split like tick_poll_go/tick_poll_res: the match on rres lives at def-body
# level so pty may be used once per arm. `out` goes through + params so it
# can be both searched and reported (match binders are affine).
def probe_got2(pty: Pty, +out: String, +found: Bool) -> IO(Unit):
  match found:
    case True{}: probe_close_print(pty, "PASS: hello-pty echoed")
    case False{}:
      probe_close_print(pty, String.append("FAIL: marker missing in: ", out))

def probe_got(pty: Pty, +out: String) -> IO(Unit):
  probe_got2(pty, out, String.contains(out, "hello-pty"))

def probe_read_res(pty: Pty, rres: Result<&1,&1, U32 & String, String>) -> IO(Unit):
  match rres:
    case Fail{e}: probe_close_print(pty, "FAIL: read failed")
    case Done{out}: probe_got(pty, out)

def probe_read(rr: Pty & Result<&1,&1, U32 & String, String>) -> IO(Unit):
  match rr:
    case (pty, rres): probe_read_res(pty, rres)

def probe_written_res(pty: Pty, rres: Result<&1,&1, U32 & String, Unit>) -> IO(Unit):
  match rres:
    case Fail{e}:
      probe_close_print(pty, "FAIL: write failed")
    case Done{_}:
      do IO<Unit>:
        _u : Unit <- IO.sleep(1500)
        rr : Pty & Result<&1,&1, U32 & String, String> <- Pty.read(pty, 4096)
        probe_read(rr)

def probe_written(wr: Pty & Result<&1,&1, U32 & String, Unit>) -> IO(Unit):
  match wr:
    case (pty, rres): probe_written_res(pty, rres)

def probe_spawned(or_: Result<&1,&1, U32 & String, Pty>) -> IO(Unit):
  match or_:
    case Fail{e}:
      IO.print("FAIL: spawn failed")
    case Done{pty}:
      do IO<Unit>:
        wr : Pty & Result<&1,&1, U32 & String, Unit> <- Pty.write(pty, "echo hello-pty\n")
        probe_written(wr)

def main() -> IO(Unit):
  do IO<Unit>:
    or_ : Result<&1,&1, U32 & String, Pty> <- Pty.spawn()
    probe_spawned(or_)
