# pty.bend: pseudo-terminal effects for a live terminal tile.
# Native-only: the JS stubs fail with ENOSYS (Node has no built-in PTY).
# The pty master fd is non-blocking so the UI thread can poll it.
#
# Indexed-handle design: the C code keeps a table idx -> fd. Bend's Pty is
# Data{PtyHandle{idx: U32}}, so it can live in Data constructors (raw
# io_hand terms cannot). The raw C functions take/return U32 indices;
# the Pty.* wrappers below convert between PtyHandle and U32.
# (No `import Base` here: this file is concatenated AFTER font.bend,
# which already imports Base; mid-file imports are a syntax error.)

type Pty is Data:
  PtyHandle{idx: U32}

# Optional Pty for the shell state.
type MaybePty is Data:
  NoPty{}
  YesPty{pty: Pty}

# Raw C effects (U32 index based).
# WAVE 2: pty_spawn_raw takes no path argument — the C side always execs
# "/bin/sh". The seam cannot express another binary.
def pty_spawn_raw() -> IO(Result<&1,&1, U32 & String, U32>):
  import "./effs/pty_spawn.c"
  import "./effs/pty_spawn.js"

def pty_read_raw(idx: U32, max: U32) -> IO(U32 & Result<&1,&1, U32 & String, String>):
  import "./effs/pty_read.c"
  import "./effs/pty_read.js"

def pty_write_raw(idx: U32, data: String) -> IO(U32 & Result<&1,&1, U32 & String, Unit>):
  import "./effs/pty_write.c"
  import "./effs/pty_write.js"

def pty_close_raw(idx: U32) -> IO(Unit):
  import "./effs/pty_close.c"
  import "./effs/pty_close.js"

# Safe wrappers: convert between PtyHandle{idx} and raw U32.
def pty_wrap(or_: Result<&1,&1, U32 & String, U32>) -> Result<&1,&1, U32 & String, Pty>:
  match or_:
    case Fail{e}: Fail{e}
    case Done{idx}: Done{PtyHandle{idx}}

def Pty.spawn() -> IO(Result<&1,&1, U32 & String, Pty>):
  do IO<Result<&1,&1, U32 & String, Pty>>:
    r : Result<&1,&1, U32 & String, U32> <- pty_spawn_raw()
    IO.pure(Result<&1,&1, U32 & String, Pty>, pty_wrap(r))

def pty_unwrap_read(rr: U32 & Result<&1,&1, U32 & String, String>) -> Pty & Result<&1,&1, U32 & String, String>:
  match rr:
    case (idx, res): (PtyHandle{idx}, res)

def Pty.read(pty: Pty, max: U32) -> IO(Pty & Result<&1,&1, U32 & String, String>):
  match pty:
    case PtyHandle{idx}:
      do IO<Pty & Result<&1,&1, U32 & String, String>>:
        rr : U32 & Result<&1,&1, U32 & String, String> <- pty_read_raw(idx, max)
        IO.pure(Pty & Result<&1,&1, U32 & String, String>, pty_unwrap_read(rr))

def pty_unwrap_write(wr: U32 & Result<&1,&1, U32 & String, Unit>) -> Pty & Result<&1,&1, U32 & String, Unit>:
  match wr:
    case (idx, res): (PtyHandle{idx}, res)

def Pty.write(pty: Pty, data: String) -> IO(Pty & Result<&1,&1, U32 & String, Unit>):
  match pty:
    case PtyHandle{idx}:
      do IO<Pty & Result<&1,&1, U32 & String, Unit>>:
        wr : U32 & Result<&1,&1, U32 & String, Unit> <- pty_write_raw(idx, data)
        IO.pure(Pty & Result<&1,&1, U32 & String, Unit>, pty_unwrap_write(wr))

def Pty.close(pty: Pty) -> IO(Unit):
  match pty:
    case PtyHandle{idx}: pty_close_raw(idx)
