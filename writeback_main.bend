# writeback_main.bend — E2E verification of item write-back (backlog item 2).
# Concatenated AFTER font.bend img.bend ui.bend reader.bend term.bend
# shell.bend. (app.bend NOT included: this test exercises save_items /
# load_items only, not the interactive loop.)
#
# Build:
#   cat font.bend img.bend ui.bend reader.bend term.bend shell.bend \
#       writeback_main.bend > build/writeback_all.bend
#   bend build/writeback_all.bend --check-only
#   bend build/writeback_all.bend -o build/writeback_all.js
# Run (in a scratch dir so items.txt/items.txt.tmp never touch the real one):
#   mkdir -p /tmp/writeback_test && cd /tmp/writeback_test \
#       && bun ~/workspace/apps/shell-os/pure/build/writeback_all.js
#
# Verifies:
#   1. serialize_items produces exact "theme|title\n" lines (pure)
#   2. save_items returns True and leaves no items.txt.tmp behind
#      (atomic tmp + rename path)
#   3. load_items reloads the identical list (round-trip)
#   4. A second mutated save round-trips (the edit/delete write path)
#   5. Missing-file fallback already covered by parse_items_fallback.
#
# PIPE-IN-TITLE FIX (landed 2026-09-21, HARDEN): parse_item_line used to
# split on every '|' and keep only the first title segment, so a title
# containing '|' silently lost its '|...' suffix on reload. Fixed by
# REJOINING the tail segments with "|" in parse_item_rest (shell.bend):
# the single-digit theme stays the head, the whole rest is the title, so
# pipe titles round-trip byte-exact. '\n' in titles is supported since
# 2026-09-21 via backslash escaping (str_escape/str_unescape in shell.bend):
# '\' -> "\\", LF -> "\n". Exercised below by the pipe-* and escape-* checks.

def wb_items_pipe() -> List<&2, Item>:
  Con{It{"a|b|c", 1}, Con{It{"plain", 2}, Nil{}}}

# Titles stressing the escape scheme: embedded LF, embedded backslash,
# trailing backslash, and a literal "\n" two-char sequence (must NOT
# become a real LF on round-trip).
def wb_items_escape() -> List<&2, Item>:
  Con{It{"line1\nline2", 0},
  Con{It{"back\\slash", 1},
  Con{It{"trail\\", 2},
  Con{It{"lit\\nseq", 3}, Nil{}}}}}

def wb_bshow(b: Bool) -> String:
  match b:
    case True{}: "T"
    case False{}: "F"

def wb_char_code(c: Char) -> U32:
  match c:
    case Chr{n}: n

def wb_bool_nat(b: Bool) -> Nat:
  match b:
    case True{}: 1n
    case False{}: 0n

def wb_none_nat(mc: Maybe<&2, Char>) -> Nat:
  match mc:
    case None{}: 1n
    case Some{c}: 0n

def wb_some_eq_nat(mc: Maybe<&2, Char>, c1: Char) -> Nat:
  match mc:
    case None{}: 0n
    case Some{c2}: wb_bool_nat(U32.is_eq(wb_char_code(c1), wb_char_code(c2)))

def wb_maybe_char_eq_nat(mc1: Maybe<&2, Char>, mc2: Maybe<&2, Char>) -> Nat:
  match mc1:
    case None{}: wb_none_nat(mc2)
    case Some{c1}: wb_some_eq_nat(mc2, c1)

def wb_str_eq_go(n: Nat, +a: String, +b: String, +i: Nat, acc: Nat, mc1: Maybe<&2, Char>, mc2: Maybe<&2, Char>) -> Nat:
  match n:
    case 0n: Nat.mul(acc, wb_none_nat(mc2))
    case 1n+m: wb_str_eq_go(m, a, b, Nat.add(i, 1n), Nat.mul(acc, wb_maybe_char_eq_nat(mc1, mc2)), String.get(a, Nat.add(i, 1n)), String.get(b, Nat.add(i, 1n)))

def wb_str_eq_nat(n: Nat) -> Bool:
  match n:
    case 0n: False{}
    case 1n+m: True{}

def wb_str_eq(+a: String, +b: String) -> Bool:
  wb_str_eq_nat(wb_str_eq_go(String.length(a), a, b, 0n, 1n, String.get(a, 0n), String.get(b, 0n)))

def wb_line(name: String, ok: Bool) -> String:
  match ok:
    case True{}: String.append(String.append("PASS ", name), nl_str())
    case False{}: String.append(String.append("FAIL ", name), nl_str())

def wb_items1() -> List<&2, Item>:
  Con{It{"alpha", 0}, Con{It{"beta", 2}, Con{It{"gamma", 3}, Nil{}}}}

def wb_items2() -> List<&2, Item>:
  Con{It{"alpha EDITED", 0}, Con{It{"gamma", 3}, Nil{}}}

# items.txt.tmp must be ABSENT after save_items (it was renamed over
# items.txt). If the open succeeds, the rename did not happen: FAIL.
def wb_tmp_absent_named(name: String, r: Result<&1,&1, U32 & String, File>) -> IO(Unit):
  match r:
    case Fail{e}: IO.print(wb_line(name, True{}))
    case Done{f}:
      do IO<Unit>:
        _u : Unit <- File.close(f)
        IO.print(wb_line(name, False{}))

def wb_tmp_absent(r: Result<&1,&1, U32 & String, File>) -> IO(Unit):
  wb_tmp_absent_named("tmp-absent-after-rename", r)

def main() -> IO(Unit):
  do IO<Unit>:
    +s1 : String = serialize_items(wb_items1())
    _a : Unit <- IO.print(wb_line("serialize-exact", wb_str_eq(s1, "0|alpha\n2|beta\n3|gamma\n")))
    ok1 : Bool <- save_items(wb_items1())
    _b : Unit <- IO.print(wb_line("save-returns-true", ok1))
    tmp_r : Result<&1,&1, U32 & String, File> <- File.open("items.txt.tmp", "r")
    _c : Unit <- wb_tmp_absent(tmp_r)
    +items1b : List<&2, Item> <- load_items()
    _d : Unit <- IO.print(wb_line("roundtrip-identical", wb_str_eq(serialize_items(items1b), s1)))
    ok2 : Bool <- save_items(wb_items2())
    _e : Unit <- IO.print(wb_line("resave-returns-true", ok2))
    +items2b : List<&2, Item> <- load_items()
    +s2 : String = serialize_items(wb_items2())
    _f : Unit <- IO.print(wb_line("resave-roundtrip-identical", wb_str_eq(serialize_items(items2b), s2)))
    +sp : String = serialize_items(wb_items_pipe())
    _g : Unit <- IO.print(wb_line("pipe-serialize-exact", wb_str_eq(sp, "1|a|b|c\n2|plain\n")))
    ok3 : Bool <- save_items(wb_items_pipe())
    _h : Unit <- IO.print(wb_line("pipe-save-returns-true", ok3))
    +items_pb : List<&2, Item> <- load_items()
    _i : Unit <- IO.print(wb_line("pipe-roundtrip-identical", wb_str_eq(serialize_items(items_pb), sp)))
    +se : String = serialize_items(wb_items_escape())
    _j : Unit <- IO.print(wb_line("escape-serialize-exact", wb_str_eq(se, "0|line1\\nline2\n1|back\\\\slash\n2|trail\\\\\n3|lit\\\\nseq\n")))
    ok4 : Bool <- save_items(wb_items_escape())
    _k : Unit <- IO.print(wb_line("escape-save-true", ok4))
    tmp_r2 : Result<&1,&1, U32 & String, File> <- File.open("items.txt.tmp", "r")
    _l : Unit <- wb_tmp_absent_named("escape-tmp-absent", tmp_r2)
    +items_eb : List<&2, Item> <- load_items()
    _m : Unit <- IO.print(wb_line("escape-roundtrip-identical", wb_str_eq(serialize_items(items_eb), se)))
    IO.print(wb_line("writeback-suite-done", True{}))
