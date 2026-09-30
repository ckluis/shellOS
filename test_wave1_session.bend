# test_wave1_session.bend — Wave 1 session restore probes: pure round-trip,
# hostile-input, restore-helper, and change-detection tests.
# Concatenated AFTER app.bend in a scratch bundle whose app main is renamed
# (see build/wave1_test_run.sh); needs SessSt, sess_*, acc_*, term_* defs.
# Run with the pinned Bend 2.0.25 interpreter. Exit code = FAIL count.

# ---- fixtures ----

def w1_sess_full() -> SessSt:
  Sess{2, 37, True{}, "hello\nworld|pipe\\back=eq", 5, 3, 1, 2, 120, 0, "work", True{}, False{}}

def w1_vs_plain() -> ViewSt:
  VSt{0, False{}, 0, 0, Nil{}}

def w1_vs_rf() -> ViewSt:
  VSt{0, True{}, 0, 0, Nil{}}

def w1_acc_g() -> AccSt:
  Acc{"", False{}, 0, MOn{MUnknown{}}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", False{}, 0, 0}}

def w1_acc_a() -> AccSt:
  Acc{"", False{}, 0, MOff{}, AOn{AIUnknown{}}, NOff{}, False{}, False{}, None{}, Pal{"", False{}, 0, 0}}

def w1_acc_touched() -> AccSt:
  Acc{"", False{}, 0, MOff{}, AOff{}, NOff{}, False{}, True{}, None{}, Pal{"", False{}, 0, 0}}

def w1_sb_idle() -> SbSt:
  SbS{0, 0, False{}}

def w1_sb_live() -> SbSt:
  SbS{0, 0, True{}}

def w1_bool_eq(+a: Bool, +b: Bool) -> Bool:
  bool_not(sess_bool_xor(a, b))

# sess_serialize is canonical (fixed field order, every field present),
# so serialized-string equality is field equality.
def w1_sess_eq(+a: SessSt, +b: SessSt) -> Bool:
  String.eq(sess_serialize(a), sess_serialize(b))

def w1_long_go(+n: Nat, +acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+m: w1_long_go(m, String.append(acc, "x"))

def w1_long() -> String:
  w1_long_go(Nat.mul(10n, 100n), "")

def w1_nul_line() -> String:
  String.append("sess1\nsearch_q=a", String.append(Char.show(Chr{0}), "\n"))

# ---- round-trip ----

# t1: full round trip incl. v2_esc specials in search_q (\n, |, backslash, =)
def w1_t1() -> Bool:
  w1_sess_eq(sess_parse(sess_serialize(w1_sess_full())), w1_sess_full())

# t2: default session round-trips exactly
def w1_t2() -> Bool:
  w1_sess_eq(sess_parse(sess_serialize(sess_default())), sess_default())

# ---- hostile inputs: all parse to safe defaults, zero crashes ----

# t3: empty input -> default
def w1_t3() -> Bool:
  w1_sess_eq(sess_parse(""), sess_default())

# t4: garbage magic -> default
def w1_t4() -> Bool:
  w1_sess_eq(sess_parse("garbage bytes"), sess_default())

# t5: truncated mid-record -> parsed prefix kept, rest defaults
def w1_t5() -> Bool:
  Bool.and(U32.is_eq(sess_focus_of(sess_parse("sess1\nfocus=2\nsbo")), 2),
           U32.is_eq(sess_sbo_of(sess_parse("sess1\nfocus=2\nsbo")), 0))

# t6: NUL byte in a value is sanitized away, never reaches state
def w1_t6() -> Bool:
  String.eq(sess_search_q_of(sess_parse(w1_nul_line())), "a")

# t7: overlong value is capped (1000 x's -> 256)
def w1_t7() -> Bool:
  Nat.is_eq(String.length(sess_str_parse(w1_long(), 256n)), 256n)

# t8: unknown fields are ignored
def w1_t8() -> Bool:
  w1_sess_eq(sess_parse("sess1\nzzz=9\nsel=2\n"),
             Sess{0, 0, False{}, "", 0, 2, 0, 0, 0, 0, "default", False{}, False{}})

# t9: duplicate keys — last wins
def w1_t9() -> Bool:
  U32.is_eq(sess_sel_of(sess_parse("sess1\nsel=1\nsel=3\n")), 3)

# t10: wrong types poison to 0, never a partial prefix
def w1_t10() -> Bool:
  Bool.and(U32.is_eq(sess_focus_of(sess_parse("sess1\nfocus=abc\n")), 0),
  Bool.and(U32.is_eq(sess_focus_of(sess_parse("sess1\nfocus=12abc\n")), 0),
           U32.is_eq(sess_focus_of(sess_parse("sess1\nfocus=-5\n")), 0)))

# t11: bool is strict — only "1" is True
def w1_t11() -> Bool:
  Bool.and(w1_bool_eq(sess_search_open_of(sess_parse("sess1\nsearch_open=yes\n")), False{}),
  Bool.and(w1_bool_eq(sess_search_open_of(sess_parse("sess1\nsearch_open=1\n")), True{}),
           w1_bool_eq(sess_search_open_of(sess_parse("sess1\nsearch_open=0\n")), False{})))

# t12: huge number saturates at U32 max instead of wrapping
def w1_t12() -> Bool:
  U32.is_eq(sess_sbo_of(sess_parse("sess1\nsbo=99999999999999999999\n")), 4294967295)

# t13: out-of-range focus/sel clamp to 0
def w1_t13() -> Bool:
  Bool.and(U32.is_eq(sess_focus_of(sess_parse("sess1\nfocus=9\n")), 0),
           U32.is_eq(sess_sel_of(sess_parse("sess1\nsel=99\n")), 0))

# t14: CRLF-edited file parses (CR stripped incl. the magic line)
def w1_t14() -> Bool:
  Bool.and(U32.is_eq(sess_focus_of(sess_parse("sess1\r\nfocus=2\r\n")), 2),
           U32.is_eq(sess_sbo_of(sess_parse("sess1\r\nfocus=2\r\nsbo=7\r\n")), 7))

# t15: key without '=' -> empty value, ignored safely
def w1_t15() -> Bool:
  w1_sess_eq(sess_parse("sess1\nnosuchkey\n"), sess_default())

# t16: value containing '=' survives (split on FIRST '=' only)
def w1_t16() -> Bool:
  String.eq(sess_search_q_of(sess_parse("sess1\nsearch_q=a=b=c\n")), "a=b=c")

# t17: profile validated — unknown falls back to default, known kept
def w1_t17() -> Bool:
  Bool.and(String.eq(sess_profile_of(sess_parse("sess1\nprofile=evil\n")), "default"),
  Bool.and(String.eq(sess_profile_of(sess_parse("sess1\nprofile=work\n")), "work"),
           String.eq(sess_profile_of(sess_parse("sess1\nprofile=personal\n")), "personal")))

# ---- restore helpers ----

# t18: terminal-focus restore flag follows the focus encoding
def w1_t18() -> Bool:
  Bool.and(w1_bool_eq(sess_tfocus_restore(Sess{2, 0, False{}, "", 0, 0, 0, 0, 0, 0, "default", False{}, False{}}), True{}),
           w1_bool_eq(sess_tfocus_restore(Sess{1, 0, False{}, "", 0, 0, 0, 0, 0, 0, "default", False{}, False{}}), False{}))

# t19: sess_vs_restore clamps rart into the real article range
def w1_t19() -> Bool:
  U32.is_le(viewst_rart_of(sess_vs_restore(Sess{1, 0, False{}, "", 0, 0, 0, 999, 0, 0, "default", False{}, False{}}, "")),
             u32_sub_sat(reader_n_arts(), 1))

# t20: focus encoding priority: terminal > reader > gmail > ai > sidebar
def w1_t20() -> Bool:
  Bool.and(U32.is_eq(sess_focus_enc(True{}, w1_vs_rf(), w1_acc_g()), 2),
  Bool.and(U32.is_eq(sess_focus_enc(False{}, w1_vs_rf(), w1_acc_g()), 1),
  Bool.and(U32.is_eq(sess_focus_enc(False{}, w1_vs_plain(), w1_acc_g()), 3),
  Bool.and(U32.is_eq(sess_focus_enc(False{}, w1_vs_plain(), w1_acc_a()), 4),
           U32.is_eq(sess_focus_enc(False{}, w1_vs_plain(), acc_new()), 0)))))

# t21: sess_of extracts the tick surface faithfully
def w1_t21() -> Bool:
  w1_sess_eq(sess_of(False{}, w1_vs_plain(), Con{TTab{NoPty{}, term_new()}, Nil{}}, 0, 3, acc_new(), "work"),
             Sess{0, 0, False{}, "", 0, 3, 0, 0, 0, 0, "work", False{}, False{}})

# ---- change detection ----

# t22: identical old/new state -> no session write
def w1_t22() -> Bool:
  w1_bool_eq(sess_save_of(0, 0, False{}, False{}, w1_vs_plain(), w1_vs_plain(), 0, w1_sb_idle(), acc_new()), False{})

# t23: sel change, view change, scroll-request, terminal-changed each trigger
def w1_t23() -> Bool:
  Bool.and(w1_bool_eq(sess_save_of(0, 1, False{}, False{}, w1_vs_plain(), w1_vs_plain(), 0, w1_sb_idle(), acc_new()), True{}),
  Bool.and(w1_bool_eq(sess_save_of(0, 0, False{}, False{}, w1_vs_plain(), w1_vs_rf(), 0, w1_sb_idle(), acc_new()), True{}),
  Bool.and(w1_bool_eq(sess_save_of(0, 0, False{}, False{}, w1_vs_plain(), w1_vs_plain(), 0, w1_sb_live(), acc_new()), True{}),
           w1_bool_eq(sess_save_of(0, 0, False{}, False{}, w1_vs_plain(), w1_vs_plain(), 5, w1_sb_idle(), acc_new()), True{}))))

# t24: accretive-panel touch (accd) triggers a session save
def w1_t24() -> Bool:
  w1_bool_eq(sess_save_of(0, 0, False{}, False{}, w1_vs_plain(), w1_vs_plain(), 0, w1_sb_idle(), w1_acc_touched()), True{})

# ---- driver ----

def w1_line(+name: String, +ok: Bool) -> String:
  match ok:
    case True{}: String.append(String.append("PASS ", name), "\n")
    case False{}: String.append(String.append("FAIL ", name), "\n")

def w1_main() -> String:
  String.append(w1_line("t1 full round trip with v2_esc specials", w1_t1()),
  String.append(w1_line("t2 default session round-trips", w1_t2()),
  String.append(w1_line("t3 empty input -> default", w1_t3()),
  String.append(w1_line("t4 garbage magic -> default", w1_t4()),
  String.append(w1_line("t5 truncated mid-record keeps prefix", w1_t5()),
  String.append(w1_line("t6 NUL byte sanitized away", w1_t6()),
  String.append(w1_line("t7 overlong value capped at 256", w1_t7()),
  String.append(w1_line("t8 unknown fields ignored", w1_t8()),
  String.append(w1_line("t9 duplicate keys last wins", w1_t9()),
  String.append(w1_line("t10 wrong types poison to 0", w1_t10()),
  String.append(w1_line("t11 bool strict: only 1 is True", w1_t11()),
  String.append(w1_line("t12 huge number saturates U32 max", w1_t12()),
  String.append(w1_line("t13 out-of-range focus/sel clamp to 0", w1_t13()),
  String.append(w1_line("t14 CRLF file parses", w1_t14()),
  String.append(w1_line("t15 key without = ignored safely", w1_t15()),
  String.append(w1_line("t16 value with = survives", w1_t16()),
  String.append(w1_line("t17 profile validated, unknown -> default", w1_t17()),
  String.append(w1_line("t18 tfocus restore flag", w1_t18()),
  String.append(w1_line("t19 rart clamped to article range", w1_t19()),
  String.append(w1_line("t20 focus encoding priority", w1_t20()),
  String.append(w1_line("t21 sess_of extracts tick surface", w1_t21()),
  String.append(w1_line("t22 identical state -> no save", w1_t22()),
  String.append(w1_line("t23 sel/view/scroll/tchanged trigger", w1_t23()),
  String.append(w1_line("t24 accretive touch triggers save", w1_t24()),
  ""))))))))))))))))))))))))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(w1_main())
