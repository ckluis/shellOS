# test_wave3_palette.bend — Wave 3 command-palette interpreter probes.
# Concatenated AFTER app.bend in a scratch bundle whose app main is renamed
# (see build/wave3_test_run.sh); needs pal_*, acc_*, MailInner defs.
# Run with the pinned Bend 2.0.25 interpreter. Exit code = FAIL count.

# ---- fixtures ----

def p3_acc_closed() -> AccSt:
  Acc{"", False{}, 0, MOff{}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", False{}, 0, 0}, HOff{}}

def p3_acc_pal() -> AccSt:
  Acc{"", False{}, 0, MOff{}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", True{}, 0, 0}, HOff{}}

def p3_acc_pal_sel(+sel: U32) -> AccSt:
  Acc{"", False{}, 0, MOff{}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", True{}, sel, 0}, HOff{}}

def p3_acc_pal_q(+q: String) -> AccSt:
  Acc{"", False{}, 0, MOff{}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{q, True{}, 0, 0}, HOff{}}

def p3_acc_fire(+fire: U32) -> AccSt:
  Acc{"", False{}, 0, MOff{}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", False{}, 0, fire}, HOff{}}

def p3_acc_gfire(+fire: U32) -> AccSt:
  Acc{"", False{}, 0, MOn{MList{"c", "s", "r", "tok", 0n, "", 0, Nil{}, MPg{0, Nil{}, None{}, None{}}}}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", False{}, 0, fire}, HOff{}}

def p3_acc_glist() -> AccSt:
  Acc{"", False{}, 0, MOn{MList{"c", "s", "r", "tok", 0n, "", 0, Nil{}, MPg{0, Nil{}, None{}, None{}}}}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", True{}, 0, 0}, HOff{}}

def p3_acc_gloading() -> AccSt:
  Acc{"", False{}, 0, MOn{MLoading{"c", "s", "r", "tok", MPg{0, Nil{}, None{}, None{}}, "", None{}}}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", True{}, 0, 0}, HOff{}}

def p3_acc_gloading_sel(+sel: U32) -> AccSt:
  Acc{"", False{}, 0, MOn{MLoading{"c", "s", "r", "tok", MPg{0, Nil{}, None{}, None{}}, "", None{}}}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", True{}, sel, 0}, HOff{}}

def p3_acc_greading() -> AccSt:
  Acc{"", False{}, 0, MOn{MReading{"c", "s", "r", "tok", 0n, "", MM{"i", "f", "s", "d"}, "", 0, Nil{}, MPg{0, Nil{}, None{}, None{}}}}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", True{}, 0, 0}, HOff{}}

def p3_acc_glist_sel(+sel: U32) -> AccSt:
  Acc{"", False{}, 0, MOn{MList{"c", "s", "r", "tok", 0n, "", 0, Nil{}, MPg{0, Nil{}, None{}, None{}}}}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", True{}, sel, 0}, HOff{}}

def p3_vs() -> ViewSt:
  VSt{0, False{}, 0, 0, Nil{}}

# ---- inspectors ----

def p3_pal_open(+acc: AccSt) -> Bool:
  match acc:
    case Acc{_, _, _, _, _, _, _, _, _, Pal{_, open, _, _}, _}: open

def p3_search_open(+acc: AccSt) -> Bool:
  match acc:
    case Acc{_, open, _, _, _, _, _, _, _, _, _}: open

def p3_gmail_on(+acc: AccSt) -> Bool:
  match acc:
    case Acc{_, _, _, MOn{_}, _, _, _, _, _, _, _}: True{}
    case _: False{}

def p3_fire_of(+acc: AccSt) -> U32:
  match acc:
    case Acc{_, _, _, _, _, _, _, _, _, Pal{_, _, _, fire}, _}: fire

def p3_q_of(+acc: AccSt) -> String:
  match acc:
    case Acc{_, _, _, _, _, _, _, _, _, Pal{q, _, _, _}, _}: q

def p3_sel_of(+acc: AccSt) -> U32:
  match acc:
    case Acc{_, _, _, _, _, _, _, _, _, Pal{_, _, sel, _}, _}: sel

def p3_key2(kr: AccSt & Bool) -> AccSt:
  match kr:
    case (acc2, _): acc2

def p3_key(+acc: AccSt, +c: U32) -> AccSt:
  p3_key2(acc_pal_key(acc, Nil{}, c, False{}, 0, p3_vs(), "", Nil{}))

def p3_keyb2(kr: AccSt & Bool) -> Bool:
  match kr:
    case (_, b): b

def p3_keyb(+acc: AccSt, +c: U32) -> Bool:
  p3_keyb2(acc_pal_key(acc, Nil{}, c, False{}, 0, p3_vs(), "", Nil{}))

def p3_open2(kr: AccSt & Bool) -> AccSt:
  match kr:
    case (acc2, _): acc2

def p3_open(+tfocus: Bool) -> AccSt:
  p3_open2(acc_closed_key2(p3_acc_closed(), 59, tfocus, p3_vs(), ""))

def p3_rep_go(+n: Nat, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+m: p3_rep_go(m, String.append(acc, "z"))

def p3_rep(+n: Nat) -> String:
  p3_rep_go(n, "")

def p3_bool_and3(+a: Bool, +b: Bool, +c: Bool) -> Bool:
  Bool.and(a, Bool.and(b, c))

# ---- tests ----

# t1..t3b: action-list sizes per context
def p3_t1() -> Bool:
  U32.is_eq(pal_count(pal_actions(0)), 25)

def p3_t2() -> Bool:
  U32.is_eq(pal_count(pal_actions(1)), 4)

def p3_t3() -> Bool:
  U32.is_eq(pal_count(pal_actions(2)), 2)

def p3_t3b() -> Bool:
  U32.is_eq(pal_count(pal_actions(3)), 1)

# t4: empty query matches everything
def p3_t4() -> Bool:
  U32.is_eq(pal_count(pal_filter("", pal_actions(0))), 25)

# t5: no-match query matches nothing
def p3_t5() -> Bool:
  U32.is_eq(pal_count(pal_filter("zzzqxj", pal_actions(0))), 0)

# t6: case-insensitive match
def p3_t6() -> Bool:
  pal_match_text(PAct{113, "Quit", "q - quit Shell-OS"}, "QUIT")

# t7: subsequence match
def p3_t7() -> Bool:
  pal_match_text(PAct{47, "Universal search", "/ - filter-as-you-type"}, "usearch")

# t8: negative match
def p3_t8() -> Bool:
  bool_not(pal_match_text(PAct{113, "Quit", "q - quit Shell-OS"}, "zzz"))

# t9: every action in every context has a key and a one-line desc
def p3_desc_ok(+key: U32, +desc: String) -> Bool:
  Bool.and(bool_not(U32.is_eq(key, 0)), bool_not(Nat.is_eq(String.length(desc), 0n)))

def p3_descs_go(+acts: List<&2, PalAct>) -> Bool:
  match acts:
    case Nil{}: True{}
    case PAct{key, _, desc} <> rest: Bool.and(p3_desc_ok(key, desc), p3_descs_go(rest))

def p3_t9() -> Bool:
  Bool.and(p3_bool_and3(p3_descs_go(pal_actions(0)), p3_descs_go(pal_actions(1)), p3_descs_go(pal_actions(2))),
    p3_descs_go(pal_actions(3)))

# t10: ';' opens the palette from closed state
def p3_t10() -> Bool:
  p3_pal_open(p3_open(False{}))

# t11: ';' does NOT open it with the terminal focused
def p3_t11() -> Bool:
  bool_not(p3_pal_open(p3_open(True{})))

# t12: Esc dismisses mid-palette
def p3_t12() -> Bool:
  bool_not(p3_pal_open(p3_key(p3_acc_pal(), 27)))

# t13: ';' toggles it closed
def p3_t13() -> Bool:
  bool_not(p3_pal_open(p3_key(p3_acc_pal(), 59)))

# t14: typing filters, backspace edits
def p3_t14() -> Bool:
  Bool.and(String.eq(p3_q_of(p3_key(p3_acc_pal(), 97)), "a"),
    String.eq(p3_q_of(p3_key(p3_key(p3_acc_pal(), 97), 127)), ""))

# t15: arrows navigate with clamping
def p3_t15() -> Bool:
  p3_bool_and3(
    U32.is_eq(p3_sel_of(p3_key(p3_acc_pal(), 63233)), 1),
    U32.is_eq(p3_sel_of(p3_key(p3_key(p3_acc_pal(), 63233), 63232)), 0),
    U32.is_eq(p3_sel_of(p3_key(p3_acc_pal(), 63232)), 0))

# t16: Enter on "Universal search" opens search, closes palette, no fire
def p3_t16() -> Bool:
  p3_bool_and3(p3_search_open(p3_key(p3_acc_pal_sel(0), 13)),
    bool_not(p3_pal_open(p3_key(p3_acc_pal_sel(0), 13))),
    U32.is_eq(p3_fire_of(p3_key(p3_acc_pal_sel(0), 13)), 0))

# t17: Enter on "Gmail panel" toggles gmail on, closes palette
def p3_t17() -> Bool:
  Bool.and(p3_gmail_on(p3_key(p3_acc_pal_sel(5), 13)),
    bool_not(p3_pal_open(p3_key(p3_acc_pal_sel(5), 13))))

# t18: Enter on Esc in gmail ctx dismisses the panel (consumed, no fire)
def p3_t18() -> Bool:
  p3_bool_and3(p3_keyb(p3_acc_glist_sel(3), 13),
    bool_not(p3_pal_open(p3_key(p3_acc_glist_sel(3), 13))),
    Bool.and(bool_not(p3_gmail_on(p3_key(p3_acc_glist_sel(3), 13))),
      U32.is_eq(p3_fire_of(p3_key(p3_acc_glist_sel(3), 13)), 0)))

# t19: Enter on "+" parks fire=43 (EvSt fold opens a tab)
def p3_t19() -> Bool:
  U32.is_eq(p3_fire_of(p3_key(p3_acc_pal_sel(11), 13)), 43)

# t20: Enter with no matches keeps the palette open, no fire
def p3_t20() -> Bool:
  Bool.and(p3_pal_open(p3_key(p3_acc_pal_q("zzzqxj"), 13)),
    U32.is_eq(p3_fire_of(p3_key(p3_acc_pal_q("zzzqxj"), 13)), 0))

# t21: fire injects a synthetic key when no panel is open
def p3_evs_head(evs: List<Event>) -> Bool:
  match evs:
    case Con{Key{43, _}, _}: True{}
    case _: False{}

def p3_t21() -> Bool:
  p3_evs_head(acc_fire_evs(p3_acc_fire(43), Nil{}))

# t22: fire is dropped when a panel is open post-dispatch
def p3_evs_nil(evs: List<Event>) -> Bool:
  match evs:
    case Nil{}: True{}
    case _: False{}

def p3_t22() -> Bool:
  p3_evs_nil(acc_fire_evs(p3_acc_gfire(43), Nil{}))

# t23: palette-open acc strips key events
def p3_t23() -> Bool:
  Bool.and(acc_any_open(p3_acc_pal()),
    acc_strip_q(p3_acc_closed(), p3_acc_pal()))

# t24: 4-way context derivation
def p3_t24() -> Bool:
  Bool.and(U32.is_eq(pal_ctx_of(p3_acc_glist()), 1),
    Bool.and(U32.is_eq(pal_ctx_of(p3_acc_closed()), 0),
      Bool.and(U32.is_eq(pal_ctx_of(p3_acc_gloading()), 3),
        U32.is_eq(pal_ctx_of(p3_acc_greading()), 2))))

# t25: gmail ctx — Enter on "Gmail: next page" dispatches to the gmail
# handler (consumed, palette closed, gmail still on, search NOT opened)
def p3_t25() -> Bool:
  p3_bool_and3(p3_keyb(p3_acc_glist_sel(1), 13),
    bool_not(p3_pal_open(p3_key(p3_acc_glist_sel(1), 13))),
    Bool.and(p3_gmail_on(p3_key(p3_acc_glist_sel(1), 13)),
      bool_not(p3_search_open(p3_key(p3_acc_glist_sel(1), 13)))))

# t26: hostile 1000-char query filters without crashing
def p3_t26() -> Bool:
  U32.is_lt(pal_count(pal_filter(p3_rep(Nat.mul(10n, 100n)), pal_actions(0))), 26)

# t27: hostile out-of-range selection — Enter is a safe no-op
def p3_t27() -> Bool:
  p3_pal_open(p3_key(p3_acc_pal_sel(999), 13))

# t28: modal tag — palette outranks everything
def p3_t28() -> Bool:
  Bool.and(U32.is_eq(acc_panel_tag(p3_acc_pal()), 5),
    U32.is_eq(acc_panel_tag(p3_acc_closed()), 0))

# t29: every listed action dispatches (palette ends closed, no crash).
def p3_closed_after(+idx: U32) -> Bool:
  bool_not(p3_pal_open(p3_key(p3_acc_pal_sel(idx), 13)))

def p3_all_go(+acts: List<&2, PalAct>, +idx: U32) -> Bool:
  match acts:
    case Nil{}: True{}
    case _ <> rest: Bool.and(p3_closed_after(idx), p3_all_go(rest, U32.add(idx, 1)))

def p3_t29() -> Bool:
  p3_all_go(pal_actions(0), 0)

# t30: selection-relative windowing — start is the 12-row page containing sel
def p3_t30() -> Bool:
  p3_bool_and3(
    Bool.and(U32.is_eq(pal_win_start(0), 0), U32.is_eq(pal_win_start(11), 0)),
    Bool.and(U32.is_eq(pal_win_start(12), 12), U32.is_eq(pal_win_start(24), 24)),
    U32.is_eq(pal_count(pal_window(pal_actions(0), 24)), 1))

# t31: ctx3 (MLoading) hides `/` — only the Esc dismiss action is listed
def p3_key_is_slash(+acts: List<&2, PalAct>) -> Bool:
  match acts:
    case Nil{}: False{}
    case PAct{key, _, _} <> rest: Bool.or(U32.is_eq(key, 47), p3_key_is_slash(rest))

def p3_t31() -> Bool:
  Bool.and(U32.is_eq(pal_ctx_of(p3_acc_gloading()), 3),
    bool_not(p3_key_is_slash(pal_actions(3))))

# t32: ctx2 (MReading, slashable) keeps `/`
def p3_t32() -> Bool:
  Bool.and(U32.is_eq(pal_ctx_of(p3_acc_greading()), 2),
    p3_key_is_slash(pal_actions(2)))

# t33: Esc is honest — absent in ctx0 (it would quit), present in gmail ctx
def p3_key_is_esc(+acts: List<&2, PalAct>) -> Bool:
  match acts:
    case Nil{}: False{}
    case PAct{key, _, _} <> rest: Bool.or(U32.is_eq(key, 27), p3_key_is_esc(rest))

def p3_t33() -> Bool:
  Bool.and(bool_not(p3_key_is_esc(pal_actions(0))),
    Bool.and(p3_key_is_esc(pal_actions(1)), p3_key_is_esc(pal_actions(3))))

# t34: Enter on Esc in ctx3 (MLoading) dismisses the panel
def p3_t34() -> Bool:
  p3_bool_and3(p3_keyb(p3_acc_gloading_sel(0), 13),
    bool_not(p3_pal_open(p3_key(p3_acc_gloading_sel(0), 13))),
    bool_not(p3_gmail_on(p3_key(p3_acc_gloading_sel(0), 13))))

# ---- driver ----

def p3_line(+name: String, +ok: Bool) -> String:
  match ok:
    case True{}: String.append(String.append("PASS ", name), "\n")
    case False{}: String.append(String.append("FAIL ", name), "\n")

def p3_main() -> String:
  String.append(p3_line("t1 ctx0 has 25 actions", p3_t1()),
  String.append(p3_line("t2 ctx1 has 4 actions", p3_t2()),
  String.append(p3_line("t3 ctx2 has 2 actions (no n/p)", p3_t3()),
  String.append(p3_line("t3b ctx3 has 1 action (Esc only)", p3_t3b()),
  String.append(p3_line("t4 empty query matches all", p3_t4()),
  String.append(p3_line("t5 no-match query matches none", p3_t5()),
  String.append(p3_line("t6 case-insensitive match", p3_t6()),
  String.append(p3_line("t7 subsequence match", p3_t7()),
  String.append(p3_line("t8 negative match", p3_t8()),
  String.append(p3_line("t9 every action has key+desc", p3_t9()),
  String.append(p3_line("t10 ';' opens palette", p3_t10()),
  String.append(p3_line("t11 ';' inert with terminal focused", p3_t11()),
  String.append(p3_line("t12 Esc dismisses", p3_t12()),
  String.append(p3_line("t13 ';' toggles closed", p3_t13()),
  String.append(p3_line("t14 type/backspace edit query", p3_t14()),
  String.append(p3_line("t15 arrows navigate clamped", p3_t15()),
  String.append(p3_line("t16 Enter opens search", p3_t16()),
  String.append(p3_line("t17 Enter toggles gmail", p3_t17()),
  String.append(p3_line("t18 Enter on Esc dismisses gmail panel", p3_t18()),
  String.append(p3_line("t19 Enter on '+' parks fire=43", p3_t19()),
  String.append(p3_line("t20 Enter with no match keeps palette", p3_t20()),
  String.append(p3_line("t21 fire injects synthetic key", p3_t21()),
  String.append(p3_line("t22 fire dropped with panel open", p3_t22()),
  String.append(p3_line("t23 palette-open strips keys", p3_t23()),
  String.append(p3_line("t24 4-way ctx derivation", p3_t24()),
  String.append(p3_line("t25 gmail ctx dispatches n to gmail", p3_t25()),
  String.append(p3_line("t26 hostile 1000-char query", p3_t26()),
  String.append(p3_line("t27 hostile sel out of range", p3_t27()),
  String.append(p3_line("t28 modal tag 5 outranks", p3_t28()),
  String.append(p3_line("t29 all 25 actions dispatch", p3_t29()),
  String.append(p3_line("t30 windowing pages with sel", p3_t30()),
  String.append(p3_line("t31 ctx3 hides '/'", p3_t31()),
  String.append(p3_line("t32 ctx2 keeps '/'", p3_t32()),
  String.append(p3_line("t33 Esc honest per ctx", p3_t33()),
  String.append(p3_line("t34 ctx3 Esc dismisses", p3_t34()),
  "")))))))))))))))))))))))))))))))))))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(p3_main())
