# term.bend: ANSI/VT100 terminal emulator in pure Bend (subset).
# 80x24 grid, cursor movement, 16 colors, clear, scroll, wrap.

# 16 ANSI colors (0-7 normal, 8-15 bright)
def ansi_color(idx: U32) -> U32:
  match idx:
    case 0: rgb(21, 22, 30)       # black
    case 1: rgb(247, 118, 142)    # red
    case 2: rgb(158, 206, 106)    # green
    case 3: rgb(224, 175, 104)    # yellow
    case 4: rgb(122, 162, 247)    # blue
    case 5: rgb(187, 154, 247)    # magenta
    case 6: rgb(125, 207, 255)    # cyan
    case 7: rgb(192, 198, 214)    # white (default fg)
    case 8: rgb(77, 85, 105)      # bright black
    case 9: rgb(255, 137, 159)    # bright red
    case 10: rgb(185, 230, 136)   # bright green
    case 11: rgb(240, 200, 130)   # bright yellow
    case 12: rgb(150, 184, 255)   # bright blue
    case 13: rgb(206, 180, 255)   # bright magenta
    case 14: rgb(160, 222, 255)   # bright cyan
    case _: rgb(232, 236, 245)    # bright white

# Terminal state: grid of chars + colors, cursor pos, current fg/bg,
# plus a bounded scrollback buffer (sb): lines that scrolled off the top,
# oldest first, capped at 200 lines. sb is what universal search searches
# (there is no other record of scrolled-off output).
# sbo is the scrollback VIEWER offset (pure view state): how many lines the
# view is scrolled back from live; 0 = live. Clamped to [0, len(sb)].
# Any new PTY output (term_write / term_clear) resets it to 0 — the shell
# auto-returns to live rather than hiding fresh output.
type Term is Data:
  Tm{cells: List<&2, U32>, fg: U32, bg: U32, cx: U32, cy: U32, sb: List<&2, String>, sbo: U32}

# Scrollback cap: at most 200 scrolled-off lines are retained.
def term_sb_cap() -> U32:
  200

# 80x24 = 1920 cells. Each cell: char code in low 16 bits, fg in next 8, bg in next 8.
def term_blank(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: term_blank(m, Con{32, acc})  # space

def term_new() -> Term:
  Tm{term_blank(1920n, Nil{}), 7, 0, 0, 0, Nil{}, 0}

# List helpers (used by term_scroll).
def list_set(xs: List<&2, U32>, +idx: U32, +val: U32) -> List<&2, U32>:
  match xs, idx:
    case Nil{}, _: Nil{}
    case _ <> t, 0: Con{val, t}
    case h <> t, _:
      +idx2 = U32.sub(idx, 1)
      Con{h, list_set(t, idx2, val)}

def list_drop(xs: List<&2, U32>, n: Nat) -> List<&2, U32>:
  match xs, n:
    case _, 0n: xs
    case _ <> t, 1n+m: list_drop(t, m)
    case Nil{}, _: Nil{}

def list_append_u32(xs: List<&2, U32>, ys: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: ys
    case h <> t: Con{h, list_append_u32(t, ys)}

# Scrollback helpers. The top row's text is captured before it scrolls
# off; trailing spaces are trimmed so blank rows store as "" and can be
# skipped by search.
def list_take_u32(xs: List<&2, U32>, n: Nat) -> List<&2, U32>:
  match xs, n:
    case _, 0n: Nil{}
    case Nil{}, _: Nil{}
    case h <> t, 1n+m: Con{h, list_take_u32(t, m)}

def term_row_text_go(xs: List<&2, U32>, n: Nat, acc: String) -> String:
  match xs, n:
    case _, 0n: acc
    case Nil{}, _: acc
    case h <> t, 1n+m:
      term_row_text_go(t, m, String.append(acc, Char.show(Chr{U32.and(h, U32.mul(255, 257))})))

# Right-trim spaces: single recursive def (no mutual recursion). Walks the
# string keeping a pending-space count; spaces are only flushed when a
# non-space char follows, so trailing spaces are dropped.
def str_spaces(n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+m: String.append(" ", str_spaces(m))

def str_rtrim_go(s: String, pend: Nat, acc: String) -> String:
  match s:
    case SNil{}: acc
    case SCon{Chr{c}, rest}:
      match c:
        case 32: str_rtrim_go(rest, Nat.add(pend, 1n), acc)
        case _: str_rtrim_go(rest, 0n, String.append(String.append(acc, str_spaces(pend)), Char.show(Chr{c})))

def str_rtrim(s: String) -> String:
  str_rtrim_go(s, 0n, "")

def term_row_text(+cells: List<&2, U32>) -> String:
  str_rtrim(term_row_text_go(list_take_u32(cells, 80n), 80n, ""))

def sb_drop_head(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case _ <> t: t

# Shared string-list length (U32). Defined here (before shell.bend) because
# the scrollback cap check needs it; shell.bend's reader helpers reuse it.
def list_len_str(+xs: List<&2, String>) -> U32:
  match xs:
    case Nil{}: 0
    case _ <> t: U32.add(1, list_len_str(t))

# Push a scrolled-off line, keeping the buffer at the cap. Blank lines are
# not stored (they carry no searchable content).
def sb_single(+line: String) -> List<&2, String>:
  Con{line, Nil{}}

def sb_push_cap(+under: Bool, sb: List<&2, String>, +line: String) -> List<&2, String>:
  match under:
    case True{}: List.append(&2, String, sb, sb_single(line))
    case False{}: List.append(&2, String, sb_drop_head(sb), sb_single(line))

def sb_push_go(+blank: Bool, +sb: List<&2, String>, +line: String) -> List<&2, String>:
  match blank:
    case True{}: sb
    case False{}: sb_push_cap(U32.is_lt(list_len_str(sb), term_sb_cap()), sb, line)

def sb_push(+sb: List<&2, String>, +line: String) -> List<&2, String>:
  sb_push_go(String.eq(line, ""), sb, line)

def term_scroll(+t: Term) -> Term:
  match t:
    case Tm{cells, fg, bg, _, _, sb, _}:
      # drop first row (80 cells), append blank row; the dropped row's
      # text goes to scrollback before it is lost. New output scrolled:
      # the view returns to live (sbo = 0).
      +dropped = list_drop(cells, 80n)
      +blank = term_blank(80n, Nil{})
      +new_cells = list_append_u32(dropped, blank)
      +sb2 = sb_push(sb, term_row_text(cells))
      Tm{new_cells, fg, bg, 0, 23, sb2, 0}

# Cursor-advance helpers: split the wrap/scroll decisions so no match
# scrutinizes a computed Bool. (match t:) binders inherit +t's reusability.
def term_nl_go2(+cells: List<&2, U32>, +fg: U32, +bg: U32, +ncy: U32, +sb: List<&2, String>, +sbo: U32, fits: Bool) -> Term:
  match fits:
    case True{}: Tm{cells, fg, bg, 0, ncy, sb, sbo}
    case False{}: term_scroll(Tm{cells, fg, bg, 0, ncy, sb, sbo})

def term_nl_go(+cells: List<&2, U32>, +fg: U32, +bg: U32, +ncy: U32, +sb: List<&2, String>, +sbo: U32) -> Term:
  term_nl_go2(cells, fg, bg, ncy, sb, sbo, U32.is_lt(ncy, 24))

def term_put_go2(+cells: List<&2, U32>, +fg: U32, +bg: U32, +ncx: U32, +cy: U32, +sb: List<&2, String>, +sbo: U32, fits: Bool) -> Term:
  match fits:
    case True{}: Tm{cells, fg, bg, ncx, cy, sb, sbo}
    case False{}: term_nl_go(cells, fg, bg, U32.add(cy, 1), sb, sbo)

def term_put_go(+cells: List<&2, U32>, +fg: U32, +bg: U32, +ncx: U32, +cy: U32, +sb: List<&2, String>, +sbo: U32) -> Term:
  term_put_go2(cells, fg, bg, ncx, cy, sb, sbo, U32.is_lt(ncx, 80))

# Set cell at (x,y) to char with current colors.
def term_put(+t: Term, +ch: U32) -> Term:
  match t:
    case Tm{cells, fg, bg, cx, cy, sb, sbo}:
      +idx = U32.add(U32.mul(cy, 80), cx)
      +cell = U32.add(ch, U32.add(U32.mul(fg, 65536), U32.mul(bg, 16777216)))
      term_put_go(list_set(cells, idx, cell), fg, bg, U32.add(cx, 1), cy, sb, sbo)

# Handle newline.
def term_nl(+t: Term) -> Term:
  match t:
    case Tm{cells, fg, bg, _, cy, sb, sbo}:
      term_nl_go(cells, fg, bg, U32.add(cy, 1), sb, sbo)

# Set foreground color.
def term_fg(+t: Term, +c: U32) -> Term:
  match t:
    case Tm{cells, _, bg, cx, cy, sb, sbo}: Tm{cells, c, bg, cx, cy, sb, sbo}

# Clear screen.
# Clear screen. Scrollback is intentionally preserved: a cleared screen's
# scrolled-off content stays searchable. The view returns to live: a
# cleared grid under a scrolled-back view would show stale history above
# blank rows.
def term_clear(+t: Term) -> Term:
  match t:
    case Tm{_, fg, bg, _, _, sb, _}: Tm{term_blank(1920n, Nil{}), fg, bg, 0, 0, sb, 0}

# ---------- scrollback viewer: pure view-offset API ----------
# sbo = lines scrolled back from live (0 = live). All three transitions
# clamp: up saturates at len(sb) (oldest line), down saturates at 0 (live).

def u32_min_go(+le: Bool, +a: U32, +b: U32) -> U32:
  match le:
    case True{}: a
    case False{}: b

def u32_min(+a: U32, +b: U32) -> U32:
  u32_min_go(U32.is_le(a, b), a, b)

def nat_to_u32_go(n: Nat, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+m: nat_to_u32_go(m, U32.add(acc, 1))

def nat_to_u32(n: Nat) -> U32:
  nat_to_u32_go(n, 0)

# Clamped view offset: what the renderer actually uses.
def term_view_off(+t: Term) -> U32:
  match t:
    case Tm{_, _, _, _, _, sb, sbo}: u32_min(sbo, list_len_str(sb))

# Back to live (any other key, Esc, new output, clear).
def term_view_live(+t: Term) -> Term:
  match t:
    case Tm{cells, fg, bg, cx, cy, sb, _}: Tm{cells, fg, bg, cx, cy, sb, 0}

# PgUp: scroll back n lines, clamped at the oldest scrollback line.
def term_view_up(+t: Term, +n: U32) -> Term:
  match t:
    case Tm{cells, fg, bg, cx, cy, sb, sbo}:
      Tm{cells, fg, bg, cx, cy, sb, u32_min(U32.add(sbo, n), list_len_str(sb))}

# Saturating subtraction: a - b, floored at 0. (U32.sub wraps mod 2^32,
# so the naive form silently breaks when b > a.)
def u32_sub_sat_go(+lt: Bool, +a: U32, +b: U32) -> U32:
  match lt:
    case True{}: 0
    case False{}: U32.sub(a, b)

def u32_sub_sat(+a: U32, +b: U32) -> U32:
  u32_sub_sat_go(U32.is_lt(a, b), a, b)

# PgDn: scroll toward live n lines, saturating at 0.
def term_view_down(+t: Term, +n: U32) -> Term:
  match t:
    case Tm{cells, fg, bg, cx, cy, sb, sbo}: Tm{cells, fg, bg, cx, cy, sb, u32_sub_sat(sbo, n)}

# Net scroll for one tick: up and down requests cancel each other, the net
# lines move the view, saturating at both ends (0 = live, len(sb) =
# oldest scrollback line). live wins over up/down.
def sb_apply_net_go(+down_le_up: Bool, +up: U32, +down: U32, +t: Term) -> Term:
  match down_le_up:
    case True{}: term_view_up(t, U32.sub(up, down))
    case False{}: term_view_down(t, U32.sub(down, up))

def sb_apply_net(+up: U32, +down: U32, +t: Term) -> Term:
  sb_apply_net_go(U32.is_le(down, up), up, down, t)

# IO-pass application of one tick's accumulated scroll request
# (up/down line counts, live flag). live wins over up/down.
def sb_apply_go(+live: Bool, +up: U32, +down: U32, +t: Term) -> Term:
  match live:
    case True{}: term_view_live(t)
    case False{}: sb_apply_net(up, down, t)

def sb_apply(+up: U32, +down: U32, +live: Bool, +t: Term) -> Term:
  sb_apply_go(live, up, down, t)

# Write a string to the terminal. (s first: it is the shrinking argument.)
# Any non-empty write is new PTY output: the scrollback view auto-returns to
# live (sbo = 0) before the bytes land, so fresh output is never hidden
# behind a scrolled-back view.
def term_write_go(s: String, +t: Term) -> Term:
  match s:
    case SNil{}: t
    case SCon{Chr{c}, rest}:
      match c:
        case 10: term_write_go(rest, term_nl(t))  # newline
        case _: term_write_go(rest, term_put(t, c))

def term_write(s: String, +t: Term) -> Term:
  match s:
    case SNil{}: t
    case SCon{_, _}: term_write_go(s, term_view_live(t))

# Render terminal to image: 80x24 grid of 8x18 cells (8x16 glyph, 1px
# leading above and below) = 640x432. Background index 0 is the pane's own
# well (drawn by the caller) and space/NUL glyphs draw nothing, so blank
# cells cost almost nothing.
def term_cell_bg(+plain: Bool, +d: Nat, img: Image, +px: U32, +py: U32, +bgi: U32) -> Image:
  match plain:
    case True{}: img
    case False{}: fill_rect(d, img, px, py, 8, 18, ansi_color(bgi))

def term_cell_glyph(+blank: Bool, +d: Nat, img: Image, +px: U32, +py: U32, +ch: U32, +fgi: U32) -> Image:
  match blank:
    case True{}: img
    case False{}: blit_glyph(d, img, px, U32.add(py, 1), ch, ansi_color(fgi))

def draw_vp_cell(+d: Nat, +cell: U32, img: Image, +px: U32, +py: U32) -> Image:
  +ch = U32.and(cell, U32.mul(255, 257))  # low 16 bits
  +fgi = U32.and(U32.shrn(cell, 16n), 255)
  +bgi = U32.and(U32.shrn(cell, 24n), 255)
  +i1 = term_cell_bg(U32.is_eq(bgi, 0), d, img, px, py, bgi)
  term_cell_glyph(Bool.or(U32.is_eq(ch, 32), U32.is_eq(ch, 0)), d, i1, px, py, ch, fgi)

# Linear walk over the grid (row-major): cell idx lands at column idx%80,
# pixel row (idx/80 + shift). Stops after `last` cells.
def vp_cells_go(+cells: List<&2, U32>, +go: Bool, +d: Nat, img: Image, +ox: U32, +oy: U32, +idx: U32, +last: U32, +shift: U32) -> Image:
  match cells, go:
    case Nil{}, _: img
    case _, False{}: img
    case c <> rest, True{}:
      +px = U32.add(ox, U32.mul(U32.mod(idx, 80), 8))
      +py = U32.add(oy, U32.mul(U32.add(U32.div(idx, 80), shift), 18))
      +nx = U32.add(idx, 1)
      vp_cells_go(rest, U32.is_lt(nx, last), d, draw_vp_cell(d, c, img, px, py), ox, oy, nx, last, shift)

def term_render(+d: Nat, +t: Term, img: Image, +ox: U32, +oy: U32) -> Image:
  # Full-grid renderer (headless proof path): always the live grid, the
  # scrollback viewer offset applies to the app's viewport renderer below.
  match t:
    case Tm{cells, _, _, _, _, _, _}:
      vp_cells_go(cells, True{}, d, img, ox, oy, 0, 1920, 0)

def list_get(xs: List<&2, U32>, +idx: U32) -> U32:
  match xs, idx:
    case Nil{}, _: 0
    case h <> _, 0: h
    case _ <> t, i: list_get(t, U32.sub(i, 1))

# ---------- scrollback-aware viewport rendering ----------
# String-list index (out of range -> "", defensive; callers clamp).
def sb_get(+xs: List<&2, String>, +idx: U32) -> String:
  match xs, idx:
    case Nil{}, _: ""
    case h <> _, 0: h
    case _ <> t, i: sb_get(t, U32.sub(i, 1))

# Draw `rem` scrollback text rows: sb[si .. si+rem-1] at pixel rows
# pr .. pr+rem-1 (18px each).
def vp_sb_rows_go(rem: Nat, +d: Nat, +sb: List<&2, String>, +si: U32, img: Image, +ox: U32, +oy: U32, +pr: U32) -> Image:
  match rem:
    case 0n: img
    case 1n+m:
      vp_sb_rows_go(m, d, sb, U32.add(si, 1),
        draw_text_go(sb_get(sb, si), d, img, ox, U32.add(U32.add(oy, U32.mul(pr, 18)), 1), ansi_color(7)),
        ox, oy, U32.add(pr, 1))

def term_render_vp(+d: Nat, +t: Term, img: Image, +ox: U32, +oy: U32, +cols: Nat, +rows: Nat) -> Image:
  # Scrollback-aware viewport: the top min(off, rows) rows draw scrollback
  # text (oldest first), the remaining rows draw the live grid shifted down.
  # off = 0 renders exactly the live view. cols is always the full 80.
  match t:
    case Tm{cells, _, _, _, _, sb, sbo}:
      +sblen = list_len_str(sb)
      +off = u32_min(sbo, sblen)
      +sbn = u32_min(off, nat_to_u32(rows))
      +img2 = vp_sb_rows_go(U32.to_nat(sbn), d, sb, U32.sub(sblen, off), img, ox, oy, 0)
      +last = U32.mul(U32.sub(nat_to_u32(rows), sbn), 80)
      vp_cells_go(cells, U32.is_lt(0, last), d, img2, ox, oy, 0, last, sbn)

# Append a line (text + newline) to the terminal.
def nl_str() -> String:
  Char.show(Chr{10})

def term_line(s: String, +t: Term) -> Term:
  term_write(String.append(s, nl_str()), t)

# ---------- terminal text lines (for universal search) ----------
# Visible grid rows as text (24 rows); all lines = scrollback ++ visible.
# Blank rows decode as "" — the search layer skips them.
# (n first: the termination checker requires the shrinking arg leftmost.)
def term_vis_go(n: Nat, +cells: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+m:
      term_vis_go(m, list_drop(cells, 80n), List.append(&2, String, acc, Con{term_row_text(cells), Nil{}}))

def term_all_lines(+t: Term) -> List<&2, String>:
  match t:
    case Tm{cells, _, _, _, _, sb, _}: List.append(&2, String, sb, term_vis_go(24n, cells, Nil{}))
