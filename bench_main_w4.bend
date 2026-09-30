# bench_main_w4.bend — Wave 4 benchmark: full vs dirty-region construction.
# Not a module: concatenated AFTER font.bend img.bend ui.bend reader.bend
# term.bend shell.bend (img.bend already carries the ppm_list_append rename).
# Phases: full construct | dirty(term) | dirty(side+items) | dirty(all) |
# encode | write. items.txt is loaded 4x up front (untimed; each bind used
# once) so every timed phase is pure construction. Output: /tmp/bench_w4.ppm
# + timing lines on stdout.

def bench4_show6(+t0: Nat, +t1: Nat, +t2: Nat, +t3: Nat, +t4: Nat, +t5: Nat, +t6: Nat) -> String:
  +c0 = String.append("construct_ms=", Nat.show(Nat.sub(t1, t0)))
  +c1 = String.append(" dirty_term_ms=", Nat.show(Nat.sub(t2, t1)))
  +c2 = String.append(" dirty_chrome_ms=", Nat.show(Nat.sub(t3, t2)))
  +c3 = String.append(" dirty_all_ms=", Nat.show(Nat.sub(t4, t3)))
  +c4 = String.append(" encode_ms=", Nat.show(Nat.sub(t5, t4)))
  +c5 = String.append(" write_ms=", Nat.show(Nat.sub(t6, t5)))
  String.append(c0, String.append(c1, String.append(c2, String.append(c3, String.append(c4, c5)))))

def bench4_done(wr: File & Result<&1,&1, U32 & String, Unit>, t0: Nat, t1: Nat, t2: Nat, t3: Nat, t4: Nat, t5: Nat) -> IO(Unit):
  (f2, rres) = wr
  do IO<Unit>:
    _u : Unit <- File.close(f2)
    t6 : Nat <- IO.now()
    IO.print(bench4_show6(t0, t1, t2, t3, t4, t5, t6))

def bench4_write(or_: Result<&1,&1, U32 & String, File>, px: List<&2, U32>, t0: Nat, t1: Nat, t2: Nat, t3: Nat, t4: Nat, t5: Nat) -> IO(Unit):
  match or_:
    case Fail{e}: IO.print("bench: open failed")
    case Done{f}:
      do IO<Unit>:
        wr : File & Result<&1,&1, U32 & String, Unit> <- File.write_bytes(f, px)
        bench4_done(wr, t0, t1, t2, t3, t4, t5)

def main() -> IO(Unit):
  do IO<Unit>:
    itemsA : List<&2, Item> <- load_items()
    itemsB : List<&2, Item> <- load_items()
    itemsC : List<&2, Item> <- load_items()
    itemsD : List<&2, Item> <- load_items()
    +w : Nat = Nat.mul(32n, 32n)
    +d : Nat = Nat.add(5n, 5n)
    +th : Theme = theme_dark()
    +tA : Term = term_new()
    +tB : Term = term_line("hello dirty world", term_line("$ echo hi", term_new()))
    +vs : ViewSt = viewst_new("")
    t0 : Nat <- IO.now()
    # full-frame construct (directly comparable to the Wave-3 baseline number)
    +img : Image = shell_render(d, 0, itemsA, tA, False{}, vs, 0, 0, 1, "default")
    t1 : Nat <- IO.now()
    # terminal-only dirty re-rasterization on the cached frame
    +img2 : Image = shell_render_dirty(d, img, dirty_term(), th, 0, itemsB, tB, False{}, vs, 0, 0, 1, "default")
    t2 : Nat <- IO.now()
    # side+items dirty (selection/title chrome)
    +img3 : Image = shell_render_dirty(d, img2, U32.or(dirty_side(), dirty_items()), th, 1, itemsC, tB, False{}, vs, 0, 0, 1, "default")
    t3 : Nat <- IO.now()
    # all-dirty re-rasterization (worst case, must be <= full construct)
    +img4 : Image = shell_render_dirty(d, img3, dirty_all(), th, 1, itemsD, tB, False{}, vs, 0, 0, 1, "default")
    t4 : Nat <- IO.now()
    +px : List<&2, U32> = ppm_bytes(img4, d, w, w)
    t5 : Nat <- IO.now()
    or_ : Result<&1,&1, U32 & String, File> <- File.open("/tmp/bench_w4.ppm", "w")
    bench4_write(or_, px, t0, t1, t2, t3, t4, t5)
