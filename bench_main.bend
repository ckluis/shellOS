# Benchmark main: separates frame construction from PPM encoding.
# Not a module: concatenated AFTER font.bend img.bend ui.bend reader.bend
# term.bend shell.bend.
# Build: cat font.bend img.bend ui.bend reader.bend term.bend shell.bend bench_main.bend > build/bench_all.bend
# Output: /tmp/bench.ppm + timing lines on stdout.

# Pure helper: multi-use time math lives here, where + params are reusable.
def times_str(+t0: Nat, +t1: Nat, +t2: Nat, +t3: Nat) -> String:
  String.append("construct_ms=",
    String.append(Nat.show(Nat.sub(t1, t0)),
      String.append(" encode_ms=",
        String.append(Nat.show(Nat.sub(t2, t1)),
          String.append(" write_ms=", Nat.show(Nat.sub(t3, t2)))))))

def bench_done(wr: File & Result<&1,&1, U32 & String, Unit>, t0: Nat, t1: Nat, t2: Nat) -> IO(Unit):
  (f2, rres) = wr
  do IO<Unit>:
    _u : Unit <- File.close(f2)
    t3 : Nat <- IO.now()
    IO.print(times_str(t0, t1, t2, t3))

def bench_write(or_: Result<&1,&1, U32 & String, File>, px: List<&2, U32>, t0: Nat, t1: Nat, t2: Nat) -> IO(Unit):
  match or_:
    case Fail{e}: IO.print("bench: open failed")
    case Done{f}:
      do IO<Unit>:
        wr : File & Result<&1,&1, U32 & String, Unit> <- File.write_bytes(f, px)
        bench_done(wr, t0, t1, t2)

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    items : List<&2, Item> <- load_items()
    +w : Nat = Nat.mul(32n, 32n)
    +d : Nat = Nat.add(5n, 5n)
    +img : Image = shell_render(d, 0, items, term_new(), False{}, viewst_new(""), 0, 0, 1, "default")
    t1 : Nat <- IO.now()
    +px : List<&2, U32> = ppm_bytes(img, d, w, w)
    t2 : Nat <- IO.now()
    or_ : Result<&1,&1, U32 & String, File> <- File.open("/tmp/bench.ppm", "w")
    bench_write(or_, px, t0, t1, t2)
