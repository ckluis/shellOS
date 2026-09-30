# wave2_hostile_spawn.bend — negative probe (MUST FAIL typecheck).
# The old call shape Pty.spawn("/bin/evil") must no longer compile:
# the Wave 2 seam accepts no path argument.
def main() -> IO(Unit):
  do IO<Unit>:
    or_ : Result<&1,&1, U32 & String, Pty> <- Pty.spawn("/bin/evil")
    IO.print("SHOULD NOT COMPILE")
