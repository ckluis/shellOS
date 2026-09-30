# ---------- universal search (accretive #1) ----------
# Pure-Bend search over three corpora: item titles (+theme names),
# reader article texts (all articles, via reader_lines), and terminal
# scrollback + visible lines (via term_all_lines). Ranking: exact (3) >
# prefix (2) > substring (1), case-insensitive. Results are grouped by
# rank (stable within a rank: items, then reader, then terminal).
# Wave 5: saved-article note text is a lower-priority signal within the
# item corpus — note hits (HItem) are appended AFTER the full title/theme
# + reader + terminal ranking, rank-grouped 3 > 2 > 1 among themselves,
# so a note hit can never outrank a title/theme hit for the same query.

type SearchHit is Data:
  HItem{idx: U32}    # item index into the full items list
  HRead{a: U32}      # reader article index
  HTerm{l: U32}      # terminal line index into term_all_lines

# ---------- case-insensitive string helpers ----------

def str_lower_c_go(+upper: Bool, +c: U32) -> U32:
  match upper:
    case True{}: U32.add(c, 32)
    case False{}: c

def str_lower_c(+c: U32) -> U32:
  str_lower_c_go(Bool.and(U32.is_le(65, c), U32.is_le(c, 90)), c)

def str_lower_go(s: String, acc: String) -> String:
  match s:
    case SNil{}: acc
    case SCon{Chr{c}, t}:
      str_lower_go(t, String.append(acc, Char.show(Chr{str_lower_c(c)})))

def str_lower(+s: String) -> String:
  str_lower_go(s, "")

# starts_with, via a char-level walk (no string rebuilding).
def str_take_go(s: String, n: Nat, acc: String) -> String:
  match s, n:
    case _, 0n: acc
    case SNil{}, _: acc
    case SCon{Chr{c}, t}, 1n+m: str_take_go(t, m, String.append(acc, Char.show(Chr{c})))

def str_take(+s: String, n: Nat) -> String:
  str_take_go(s, n, "")

# ---------- ranking ----------

# 3 = exact, 2 = prefix, 1 = substring, 0 = no match. Case-insensitive.
def match_rank_sub(+sub: Bool, +q: String, +t: String) -> U32:
  match sub:
    case True{}: 1
    case False{}: 0

def match_rank_is(+r: U32, +want: U32) -> Bool:
  U32.is_eq(r, want)

# ---------- corpus collectors ----------
# Each collector appends hits of exactly rank `want`, in source order.

def search_item_text(+it: Item) -> String:
  match it:
    case It{title, theme, _, _, _}: String.append(title, String.append(" ", theme_name(theme)))

def search_hit_pick(+hit: Bool, +h: SearchHit, acc: List<&2, SearchHit>) -> List<&2, SearchHit>:
  match hit:
    case True{}: List.append(&2, SearchHit, acc, Con{h, Nil{}})
    case False{}: acc

def search_items_hit(+r: U32, +want: U32, +idx: U32, acc: List<&2, SearchHit>) -> List<&2, SearchHit>:
  search_hit_pick(match_rank_is(r, want), HItem{idx}, acc)

def u32_max_go(+le: Bool, +a: U32, +b: U32) -> U32:
  match le:
    case True{}: b
    case False{}: a

def u32_max(+a: U32, +b: U32) -> U32:
  u32_max_go(U32.is_le(a, b), a, b)

def search_reader_hit(+r: U32, +want: U32, +a: U32, acc: List<&2, SearchHit>) -> List<&2, SearchHit>:
  search_hit_pick(match_rank_is(r, want), HRead{a}, acc)

def search_term_hit(+r: U32, +want: U32, +l: U32, +blank: Bool, acc: List<&2, SearchHit>) -> List<&2, SearchHit>:
  match blank:
    case True{}: acc
    case False{}: search_hit_pick(match_rank_is(r, want), HTerm{l}, acc)

def search_hit_count(+hits: List<&2, SearchHit>) -> U32:
  match hits:
    case Nil{}: 0
    case _ <> t: U32.add(1, search_hit_count(t))

def search_hit_at(+hits: List<&2, SearchHit>, +idx: U32) -> Maybe<&2, SearchHit>:
  match hits, idx:
    case Nil{}, _: None{}
    case h <> _, 0: Some{h}
    case _ <> t, _: search_hit_at(t, U32.sub(idx, 1))

# Display text for a hit.
def list_get_str(+xs: List<&2, String>, +idx: U32) -> String:
  match xs, idx:
    case Nil{}, _: ""
    case h <> _, 0: h
    case _ <> t, _: list_get_str(t, U32.sub(idx, 1))

# ---------- search overlay rendering ----------
# Panel (192,224,640,480): header, up to 12 ranked hits, footer hints.
def search_item_title(+items: List<&2, Item>, idx: U32) -> String:
  match items, idx:
    case Nil{}, _: ""
    case It{title, _, _, _, _} <> _, 0: title
    case _ <> t, i: search_item_title(t, U32.sub(i, 1))

def search_hit_text(+hit: SearchHit, +items: List<&2, Item>, +termlines: List<&2, String>) -> String:
  match hit:
    case HItem{idx}: String.append("[item] ", search_item_title(items, idx))
    case HRead{a}: String.append("[read] ", reader_art_title(a))
    case HTerm{l}: String.append("[term] ", str_take(list_get_str(termlines, l), 44n))

def search_row_mark(+is_cur: Bool) -> String:
  match is_cur:
    case True{}: "> "
    case False{}: "  "

def search_row_color(+is_cur: Bool, +accent: U32, +text: U32) -> U32:
  match is_cur:
    case True{}: accent
    case False{}: text

# Card geometry matches app.bend's palette card: rows 26px from y 198.
def search_row_bg(+on: Bool, +d: Nat, img: Image, +y: U32) -> Image:
  match on:
    case False{}: img
    case True{}:
      +i1 = fill_rect(d, img, 213, y, 598, 24, col_selbg())
      fill_rect(d, i1, 213, y, 2, 24, col_accent())

def search_overlay_row_text(img: Image, +d: Nat, +hit: SearchHit, +cur: U32, +row: U32, +items: List<&2, Item>, +termlines: List<&2, String>, +accent: U32, +text: U32) -> Image:
  +on = U32.is_eq(cur, row)
  +y = U32.add(198, U32.mul(row, 26))
  +i1 = search_row_bg(on, d, img, y)
  draw_text(ui_fit(search_hit_text(hit, items, termlines), 94n), d, i1, 228, U32.add(y, 6), ui_pick(on, col_text(), col_body()))

def search_overlay_row_draw(img: Image, +hit: SearchHit, +d: Nat, +th: Theme, +cur: U32, +row: U32, +items: List<&2, Item>, +termlines: List<&2, String>) -> Image:
  match th:
    case T{_, _, accent, text, dim}:
      search_overlay_row_text(img, d, hit, cur, row, items, termlines, accent, text)

def search_overlay_text(img: Image, +d: Nat, +s: String, +x: U32, +y: U32, +c: U32) -> Image:
  draw_text(s, d, img, x, y, c)

def search_header_str(+n: U32, +empty: Bool) -> String:
  match empty:
    case True{}: "SEARCH — type to search items, articles, terminal"
    case False{}: String.append("SEARCH — ", String.append(U32.show(n), " matches (up/down, enter, esc)"))

def search_overlay_header(+d: Nat, img: Image, +th: Theme, +n: U32, +empty: Bool) -> Image:
  match th:
    case T{_, _, _, text, dim}:
      search_overlay_text(img, d, search_header_str(n, empty), 224, 248, text)

def match_rank_pre(+pre: Bool, +q: String, +t: String) -> U32:
  match pre:
    case True{}: 2
    case False{}: match_rank_sub(String.contains(t, q), q, t)

def match_rank_eq(+eq: Bool, +q: String, +t: String) -> U32:
  match eq:
    case True{}: 3
    case False{}: match_rank_pre(String.starts_with(t, q), q, t)

def match_rank_go(+q: String, +t: String) -> U32:
  match_rank_eq(String.eq(q, t), q, t)

def match_rank(+query: String, +text: String) -> U32:
  match_rank_go(str_lower(query), str_lower(text))

def search_items_go(+items: List<&2, Item>, +q: String, +idx: U32, +want: U32, acc: List<&2, SearchHit>) -> List<&2, SearchHit>:
  match items:
    case Nil{}: acc
    case it <> rest:
      search_items_go(rest, q, U32.add(idx, 1), want,
        search_items_hit(match_rank(q, search_item_text(it)), want, idx, acc))

def search_items(+items: List<&2, Item>, +q: String, +want: U32) -> List<&2, SearchHit>:
  search_items_go(items, q, 0, want, Nil{})

# ---------- Wave 5: saved-note sub-corpus ----------
# Note text (saved-article annotations) is searchable as a lower-priority
# signal within the item corpus. An item emits a note hit only when it has
# NO title/theme match for the query (dedup: the title/theme hit already
# surfaces the item). Note hits are appended after the full existing
# ranking (see search_all_go), grouped 3 > 2 > 1 among themselves. Empty
# notes rank 0 and contribute nothing.

def search_item_note_text(+it: Item) -> String:
  match it:
    case It{_, _, note, _, _}: note

def search_note_hit_go(+title_rank0: Bool, +r: U32, +want: U32, +idx: U32, acc: List<&2, SearchHit>) -> List<&2, SearchHit>:
  match title_rank0:
    case True{}: search_hit_pick(match_rank_is(r, want), HItem{idx}, acc)
    case False{}: acc

def search_note_hit2(+it: Item, +q: String, +want: U32, +idx: U32, acc: List<&2, SearchHit>) -> List<&2, SearchHit>:
  search_note_hit_go(U32.is_eq(match_rank(q, search_item_text(it)), 0),
    match_rank(q, search_item_note_text(it)), want, idx, acc)

def search_note_items_go(+items: List<&2, Item>, +q: String, +idx: U32, +want: U32, acc: List<&2, SearchHit>) -> List<&2, SearchHit>:
  match items:
    case Nil{}: acc
    case it <> rest:
      search_note_items_go(rest, q, U32.add(idx, 1), want,
        search_note_hit2(it, q, want, idx, acc))

def search_notes(+items: List<&2, Item>, +q: String, +want: U32) -> List<&2, SearchHit>:
  search_note_items_go(items, q, 0, want, Nil{})

def search_notes_ranked(+q: String, +items: List<&2, Item>) -> List<&2, SearchHit>:
  List.append(&2, SearchHit, search_notes(items, q, 3),
    List.append(&2, SearchHit, search_notes(items, q, 2),
      search_notes(items, q, 1)))

# Reader: one hit per article, ranked by the best rank of title/lines.
def search_reader_line_rank(+lines: List<&2, String>, +q: String, best: U32) -> U32:
  match lines:
    case Nil{}: best
    case l <> rest:
      search_reader_line_rank(rest, q, u32_max(best, match_rank(q, l)))

def search_term_go(+lines: List<&2, String>, +q: String, +l: U32, +want: U32, acc: List<&2, SearchHit>) -> List<&2, SearchHit>:
  match lines:
    case Nil{}: acc
    case ln <> rest:
      search_term_go(rest, q, U32.add(l, 1), want,
        search_term_hit(match_rank(q, ln), want, l, String.eq(ln, ""), acc))

def search_term(+lines: List<&2, String>, +q: String, +want: U32) -> List<&2, SearchHit>:
  search_term_go(lines, q, 0, want, Nil{})

# Rank-grouped: exact, then prefix, then substring.
def search_reader_go(n: Nat, +a: U32, +q: String, +feed: String, +want: U32, acc: List<&2, SearchHit>) -> List<&2, SearchHit>:
  match n:
    case 0n: acc
    case 1n+m:
      search_reader_go(m, U32.add(a, 1), q, feed, want,
        search_reader_hit(search_reader_line_rank(reader_lines(a, feed), q, match_rank(q, reader_art_title(a))), want, a, acc))

def search_reader(+q: String, +feed: String, +want: U32) -> List<&2, SearchHit>:
  search_reader_go(U32.to_nat(reader_n_arts()), 0, q, feed, want, Nil{})

# Terminal: one hit per matching line (blank lines skipped).
def search_ranked_go(+q: String, +items: List<&2, Item>, +feed: String, +termlines: List<&2, String>, +want: U32) -> List<&2, SearchHit>:
  List.append(&2, SearchHit, search_items(items, q, want),
    List.append(&2, SearchHit, search_reader(q, feed, want), search_term(termlines, q, want)))

def search_all_go(+empty: Bool, +q: String, +items: List<&2, Item>, +feed: String, +termlines: List<&2, String>) -> List<&2, SearchHit>:
  match empty:
    case True{}: Nil{}
    case False{}:
      List.append(&2, SearchHit, search_ranked_go(q, items, feed, termlines, 3),
        List.append(&2, SearchHit, search_ranked_go(q, items, feed, termlines, 2),
          List.append(&2, SearchHit, search_ranked_go(q, items, feed, termlines, 1),
            search_notes_ranked(q, items))))

def search_all(+q: String, +items: List<&2, Item>, +feed: String, +termlines: List<&2, String>) -> List<&2, SearchHit>:
  search_all_go(String.eq(q, ""), q, items, feed, termlines)

def search_overlay_rows_go(+hits: List<&2, SearchHit>, +d: Nat, img: Image, +th: Theme, +cur: U32, +row: U32, +items: List<&2, Item>, +termlines: List<&2, String>) -> Image:
  match hits:
    case Nil{}: img
    case h <> t:
      search_overlay_rows_go(t, d, search_overlay_row_draw(img, h, d, th, cur, row, items, termlines), th, cur, U32.add(row, 1), items, termlines)


def search_overlay_rows(+hits: List<&2, SearchHit>, +d: Nat, img: Image, +th: Theme, +cur: U32, +row: U32, +items: List<&2, Item>, +termlines: List<&2, String>) -> Image:
  search_overlay_rows_go(List.take(&2, SearchHit, hits, 12n), d, img, th, cur, row, items, termlines)

def bool_not_s(+b: Bool) -> Bool:
  match b:
    case True{}: False{}
    case False{}: True{}

def search_rows_vis(+n: U32) -> U32:
  match n:
    case 0: 1
    case _: u32_min(n, 12)

def search_input(+empty: Bool, +d: Nat, img: Image, +q: String) -> Image:
  match empty:
    case True{}:
      +i1 = fill_rect(d, img, 244, 164, 6, 12, col_accent())
      draw_text("items, articles, notes, terminal", d, i1, 258, 164, col_faint())
    case False{}:
      +i1 = draw_text(ui_fit(q, 80n), d, img, 244, 164, col_text())
      fill_rect(d, i1, U32.add(245, text_width(ui_fit(q, 80n))), 164, 6, 12, col_accent())

def search_count_str(+n: U32) -> String:
  match n:
    case 1: "1 match"
    case _: String.append(U32.show(n), " matches")

def search_empty(+show: Bool, +d: Nat, img: Image) -> Image:
  match show:
    case False{}: img
    case True{}: draw_text("No matches.", d, img, 228, 204, col_faint())

def draw_search_overlay(+d: Nat, img: Image, +th: Theme, +hits: List<&2, SearchHit>, +cur: U32, +q: String, +items: List<&2, Item>, +termlines: List<&2, String>) -> Image:
  +n = search_hit_count(hits)
  +h = U32.add(96, U32.mul(search_rows_vis(n), 26))
  +p = ui_panel(d, img, rect(212, 150, 600, h), th)
  +p1 = draw_text("/", d, p, 228, 164, col_accent())
  +p2 = search_input(String.eq(q, ""), d, p1, q)
  +p3 = ui_text_right(search_count_str(n), d, p2, 796, 164, col_faint())
  +p4 = fill_rect(d, p3, 213, 190, 598, 1, col_line())
  +p5 = search_overlay_rows(hits, d, p4, th, cur, 0, items, termlines)
  +p6 = search_empty(Bool.and(U32.is_eq(n, 0), bool_not_s(String.eq(q, ""))), d, p5)
  +fy = U32.add(150, U32.sub(h, 26))
  +p7 = fill_rect(d, p6, 213, U32.sub(fy, 10), 598, 1, col_line())
  +p8 = draw_text(String.append(sym_up(), sym_down()), d, p7, 228, fy, col_accent())
  +p9 = draw_text("move", d, p8, 246, fy, col_sub())
  +p10 = draw_text("enter", d, p9, 288, fy, col_accent())
  +p11 = draw_text("open", d, p10, 324, fy, col_sub())
  +p12 = draw_text("esc", d, p11, 360, fy, col_accent())
  draw_text("close", d, p12, 384, fy, col_sub())

