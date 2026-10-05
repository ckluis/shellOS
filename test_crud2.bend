# test_crud2.bend — CRUD entry-flow tests. Concatenated AFTER app.bend.

def t_items() -> List<&2, Item>:
  Con{It{"first", 0}, Con{It{"second", 1}, Con{It{"third", 2}, Nil{}}}}

def t_items1() -> List<&2, Item>:
  Con{It{"only", 2}, Nil{}}

def t_vs() -> ViewSt:
  viewst_new("")

def t_st0() -> EvSt:
  evst_new(0, t_items(), False{}, t_vs(), "", 0)

def t_k1(a: U32) -> List<Event>:
  Con{Key{a, True{}}, Nil{}}

def t_k2(a: U32, b: U32) -> List<Event>:
  Con{Key{a, True{}}, Con{Key{b, True{}}, Nil{}}}

def t_k3(a: U32, b: U32, c: U32) -> List<Event>:
  Con{Key{a, True{}}, Con{Key{b, True{}}, Con{Key{c, True{}}, Nil{}}}}

def t_k4(a: U32, b: U32, c: U32, d: U32) -> List<Event>:
  Con{Key{a, True{}}, Con{Key{b, True{}}, Con{Key{c, True{}}, Con{Key{d, True{}}, Nil{}}}}}

def t_k5(a: U32, b: U32, c: U32, d: U32, e: U32) -> List<Event>:
  Con{Key{a, True{}}, Con{Key{b, True{}}, Con{Key{c, True{}}, Con{Key{d, True{}}, Con{Key{e, True{}}, Nil{}}}}}}

def t_rep_go(+n: Nat, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+m: t_rep_go(m, String.append(acc, "x"))

def t_rep(n: Nat) -> String:
  t_rep_go(n, "")

def t_nl() -> String:
  Char.show(Chr{10})

def t_bshow(b: Bool) -> String:
  match b:
    case True{}: "T"
    case False{}: "F"

# String equality (Base has no String.is_eq here). Single self-recursion only:
# each iteration precomputes the next iteration's String.get results as params,
# and char equality folds into acc via multiplication (1 = all equal so far).
def t_char_code(c: Char) -> U32:
  match c:
    case Chr{n}: n

def t_bool_nat(b: Bool) -> Nat:
  match b:
    case True{}: 1n
    case False{}: 0n

def t_none_nat(mc: Maybe<&2, Char>) -> Nat:
  match mc:
    case None{}: 1n
    case Some{c}: 0n

def t_some_eq_nat(mc: Maybe<&2, Char>, c1: Char) -> Nat:
  match mc:
    case None{}: 0n
    case Some{c2}: t_bool_nat(U32.is_eq(t_char_code(c1), t_char_code(c2)))

def t_maybe_char_eq_nat(mc1: Maybe<&2, Char>, mc2: Maybe<&2, Char>) -> Nat:
  match mc1:
    case None{}: t_none_nat(mc2)
    case Some{c1}: t_some_eq_nat(mc2, c1)

def t_str_eq_go(n: Nat, +a: String, +b: String, +i: Nat, acc: Nat, mc1: Maybe<&2, Char>, mc2: Maybe<&2, Char>) -> Nat:
  match n:
    case 0n: Nat.mul(acc, t_none_nat(mc2))
    case 1n+m: t_str_eq_go(m, a, b, Nat.add(i, 1n), Nat.mul(acc, t_maybe_char_eq_nat(mc1, mc2)), String.get(a, Nat.add(i, 1n)), String.get(b, Nat.add(i, 1n)))

def t_str_eq_nat(n: Nat) -> Bool:
  match n:
    case 0n: False{}
    case 1n+m: True{}

def t_str_eq(+a: String, +b: String) -> Bool:
  t_str_eq_nat(t_str_eq_go(String.length(a), a, b, 0n, 1n, String.get(a, 0n), String.get(b, 0n)))

def t_nat_is_zero(n: Nat) -> Bool:
  match n:
    case 0n: True{}
    case 1n+m: False{}

def t_nat_eq(+x: Nat, +y: Nat) -> Bool:
  Bool.and(t_nat_is_zero(Nat.sub(x, y)), t_nat_is_zero(Nat.sub(y, x)))

def t_line(name: String, ok: Bool) -> String:
  match ok:
    case True{}: String.append(String.append("PASS ", name), t_nl())
    case False{}: String.append(String.append("FAIL ", name), t_nl())

# mode|entry|count|sel|dirty|tfocus
def t_summary(st: EvSt) -> String:
  match st:
    case EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, entry_mode}:
      String.append(U32.show(entry_mode), String.append("|", String.append(entry,
        String.append("|", String.append(U32.show(items_count(items)),
          String.append("|", String.append(U32.show(sel),
            String.append("|", String.append(t_bshow(dirty), String.append("|", t_bshow(tfocus)))))))))))

def t_entry_of(st: EvSt) -> String:
  match st:
    case EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, entry_mode}: entry

def t_tfocus_of(st: EvSt) -> Bool:
  match st:
    case EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, entry_mode}: tfocus

def t_last_go(items: List<&2, Item>, acc_title: String, acc_theme: U32) -> String & U32:
  match items:
    case Nil{}: (acc_title, acc_theme)
    case Con{it, rest}:
      match it:
        case It{title, theme}: t_last_go(rest, title, theme)

def t_fst(p: String & U32) -> String:
  match p:
    case (title, theme): title

def t_snd(p: String & U32) -> U32:
  match p:
    case (title, theme): theme

def t_last_title(items: List<&2, Item>) -> String:
  t_fst(t_last_go(items, "", 0))

def t_last_theme(items: List<&2, Item>) -> U32:
  t_snd(t_last_go(items, "", 0))

def t_last_title_of(st: EvSt) -> String:
  match st:
    case EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, entry_mode}: t_last_title(items)

def t_last_theme_of(st: EvSt) -> U32:
  match st:
    case EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, entry_mode}: t_last_theme(items)

def t_title_at(st: EvSt, idx: U32) -> String:
  match st:
    case EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, entry_mode}: items_get_title(items, idx)

def t_theme_at(st: EvSt, idx: U32) -> U32:
  match st:
    case EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, entry_mode}: items_get_theme(items, idx)

def t_st_entry(entry: String, mode: U32) -> EvSt:
  EvS{0, t_items(), False{}, False{}, False{}, TtyWNil{}, t_vs(), entry, mode}

# --- tests ---

def t1() -> Bool:
  t_str_eq(t_summary(tick_ev_go(t_k1(97), t_st0())), "1||3|0|F|F")

def t2() -> Bool:
  t_str_eq(t_summary(tick_ev_go(t_k4(97, 104, 105, 13), t_st0())), "0||4|0|T|F")

def t2b() -> Bool:
  t_str_eq(t_last_title_of(tick_ev_go(t_k4(97, 104, 105, 13), t_st0())), "hi")

def t2c() -> Bool:
  U32.is_eq(t_last_theme_of(tick_ev_go(t_k4(97, 104, 105, 13), t_st0())), 0)

def t3() -> Bool:
  t_str_eq(t_summary(tick_ev_go(t_k2(101, 48), evst_new(1, t_items(), False{}, t_vs(), "", 0))), "5|second0|3|1|F|F")

def t4() -> Bool:
  t_str_eq(t_summary(tick_ev_go(t_k2(97, 50), t_st0())), "3||3|0|F|F")

def t5() -> Bool:
  t_str_eq(t_summary(tick_ev_go(t_k3(97, 120, 27), t_st0())), "0||3|0|F|F")

def t6() -> Bool:
  t_str_eq(t_summary(tick_ev_go(t_k2(97, 13), t_st0())), "0||3|0|F|F")

def t7() -> Bool:
  t_str_eq(t_summary(tick_ev_go(t_k4(97, 104, 105, 8), t_st0())), "1|h|3|0|F|F")

def t8() -> Bool:
  t_nat_eq(String.length(t_entry_of(tick_ev_go(t_k1(121), t_st_entry(t_rep(64n), 1)))), 64n)

def t9() -> Bool:
  t_nat_eq(String.length(t_entry_of(tick_ev_go(t_k1(121), t_st_entry(t_rep(100n), 1)))), 100n)

def t10() -> Bool:
  Bool.and(t_nat_eq(String.length(entry_trunc64(t_rep(100n))), 64n),
    Bool.and(t_nat_eq(String.length(entry_trunc64(t_rep(10n))), 10n),
      Bool.and(t_nat_eq(String.length(entry_trunc64(t_rep(64n))), 64n),
        t_str_eq(entry_trunc64("abc"), "abc"))))

def t11() -> Bool:
  t_str_eq(t_summary(tick_ev_go(t_k1(100), evst_new(2, t_items(), False{}, t_vs(), "", 0))), "0||2|1|T|F")

def t12() -> Bool:
  t_str_eq(t_summary(tick_ev_go(t_k1(100), evst_new(0, t_items1(), False{}, t_vs(), "", 0))), "0||0|0|T|F")

def t13() -> Bool:
  t_str_eq(t_summary(tick_ev_go(t_k1(100), evst_new(0, Nil{}, False{}, t_vs(), "", 0))), "0||0|0|F|F")

def t14() -> Bool:
  Bool.and(tick_need(0, 0, False{}, False{}, False{}, t_vs(), t_vs(), 1, 0),
    bool_not(tick_need(0, 0, False{}, False{}, False{}, t_vs(), t_vs(), 0, 0)))

def t15() -> Bool:
  t_str_eq(t_summary(tick_ev_act(20, 0, t_items(), False{}, False{}, False{}, TtyWNil{}, t_vs())), "1||3|0|F|F")

def t16() -> Bool:
  t_tfocus_of(tick_ev_single_normal(Key{65, False{}}, 0, t_items(), True{}, False{}, False{}, TtyWNil{}, t_vs()))

def t17() -> Bool:
  Bool.and(t_str_eq(entry_mode_label(0), ""),
    Bool.and(t_str_eq(entry_mode_label(1), "ADD [0]"),
      t_str_eq(entry_mode_label(5), "EDIT")))

def t18a() -> Bool:
  t_str_eq(t_summary(tick_ev_go(t_k3(101, 33, 13), evst_new(1, t_items(), False{}, t_vs(), "", 0))), "0||3|1|T|F")

def t18b() -> Bool:
  t_str_eq(t_title_at(tick_ev_go(t_k3(101, 33, 13), evst_new(1, t_items(), False{}, t_vs(), "", 0)), 1), "second!")

def t18c() -> Bool:
  U32.is_eq(t_theme_at(tick_ev_go(t_k3(101, 33, 13), evst_new(1, t_items(), False{}, t_vs(), "", 0)), 1), 1)

def t19() -> Bool:
  Bool.and(
    U32.is_eq(t_last_theme_of(tick_ev_go(t_k5(97, 50, 97, 98, 13), t_st0())), 2),
    t_str_eq(t_last_title_of(tick_ev_go(t_k5(97, 50, 97, 98, 13), t_st0())), "ab"))

def main() -> String:
  String.append(t_line("t1 a enters add mode", t1()),
  String.append(t_line("t2 add hi commits", t2()),
  String.append(t_line("t2b committed title", t2b()),
  String.append(t_line("t2c committed theme 0", t2c()),
  String.append(t_line("t3 digit appends in edit", t3()),
  String.append(t_line("t4 digit switches theme in add", t4()),
  String.append(t_line("t5 esc cancels", t5()),
  String.append(t_line("t6 empty enter cancels", t6()),
  String.append(t_line("t7 backspace", t7()),
  String.append(t_line("t8 cap at 64", t8()),
  String.append(t_line("t9 oversized refuses", t9()),
  String.append(t_line("t10 trunc64", t10()),
  String.append(t_line("t11 delete clamps sel", t11()),
  String.append(t_line("t12 delete only item", t12()),
  String.append(t_line("t13 delete from empty", t13()),
  String.append(t_line("t14 need on emode change", t14()),
  String.append(t_line("t15 action20 add mode", t15()),
  String.append(t_line("t16 keyup keeps tfocus", t16()),
  String.append(t_line("t17 labels", t17()),
  String.append(t_line("t18a edit summary", t18a()),
  String.append(t_line("t18b edit title", t18b()),
  String.append(t_line("t18c edit theme kept", t18c()),
  String.append(t_line("t19 add theme 2", t19()), "")))))))))))))))))))))))
