# test_wave4_dirty.bend — Wave 4 dirty-region rendering interpreter probes.
# Concatenated AFTER app.bend in a scratch bundle whose app main is renamed
# (see build/wave4_test_run.sh); needs shell_render_dirty, tick_dirty_mask,
# dirty_* bits, viewst_*, term_*, ui defs.
# Run with the pinned Bend 2.0.25 interpreter. Exit code = FAIL count.

# ---------- fixtures ----------

def t4_d() -> Nat:
  Nat.add(5n, 6n)

def t4_acc0() -> AccSt:
  Acc{"", False{}, 0, MOff{}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", False{}, 0, 0}, HOff{}}

def t4_acc_touched() -> AccSt:
  Acc{"", False{}, 0, MOff{}, AOff{}, NOff{}, False{}, True{}, None{}, Pal{"", False{}, 0, 0}, HOff{}}

def t4_acc_search() -> AccSt:
  Acc{"", True{}, 0, MOff{}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", False{}, 0, 0}, HOff{}}

def t4_acc_pal() -> AccSt:
  Acc{"", False{}, 0, MOff{}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", True{}, 0, 0}, HOff{}}

def t4_vs0() -> ViewSt:
  viewst_new("")

def t4_vs_page1_go(+vs: ViewSt) -> ViewSt:
  match vs:
    case VSt{_, f, a, s, rl}: VSt{1, f, a, s, rl}

def t4_vs_page1() -> ViewSt:
  t4_vs_page1_go(t4_vs0())

def t4_vs_scroll5_go(+vs: ViewSt) -> ViewSt:
  match vs:
    case VSt{p, f, a, _, rl}: VSt{p, f, a, 5, rl}

def t4_vs_scroll5() -> ViewSt:
  t4_vs_scroll5_go(t4_vs0())

def t4_vs_rfocus_go(+vs: ViewSt) -> ViewSt:
  match vs:
    case VSt{p, _, a, s, rl}: VSt{p, True{}, a, s, rl}

def t4_vs_rfocus() -> ViewSt:
  t4_vs_rfocus_go(t4_vs0())

def t4_items() -> List<&2, Item>:
  It{"alpha", 1, "", 0n, ""} <> It{"beta", 2, "", 0n, ""} <> It{"gamma", 3, "", 0n, ""} <> Nil{}

def t4_long_title() -> String:
  "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

def t4_items_long() -> List<&2, Item>:
  It{t4_long_title(), 1, "", 0n, ""} <> It{"beta", 2, "", 0n, ""} <> Nil{}

def t4_term_out() -> Term:
  term_line("hello dirty world", term_line("$ echo hi", term_new()))

# mask with a single diff against the all-quiet baseline
def t4_m(+sel2: U32, +dirty: Bool, +tchanged: U32, +tc: Bool, +tfc: Bool, +vs2: ViewSt, +emode2: U32, +hover2: U32, +feed2: String, +acc: AccSt, +ff: Bool) -> U32:
  tick_dirty_mask(0, sel2, dirty, tchanged, tc, tfc, t4_vs0(), vs2, 0, emode2, 0, hover2, "", feed2, acc, ff)

def t4_full(+items: List<&2, Item>, +t: Term, +vs: ViewSt, +hover: U32) -> Image:
  shell_render(t4_d(), 0, items, t, False{}, vs, hover, 0, 1, "default")

def t4_dirty(+frame: Image, +mask: U32, +items: List<&2, Item>, +t: Term, +vs: ViewSt, +hover: U32) -> Image:
  shell_render_dirty(t4_d(), frame, mask, theme_dark(), 0, items, t, False{}, vs, hover, 0, 1, "default")

# ---------- sampled pixel comparison (32x32 points over the 1440x960 canvas) ----------

def t4_x(+i: U32) -> U32:
  U32.add(16, U32.mul(U32.mod(i, 32), 44))

def t4_y(+i: U32) -> U32:
  U32.add(16, U32.mul(U32.div(i, 32), 29))

def t4_px_eq(+a: Image, +b: Image, +x: U32, +y: U32) -> Bool:
  U32.is_eq(get_pixel(t4_d(), a, x, y), get_pixel(t4_d(), b, x, y))

def t4_cmp_go(n: Nat, +idx: U32, +a: Image, +b: Image) -> Bool:
  match n:
    case 0n: t4_px_eq(a, b, t4_x(idx), t4_y(idx))
    case 1n+m:
      Bool.and(t4_px_eq(a, b, t4_x(idx), t4_y(idx)), t4_cmp_go(m, U32.add(idx, 1), a, b))

def t4_same(+a: Image, +b: Image) -> Bool:
  t4_cmp_go(1024n, 0, a, b)

# ---------- mask tests ----------

def t4_t01() -> Bool: U32.is_eq(t4_m(1, False{}, 0, False{}, False{}, t4_vs0(), 0, 0, "", t4_acc0(), False{}), 6)
def t4_t02() -> Bool: U32.is_eq(t4_m(0, True{}, 0, False{}, False{}, t4_vs0(), 0, 0, "", t4_acc0(), False{}), 6)
def t4_t03() -> Bool: U32.is_eq(t4_m(0, False{}, 0, True{}, False{}, t4_vs0(), 0, 0, "", t4_acc0(), False{}), 16)
def t4_t04() -> Bool: U32.is_eq(t4_m(0, False{}, 0, False{}, True{}, t4_vs0(), 0, 0, "", t4_acc0(), False{}), 16)
def t4_t05() -> Bool: U32.is_eq(t4_m(0, False{}, 1, False{}, False{}, t4_vs0(), 0, 0, "", t4_acc0(), False{}), 16)
def t4_t06() -> Bool: U32.is_eq(t4_m(0, False{}, 0, False{}, False{}, t4_vs0(), 0, 3, "", t4_acc0(), False{}), 2)
def t4_t07() -> Bool: U32.is_eq(t4_m(0, False{}, 0, False{}, False{}, t4_vs0(), 0, 0, "http://x/y", t4_acc0(), False{}), 8)
def t4_t08() -> Bool: U32.is_eq(t4_m(0, False{}, 0, False{}, False{}, t4_vs_page1(), 0, 0, "", t4_acc0(), False{}), 4)
def t4_t09() -> Bool: U32.is_eq(t4_m(0, False{}, 0, False{}, False{}, t4_vs_scroll5(), 0, 0, "", t4_acc0(), False{}), 8)
def t4_t10() -> Bool: U32.is_eq(t4_m(0, False{}, 0, False{}, False{}, t4_vs0(), 1, 0, "", t4_acc0(), False{}), 31)
def t4_t11() -> Bool: U32.is_eq(t4_m(0, False{}, 0, False{}, False{}, t4_vs0(), 0, 0, "", t4_acc_touched(), False{}), 31)
def t4_t12() -> Bool: U32.is_eq(t4_m(0, False{}, 0, False{}, False{}, t4_vs0(), 0, 0, "", t4_acc_search(), False{}), 31)
def t4_t13() -> Bool: U32.is_eq(t4_m(0, False{}, 0, False{}, False{}, t4_vs0(), 0, 0, "", t4_acc_pal(), False{}), 31)
def t4_t14() -> Bool: U32.is_eq(t4_m(0, False{}, 0, False{}, False{}, t4_vs0(), 0, 0, "", t4_acc0(), True{}), 31)
def t4_t15() -> Bool: U32.is_eq(t4_m(0, False{}, 0, False{}, False{}, t4_vs0(), 0, 0, "", t4_acc0(), False{}), 0)
def t4_t16() -> Bool:
  Bool.and(Bool.and(bool_not(dirty_usable(0)), dirty_usable(16)),
           Bool.and(bool_not(dirty_usable(31)), dirty_usable(6)))
def t4_t17() -> Bool: U32.is_eq(t4_m(2, False{}, 0, True{}, False{}, t4_vs0(), 0, 4, "", t4_acc0(), False{}), 22)
def t4_t18() -> Bool: U32.is_eq(t4_m(0, False{}, 0, False{}, False{}, t4_vs_rfocus(), 0, 0, "", t4_acc0(), False{}), 8)

# ---------- pixel-equivalence tests ----------

# all-dirty on a black base == full render
def t4_t19() -> Bool:
  +full = t4_full(t4_items(), term_new(), t4_vs0(), 0)
  +black = solid_tree(t4_d(), rgb(0, 0, 0))
  t4_same(t4_dirty(black, 31, t4_items(), term_new(), t4_vs0(), 0), full)

# terminal-only dirty: new PTY output
def t4_t20() -> Bool:
  +f0 = t4_full(t4_items(), term_new(), t4_vs0(), 0)
  +fd = t4_dirty(f0, 16, t4_items(), t4_term_out(), t4_vs0(), 0)
  t4_same(fd, t4_full(t4_items(), t4_term_out(), t4_vs0(), 0))

# hostile: 200-char title shrinks to short; items-grid dirty
def t4_t21() -> Bool:
  +f0 = t4_full(t4_items_long(), term_new(), t4_vs0(), 0)
  +fd = t4_dirty(f0, 6, t4_items(), term_new(), t4_vs0(), 0)
  t4_same(fd, t4_full(t4_items(), term_new(), t4_vs0(), 0))

# reader scroll
def t4_t22() -> Bool:
  +f0 = t4_full(t4_items(), term_new(), t4_vs0(), 0)
  +fd = t4_dirty(f0, 8, t4_items(), term_new(), t4_vs_scroll5(), 0)
  t4_same(fd, t4_full(t4_items(), term_new(), t4_vs_scroll5(), 0))

# hover change on theme buttons
def t4_t23() -> Bool:
  +f0 = t4_full(t4_items(), term_new(), t4_vs0(), 0)
  +fd = t4_dirty(f0, 2, t4_items(), term_new(), t4_vs0(), 3)
  t4_same(fd, t4_full(t4_items(), term_new(), t4_vs0(), 3))

# empty mask is a no-op on the cached frame
def t4_t24() -> Bool:
  +f0 = t4_full(t4_items(), term_new(), t4_vs0(), 0)
  t4_same(t4_dirty(f0, 0, t4_items(), t4_term_out(), t4_vs_scroll5(), 3), f0)

def t4_line(+name: String, +ok: Bool) -> String:
  match ok:
    case True{}: String.append("PASS ", name)
    case False{}: String.append("FAIL ", name)

def t4_main() -> String:
  String.append(t4_line("t01 sel change -> SIDE|ITEMS", t4_t01()),
  String.append("\n",
  String.append(t4_line("t02 items dirty -> SIDE|ITEMS", t4_t02()),
  String.append("\n",
  String.append(t4_line("t03 term_changed -> TERM", t4_t03()),
  String.append("\n",
  String.append(t4_line("t04 tfocus_changed -> TERM", t4_t04()),
  String.append("\n",
  String.append(t4_line("t05 tchanged!=0 -> TERM", t4_t05()),
  String.append("\n",
  String.append(t4_line("t06 hover change -> SIDE", t4_t06()),
  String.append("\n",
  String.append(t4_line("t07 feed change -> READER", t4_t07()),
  String.append("\n",
  String.append(t4_line("t08 vs page -> ITEMS", t4_t08()),
  String.append("\n",
  String.append(t4_line("t09 vs scroll -> READER", t4_t09()),
  String.append("\n",
  String.append(t4_line("t10 entry mode -> ALL", t4_t10()),
  String.append("\n",
  String.append(t4_line("t11 accd -> ALL", t4_t11()),
  String.append("\n",
  String.append(t4_line("t12 overlay open -> ALL", t4_t12()),
  String.append("\n",
  String.append(t4_line("t13 palette open -> ALL", t4_t13()),
  String.append("\n",
  String.append(t4_line("t14 force_full -> ALL", t4_t14()),
  String.append("\n",
  String.append(t4_line("t15 no change -> 0", t4_t15()),
  String.append("\n",
  String.append(t4_line("t16 dirty_usable gate", t4_t16()),
  String.append("\n",
  String.append(t4_line("t17 combo sel+term+hover -> 22", t4_t17()),
  String.append("\n",
  String.append(t4_line("t18 rfocus -> READER", t4_t18()),
  String.append("\n",
  String.append(t4_line("t19 all-dirty == full", t4_t19()),
  String.append("\n",
  String.append(t4_line("t20 term-only dirty == full", t4_t20()),
  String.append("\n",
  String.append(t4_line("t21 hostile title shrink == full", t4_t21()),
  String.append("\n",
  String.append(t4_line("t22 reader scroll dirty == full", t4_t22()),
  String.append("\n",
  String.append(t4_line("t23 hover dirty == full", t4_t23()),
  String.append("\n",
  t4_line("t24 empty mask no-op", t4_t24())))))))))))))))))))))))))))))))))))))))))))))))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(t4_main())
