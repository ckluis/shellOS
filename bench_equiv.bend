# bench_equiv.bend — Wave 4 native pixel-equivalence oracle.
# Not a module: concatenated AFTER font.bend img.bend ui.bend reader.bend
# term.bend shell.bend (img.bend already carries the ppm_list_append rename).
# Compares FULL 3,145,728-byte PPM byte lists (not samples): full render vs
# all-dirty on a black base, plus per-region dirty-on-cached-frame renders.
# Prints EQUIV_BITS=n (bit0=all-dirty, bit1=term, bit2=chrome, bit3=reader);
# 15 = all equal. items.txt loaded once (untimed); all comparisons run in one
# pure helper so the single affine items bind is consumed exactly once.

def u32list_eq_go(+a: List<&2, U32>, +b: List<&2, U32>, +acc: Bool) -> Bool:
  match a, b:
    case Nil{}, Nil{}: acc
    case Con{x, xs}, Con{y, ys}: u32list_eq_go(xs, ys, Bool.and(acc, U32.is_eq(x, y)))
    case _, _: False{}

def u32list_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  u32list_eq_go(a, b, True{})

def equiv_bit(+b: Bool, +v: U32) -> U32:
  match b:
    case True{}: v
    case False{}: 0

def equiv_vs_scroll5(+vs: ViewSt) -> ViewSt:
  match vs:
    case VSt{p, f, a, _, rl}: VSt{p, f, a, 5, rl}

def equiv_run(+items: List<&2, Item>, +d: Nat, +w: Nat, +th: Theme, +vs: ViewSt, +tA: Term, +tB: Term) -> U32:
  +full = shell_render(d, 0, items, tA, False{}, vs, 0, 0, 1, "default")
  +black = solid_tree(d, rgb(0, 0, 0))
  +fd_all = shell_render_dirty(d, black, dirty_all(), th, 0, items, tA, False{}, vs, 0, 0, 1, "default")
  +e1 = u32list_eq(ppm_bytes(full, d, w, w), ppm_bytes(fd_all, d, w, w))
  +fullB = shell_render(d, 0, items, tB, False{}, vs, 0, 0, 1, "default")
  +fd_term = shell_render_dirty(d, full, dirty_term(), th, 0, items, tB, False{}, vs, 0, 0, 1, "default")
  +e2 = u32list_eq(ppm_bytes(fullB, d, w, w), ppm_bytes(fd_term, d, w, w))
  +fullS = shell_render(d, 2, items, tA, False{}, vs, 0, 0, 1, "default")
  +fd_chrome = shell_render_dirty(d, full, U32.or(dirty_side(), dirty_items()), th, 2, items, tA, False{}, vs, 0, 0, 1, "default")
  +e3 = u32list_eq(ppm_bytes(fullS, d, w, w), ppm_bytes(fd_chrome, d, w, w))
  +vs5 = equiv_vs_scroll5(vs)
  +fullR = shell_render(d, 0, items, tA, False{}, vs5, 0, 0, 1, "default")
  +fd_reader = shell_render_dirty(d, full, dirty_reader(), th, 0, items, tA, False{}, vs5, 0, 0, 1, "default")
  +e4 = u32list_eq(ppm_bytes(fullR, d, w, w), ppm_bytes(fd_reader, d, w, w))
  U32.add(equiv_bit(e1, 1), U32.add(equiv_bit(e2, 2), U32.add(equiv_bit(e3, 4), equiv_bit(e4, 8))))

def main() -> IO(Unit):
  do IO<Unit>:
    items : List<&2, Item> <- load_items()
    +w : Nat = Nat.mul(32n, 32n)
    +d : Nat = Nat.add(5n, 5n)
    +th : Theme = theme_dark()
    +vs : ViewSt = viewst_new("")
    +tA : Term = term_new()
    +tB : Term = term_line("dirty line 1", term_line("$ echo hi", term_new()))
    +bits : U32 = equiv_run(items, d, w, th, vs, tA, tB)
    IO.print(String.append("EQUIV_BITS=", U32.show(bits)))
