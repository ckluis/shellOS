# test_wave5_notes.bend — Wave 5 targeted tests: universal search covers
# saved-article note text. Concatenated AFTER app.bend (needs search_all,
# Item, theme_name). Run in the interpreter via a test bundle whose
# app.bend main is renamed (see build/wave5_test_run.sh).
#
# Fixture design: the distinctive word "zqxj" appears NOWHERE else —
# not in theme names (home design/gaming/Nov trip/saved/all), not in the
# four sample reader articles, not in terminal lines (Nil).

# ---- fixtures ----
def w5_items() -> List<&2, Item>:
  Con{It{"alpha", 0, "", 0n, ""},
  Con{It{"beta", 4, "my zqxj note", 1n, "u1"},
  Con{It{"gamma", 4, "zqxj", 2n, "u2"},
  Con{It{"zqxj title", 0, "", 0n, ""},
  Con{It{"delta", 4, "zqxj starts here", 3n, "u3"},
  Nil{}}}}}}

# A: title substring hit; B: note-only exact hit (strict-ordering probe).
def w5_items2() -> List<&2, Item>:
  Con{It{"has zqxj here", 0, "", 0n, ""},
  Con{It{"other", 4, "zqxj", 5n, "u9"},
  Nil{}}}

# Note-hit item listed FIRST; title-hit item second. If ordering were
# insertion-driven the note hit would win — the strict guarantee says
# the title hit (idx1) still comes first.
def w5_items_rev() -> List<&2, Item>:
  Con{It{"delta", 4, "zqxj starts here", 3n, "u3"},
  Con{It{"zqxj title", 0, "", 0n, ""},
  Nil{}}}

# Note-free corpus (byte-identical ranking probe). "zap" appears in no
# sample reader article and no theme name, so only item hits are expected.
def w5_plain() -> List<&2, Item>:
  Con{It{"zappy", 0, "", 0n, ""},
  Con{It{"zebra zap", 0, "", 0n, ""},
  Con{It{"zap", 0, "", 0n, ""},
  Nil{}}}}

# ---- observation helpers ----
def w5_hit_idx_str(+hit: SearchHit) -> String:
  match hit:
    case HItem{idx}: U32.show(idx)
    case HRead{a}: String.append("r", U32.show(a))
    case HTerm{l}: String.append("t", U32.show(l))

def w5_hits_idx_go(+hits: List<&2, SearchHit>, acc: String) -> String:
  match hits:
    case Nil{}: acc
    case h <> t: w5_hits_idx_go(t, String.append(acc, String.append(w5_hit_idx_str(h), ",")))

def w5_hits_idx(+hits: List<&2, SearchHit>) -> String:
  w5_hits_idx_go(hits, "")

def w5_search(+q: String, +items: List<&2, Item>) -> List<&2, SearchHit>:
  search_all(q, items, "", Nil{})

def w5_first_text(+hits: List<&2, SearchHit>, +items: List<&2, Item>) -> String:
  match hits:
    case Nil{}: ""
    case h <> _: search_hit_text(h, items, Nil{})

# ---- tests ----
# t1: note text found at all three ranks; title hit first; note block
# itself grouped exact > prefix > substring.
# q="zqxj": idx3 title-prefix (t2); idx2 note-exact (n3); idx4 note-prefix
# (n2); idx1 note-substring (n1); idx0 nothing.
def w5_t1() -> Bool:
  String.eq(w5_hits_idx(w5_search("zqxj", w5_items())), "3,2,4,1,")

# t2: strict guarantee is rank-driven, not insertion-order-driven: the
# note-hit item is listed FIRST yet the title hit (idx1) still wins.
def w5_t2() -> Bool:
  String.eq(w5_hits_idx(w5_search("zqxj", w5_items_rev())), "1,0,")

# t3: title SUBSTRING (band 1) still outranks note EXACT (note band 3).
def w5_t3() -> Bool:
  String.eq(w5_hits_idx(w5_search("zqxj", w5_items2())), "0,1,")

# t4: byte-identical ranking on note-free items.
# q="zap": "zappy all" prefix(2), "zap all" prefix(2), "zebra zap all"
# substring(1) -> [0, 2] then [1]. No reader/terminal hits ("zap" is
# absent from the sample articles and theme names).
def w5_t4() -> Bool:
  String.eq(w5_hits_idx(w5_search("zap", w5_plain())), "0,2,1,")

# t5: dedup — title-exact + note-exact on the same item -> exactly one hit.
def w5_t5() -> Bool:
  String.eq(w5_hits_idx(w5_search("zqxj", Con{It{"zqxj", 0, "zqxj", 9n, "u"}, Nil{}})), "0,")

# t6: note matching is case-insensitive.
def w5_t6() -> Bool:
  String.eq(w5_hits_idx(w5_search("zqxj", Con{It{"t", 4, "ZQXJ NOTE", 9n, "u"}, Nil{}})), "0,")

# t7: empty query -> no hits (existing behavior preserved).
def w5_t7() -> Bool:
  String.eq(w5_hits_idx(w5_search("", w5_items())), "")

# t8: note hit renders as "[item] <title>" and carries the item idx
# (Enter jumps to the item via the unchanged HItem path).
def w5_t8() -> Bool:
  String.eq(w5_first_text(w5_search("zqxj", Con{It{"gamma", 4, "zqxj", 2n, "u2"}, Nil{}}),
                          Con{It{"gamma", 4, "zqxj", 2n, "u2"}, Nil{}}), "[item] gamma")

# t9: no false positives — gibberish query matches nothing.
def w5_t9() -> Bool:
  String.eq(w5_hits_idx(w5_search("qqqzzz", w5_items())), "")

# t10: title+note both substring-match -> exactly one hit, at the title band.
def w5_t10() -> Bool:
  String.eq(w5_hits_idx(w5_search("zqxj", Con{It{"has zqxj inside", 0, "zqxj here", 9n, "u"}, Nil{}})), "0,")

# t11: theme-name title hit still outranks a note hit (theme is part of
# the title/theme corpus). q="saved": idx1 theme "saved" substring(1)
# beats idx2's note-only... (note has no "saved") -> only idx1 hits.
def w5_t11() -> Bool:
  String.eq(w5_hits_idx(w5_search("saved", w5_items())), "1,2,4,")

def w5_line(+name: String, +ok: Bool) -> String:
  match ok:
    case True{}: String.append(String.append("PASS ", name), "\n")
    case False{}: String.append(String.append("FAIL ", name), "\n")

def w5_main() -> String:
  String.append(w5_line("t1 note ranks 3/2/1 found, title first", w5_t1()),
  String.append(w5_line("t2 title wins regardless of item order", w5_t2()),
  String.append(w5_line("t3 title-substring outranks note-exact", w5_t3()),
  String.append(w5_line("t4 note-free ranking byte-identical", w5_t4()),
  String.append(w5_line("t5 dedup title+note same item", w5_t5()),
  String.append(w5_line("t6 note case-insensitive", w5_t6()),
  String.append(w5_line("t7 empty query no hits", w5_t7()),
  String.append(w5_line("t8 note hit renders [item] title", w5_t8()),
  String.append(w5_line("t9 no false positives", w5_t9()),
  String.append(w5_line("t10 title+note substring dedup", w5_t10()),
  String.append(w5_line("t11 theme hit is a title hit", w5_t11()), "")))))))))))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(w5_main())
