# test_wave4_scrollback.bend — Wave 4 targeted tests for the terminal
# scrollback viewer. Concatenated AFTER app.bend (needs Term, SbSt, the
# fold key path, and shell.bend's term_title_sb).

# ---- fixtures ----
# 30 labeled lines: line i (0-based) is a single distinct char + "\n"
# (i in 0..25 -> 'a'..'z', 26..29 -> 'A'..'D'). After 30 lines the grid
# holds rows h..D and the scrollback holds a..g (7 scrolled-off lines).
def w4_line_char2(+low: Bool, +i: U32) -> Char:
  match low:
    case True{}: Chr{U32.add(97, i)}
    case False{}: Chr{U32.add(65, U32.sub(i, 26))}

def w4_line_char(+i: U32) -> Char:
  w4_line_char2(U32.is_lt(i, 26), i)

def w4_textline(+i: U32) -> String:
  String.append(Char.show(w4_line_char(i)), Char.show(Chr{10}))

def w4_write_go(+n: Nat, +t: Term, +i: U32) -> Term:
  match n:
    case 0n: t
    case 1n+m: w4_write_go(m, term_write(w4_textline(i), t), U32.add(i, 1))

def w4_nat_eq(+a: Nat, +b: Nat) -> Bool:
  match a, b:
    case 0n, 0n: True{}
    case 0n, _: False{}
    case _, 0n: False{}
    case 1n+x, 1n+y: w4_nat_eq(x, y)

def w4_write_lines(+n: Nat) -> Term:
  w4_write_go(n, term_new(), 0)

def w4_t30() -> Term:
  w4_write_lines(30n)

def w4_sb_of(+t: Term) -> List<&2, String>:
  match t:
    case Tm{_, _, _, _, _, sb, _}: sb

def w4_rep_push_go(+n: Nat, +sb: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: sb
    case 1n+m: w4_rep_push_go(m, sb_push(sb, "x"))

def w4_term_with_sb(+t: Term, +sb: List<&2, String>) -> Term:
  match t:
    case Tm{cells, fg, bg, cx, cy, _, _}: Tm{cells, fg, bg, cx, cy, sb, 0}

def w4_items() -> List<&2, Item>:
  Con{item_plain("x", 0), Nil{}}

def w4_vs() -> ViewSt:
  viewst_new("")

# ---- tests (each -> Bool) ----
# t1: fresh terminal has zero scrollback offset.
def w4_t1() -> Bool:
  U32.is_eq(term_view_off(term_new()), 0)

# t2: 30 lines scroll 7 lines into the buffer.
def w4_t2() -> Bool:
  U32.is_eq(list_len_str(w4_sb_of(w4_t30())), 7)

# t3: PgUp (+24) clamps to the 7 available lines.
def w4_t3() -> Bool:
  U32.is_eq(term_view_off(term_view_up(w4_t30(), 24)), 7)

# t4: a second PgUp saturates (stays 7, never overshoots).
def w4_t4() -> Bool:
  U32.is_eq(term_view_off(term_view_up(term_view_up(w4_t30(), 24), 24)), 7)

# t5: PgDn (-24) returns to live, saturating at 0.
def w4_t5() -> Bool:
  U32.is_eq(term_view_off(term_view_down(term_view_up(w4_t30(), 24), 24)), 0)

# t6: exact scrollback content: oldest "a", newest "g".
def w4_t6() -> Bool:
  Bool.and(String.eq(sb_get(w4_sb_of(w4_t30()), 0), "a"),
           String.eq(sb_get(w4_sb_of(w4_t30()), 6), "g"))

# t7: new PTY output auto-returns the view to live.
def w4_t7() -> Bool:
  U32.is_eq(term_view_off(term_write("z", term_view_up(w4_t30(), 24))), 0)

# t8: an empty write preserves the scrolled view (no new output).
def w4_t8() -> Bool:
  U32.is_eq(term_view_off(term_write("", term_view_up(w4_t30(), 24))), 7)

# t9: the 200-line cap holds and the offset clamps to it.
def w4_t9() -> Bool:
  +sb250 = w4_rep_push_go(250n, Nil{})
  Bool.and(U32.is_eq(list_len_str(sb250), 200),
           U32.is_eq(term_view_off(sb_apply(500, 0, False{}, w4_term_with_sb(term_new(), sb250))), 200))

# t10: sb_apply semantics — up/down accumulate, live wins, net-zero holds.
def w4_t10() -> Bool:
  +up = term_view_off(sb_apply(24, 0, False{}, w4_t30()))
  +lived = term_view_off(sb_apply(0, 0, True{}, term_view_up(w4_t30(), 24)))
  +netz = term_view_off(sb_apply(24, 24, False{}, term_view_up(w4_t30(), 24)))
  Bool.and(U32.is_eq(up, 7), Bool.and(U32.is_eq(lived, 0), U32.is_eq(netz, 7)))

# t11: sb_touched — quiet sidecar vs scroll request vs live request.
def w4_t11() -> Bool:
  +q = sb_touched(sb_none())
  +s = sb_touched(sb_up_add(sb_none(), 24))
  +l = sb_touched(sb_go_live())
  Bool.and(Bool.not(q), Bool.and(s, l))

# t12: title marker appears only while scrolled back.
def w4_t12() -> Bool:
  Bool.and(String.eq(term_title_sb("Terminal [1/1]", 0), "Terminal [1/1]"),
           String.eq(term_title_sb("Terminal [1/1]", 5), "Terminal [1/1] [sb]"))

# t13: PgUp on a focused terminal: +24 requested, NOTHING written to the PTY,
# focus kept.
def w4_t13_go(+up24: Bool, +nowrite: Bool, +kept: Bool) -> Bool:
  Bool.and(up24, Bool.and(nowrite, kept))

def w4_t13_sb(+sb: SbSt) -> Bool:
  match sb:
    case SbS{up, _, _}: U32.is_eq(up, 24)

def w4_t13_ev2(+kept: Bool, writes: TtyWList) -> Bool:
  match writes:
    case TtyWNil{}: kept
    case _: False{}

def w4_t13_ev(ev: EvSt) -> Bool:
  match ev:
    case EvS{_, _, tfocus, _, _, writes, _, _, _}: w4_t13_ev2(tfocus, writes)

def w4_t13_pair(p: EvSt & SbSt) -> Bool:
  match p:
    case (ev, sb): w4_t13_go(w4_t13_sb(sb), w4_t13_ev(ev), True{})

def w4_t13() -> Bool:
  w4_t13_pair(tick_ev_fkey_down_sb(63276, 0, w4_items(), False{}, False{}, TtyWNil{}, w4_vs(), sb_none()))

# t14: a normal focused key ('a') still writes to the PTY and the sidecar
# requests live.
def w4_t14_sb(+sb: SbSt) -> Bool:
  match sb:
    case SbS{_, _, live}: live

def w4_t14_ev(ev: EvSt) -> Bool:
  match ev:
    case EvS{_, _, tfocus, _, _, writes, _, _, _}:
      match writes:
        case TtyWCons{w, TtyWNil{}}: Bool.and(String.eq(w, "a"), tfocus)
        case _: False{}

def w4_t14_pair(p: EvSt & SbSt) -> Bool:
  match p:
    case (ev, sb): Bool.and(w4_t14_sb(sb), w4_t14_ev(ev))

def w4_t14() -> Bool:
  w4_t14_pair(tick_ev_fkey_down_sb(97, 0, w4_items(), False{}, False{}, TtyWNil{}, w4_vs(), sb_none()))

# t15: Esc keeps its old behavior (unfocus) and requests live.
def w4_t15_ev(ev: EvSt) -> Bool:
  match ev:
    case EvS{_, _, tfocus, _, _, _, _, _, _}: Bool.not(tfocus)

def w4_t15_pair(p: EvSt & SbSt) -> Bool:
  match p:
    case (ev, sb): Bool.and(w4_t14_sb(sb), w4_t15_ev(ev))

def w4_t15() -> Bool:
  w4_t15_pair(tick_ev_fkey_down_sb(27, 0, w4_items(), False{}, False{}, TtyWNil{}, w4_vs(), sb_none()))

# t16: the live grid's top row after 30 lines is "h" (viewport window check:
# scrollback rows a..g sit above grid rows h..D).
def w4_t16() -> Bool:
  String.eq(sb_get(term_all_lines(w4_t30()), 7), "h")

# t17: net scroll, up-heavy: 48 up / 24 down at live nets to +24 (clamped to 7).
def w4_t17() -> Bool:
  U32.is_eq(term_view_off(sb_apply(48, 24, False{}, w4_t30())), 7)

# t18: net scroll, down-heavy: 24 up / 48 down from offset 7 nets to -24,
# saturating at 0 (live).
def w4_t18() -> Bool:
  U32.is_eq(term_view_off(sb_apply(24, 48, False{}, term_view_up(w4_t30(), 24))), 0)

# t19: full fold — synthetic key events [t, x, y] focus the terminal and
# queue both chars as PTY writes (oldest first).
def w4_t19_ev(ev: EvSt) -> Bool:
  match ev:
    case EvS{_, _, tfocus, _, _, writes, _, _, _}:
      Bool.and(tfocus, String.eq(concat_writes(writes), "xy"))

def w4_t19() -> Bool:
  w4_t19_ev(tick_ev_go(Con{Key{116, True{}}, Con{Key{120, True{}}, Con{Key{121, True{}}, Nil{}}}},
                      evst_new(0, w4_items(), False{}, w4_vs(), "", 0)))

# t20: full fold — PgUp on a focused terminal is swallowed (no writes) and
# keeps focus.
def w4_t20_ev(ev: EvSt) -> Bool:
  match ev:
    case EvS{_, _, tfocus, _, _, writes, _, _, _}:
      match writes:
        case TtyWNil{}: tfocus
        case _: False{}

def w4_t20() -> Bool:
  w4_t20_ev(tick_ev_go(Con{Key{63276, True{}}, Nil{}},
                       evst_new(0, w4_items(), True{}, w4_vs(), "", 0)))

def w4_line(+name: String, +ok: Bool) -> String:
  match ok:
    case True{}: String.append(String.append("PASS ", name), "\n")
    case False{}: String.append(String.append("FAIL ", name), "\n")

def w4_main() -> String:
  String.append(w4_line("t1 fresh offset 0", w4_t1()),
  String.append(w4_line("t2 30 lines -> 7 scrolled", w4_t2()),
  String.append(w4_line("t3 pgup clamps to 7", w4_t3()),
  String.append(w4_line("t4 pgup saturates", w4_t4()),
  String.append(w4_line("t5 pgdn returns live", w4_t5()),
  String.append(w4_line("t6 sb content a..g", w4_t6()),
  String.append(w4_line("t7 output auto-live", w4_t7()),
  String.append(w4_line("t8 empty write keeps view", w4_t8()),
  String.append(w4_line("t9 200-line cap", w4_t9()),
  String.append(w4_line("t10 sb_apply semantics", w4_t10()),
  String.append(w4_line("t11 sb_touched", w4_t11()),
  String.append(w4_line("t12 title [sb] marker", w4_t12()),
  String.append(w4_line("t13 pgup swallowed", w4_t13()),
  String.append(w4_line("t14 normal key writes+live", w4_t14()),
  String.append(w4_line("t15 esc unfocus+live", w4_t15()),
  String.append(w4_line("t16 grid top row h", w4_t16()),
  String.append(w4_line("t17 net up-heavy", w4_t17()),
  String.append(w4_line("t18 net down-heavy sat", w4_t18()),
  String.append(w4_line("t19 fold keys->writes", w4_t19()),
  String.append(w4_line("t20 fold pgup swallowed", w4_t20()), ""))))))))))))))))))))
