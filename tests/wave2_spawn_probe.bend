# wave2_spawn_probe.bend — positive runtime probe for the Wave 2 narrowing.
# Concatenated AFTER pty.bend. Spawns with the new NO-ARG API, asks the
# child for its argv[0] (`echo $0`), and asserts it is /bin/sh — proving the
# C side execs the fixed literal even though no path argument exists.
# Exit code is always 0; the verdict is the printed line.
#
# Build: cat font.bend pty.bend tests/wave2_spawn_probe.bend > build/wave2_spawn_all.bend
#        bend build/wave2_spawn_all.bend -o build/wave2_spawn_probe

def probe_close_print(pty: Pty, +msg: String) -> IO(Unit):
  do IO<Unit>:
    _u : Unit <- Pty.close(pty)
    IO.print(msg)

def probe_got2(pty: Pty, +out: String, +is_sh: Bool) -> IO(Unit):
  match is_sh:
    case True{}: probe_close_print(pty, "PASS: child argv0 is /bin/sh")
    case False{}:
      probe_close_print(pty, String.append("FAIL: argv0 not /bin/sh in: ", out))

def probe_got(pty: Pty, +out: String) -> IO(Unit):
  probe_got2(pty, out, String.contains(out, "/bin/sh"))

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
        wr : Pty & Result<&1,&1, U32 & String, Unit> <- Pty.write(pty, "echo W2ARGV0=$0\n")
        probe_written(wr)

def main() -> IO(Unit):
  do IO<Unit>:
    or_ : Result<&1,&1, U32 & String, Pty> <- Pty.spawn()
    probe_spawned(or_)
