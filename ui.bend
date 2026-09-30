# muibend: minimal immediate-mode UI toolkit in pure Bend.
# Rect math, row/column layout, clip stack, labels, buttons, panels.
# State (hot/active/focus) driven by Event values.

# ---------- Rect ----------
type Rect is Data:
  R{x: U32, y: U32, w: U32, h: U32}

def rect(x: U32, y: U32, w: U32, h: U32) -> Rect:
  R{x, y, w, h}

def rect_x(+r: Rect) -> U32:
  match r:
    case R{x, _, _, _}: x

def rect_y(+r: Rect) -> U32:
  match r:
    case R{_, y, _, _}: y

def rect_w(+r: Rect) -> U32:
  match r:
    case R{_, _, w, _}: w

def rect_h(+r: Rect) -> U32:
  match r:
    case R{_, _, _, h}: h

# Shrink rect by padding on all sides.
def rect_pad(+r: Rect, +pad: U32) -> Rect:
  match r:
    case R{x, y, w, h}:
      R{U32.add(x, pad), U32.add(y, pad), U32.sub(w, U32.mul(pad, 2)), U32.sub(h, U32.mul(pad, 2))}

# Split rect horizontally: top h_px, bottom rest.
def rect_split_top(+r: Rect, +h_px: U32) -> Rect & Rect:
  match r:
    case R{x, y, w, h}:
      (R{x, y, w, h_px}, R{x, U32.add(y, h_px), w, U32.sub(h, h_px)})

# Split rect vertically: left w_px, right rest.
def rect_split_left(+r: Rect, +w_px: U32) -> Rect & Rect:
  match r:
    case R{x, y, w, h}:
      (R{x, y, w_px, h}, R{U32.add(x, w_px), y, U32.sub(w, w_px), h})

# ---------- Colors (theme) ----------
# Design tokens: design/mockup.html, variant A ("Panes"). Theme keeps its
# five positional fields for existing callers (bg, panel, accent, text,
# dim); every other token is a plain function.
type Theme is Data:
  T{bg: U32, panel: U32, accent: U32, text: U32, dim: U32}

def theme_dark() -> Theme:
  T{rgb(15, 17, 23), rgb(21, 25, 35), rgb(122, 162, 247), rgb(213, 217, 227), rgb(138, 147, 168)}

def col_bg() -> U32: rgb(15, 17, 23)
def col_bar() -> U32: rgb(10, 11, 15)
def col_raised() -> U32: rgb(21, 25, 35)
def col_line() -> U32: rgb(38, 44, 58)
def col_accent() -> U32: rgb(122, 162, 247)
def col_text() -> U32: rgb(213, 217, 227)
def col_body() -> U32: rgb(180, 187, 202)
def col_sub() -> U32: rgb(138, 147, 168)
def col_faint() -> U32: rgb(77, 85, 105)
def col_selbg() -> U32: rgb(26, 33, 48)
def col_keycap() -> U32: rgb(27, 32, 43)
def col_keycap_on() -> U32: rgb(37, 48, 73)
def col_shadow() -> U32: rgb(5, 6, 8)
def col_term_bg() -> U32: rgb(11, 13, 18)
def col_green() -> U32: rgb(158, 206, 106)
def col_purple() -> U32: rgb(187, 154, 247)
def col_amber() -> U32: rgb(224, 175, 104)
def col_cyan() -> U32: rgb(125, 207, 255)
def col_red() -> U32: rgb(247, 118, 142)

# Theme ids: items carry 0-3 (4 = saved); the filter selection uses 5 for
# saved. Both map to the same color.
def theme_color(+t: U32) -> U32:
  match t:
    case 1: col_green()
    case 2: col_purple()
    case 3: col_amber()
    case 4: col_cyan()
    case 5: col_cyan()
    case _: col_accent()

def ui_pick(+b: Bool, +yes: U32, +no: U32) -> U32:
  match b:
    case True{}: yes
    case False{}: no

def ui_pick_str(+b: Bool, +yes: String, +no: String) -> String:
  match b:
    case True{}: yes
    case False{}: no

# ---------- Symbols (font6x12.bend codes 1-7) ----------
def sym(+c: U32) -> String: Char.show(Chr{c})
def sym_dot() -> String: sym(1)
def sym_ell() -> String: sym(2)
def sym_ptr() -> String: sym(3)
def sym_check() -> String: sym(4)
def sym_up() -> String: sym(5)
def sym_down() -> String: sym(6)
def sym_diamond() -> String: sym(7)

# ---------- Strings ----------
def ui_take(s: String, n: Nat) -> String:
  match s, n:
    case _, 0n: ""
    case SNil{}, _: ""
    case SCon{c, t}, 1n+m: SCon{c, ui_take(t, m)}

# Fit s into max cells: a longer string keeps max-1 cells plus an ellipsis.
def ui_fit_go(+over: Bool, +s: String, +max: Nat) -> String:
  match over:
    case True{}: String.append(ui_take(s, Nat.sub(max, 1n)), sym_ell())
    case False{}: s

def ui_fit(+s: String, +max: Nat) -> String:
  ui_fit_go(Nat.is_lt(max, String.length(s)), s, max)

# Fit into a pixel width (6px cells).
def ui_fit_px(+s: String, +px: U32) -> String:
  ui_fit(s, U32.to_nat(U32.div(px, 6)))

# Right-aligned text ending at xr.
def ui_text_right(+s: String, +d: Nat, img: Image, +xr: U32, +y: U32, +c: U32) -> Image:
  draw_text(s, d, img, U32.sub(xr, text_width(s)), y, c)

# ---------- Widgets (pure draw functions) ----------
# Rounded 1px box: each corner pixel is pulled in one step, the pixel-scale
# equivalent of a TUI's box-drawing corners.
def ui_box(+d: Nat, img: Image, +x: U32, +y: U32, +w: U32, +h: U32, +c: U32) -> Image:
  +x2 = U32.sub(U32.add(x, w), 1)
  +y2 = U32.sub(U32.add(y, h), 1)
  +i1 = fill_rect(d, img, U32.add(x, 2), y, U32.sub(w, 4), 1, c)
  +i2 = fill_rect(d, i1, U32.add(x, 2), y2, U32.sub(w, 4), 1, c)
  +i3 = fill_rect(d, i2, x, U32.add(y, 2), 1, U32.sub(h, 4), c)
  +i4 = fill_rect(d, i3, x2, U32.add(y, 2), 1, U32.sub(h, 4), c)
  +i5 = fill_rect(d, i4, U32.add(x, 1), U32.add(y, 1), 1, 1, c)
  +i6 = fill_rect(d, i5, U32.sub(x2, 1), U32.add(y, 1), 1, 1, c)
  +i7 = fill_rect(d, i6, U32.add(x, 1), U32.sub(y2, 1), 1, 1, c)
  fill_rect(d, i7, U32.sub(x2, 1), U32.sub(y2, 1), 1, 1, c)

# A label set into a border line at (x, y): the line is cut 4px either
# side and the 12px glyphs straddle it (6 above, 6 below).
def ui_border_label(+d: Nat, img: Image, +x: U32, +y: U32, +s: String, +bg: U32, +c: U32) -> Image:
  +i1 = fill_rect(d, img, U32.sub(x, 4), y, U32.add(text_width(s), 8), 1, bg)
  draw_text(s, d, i1, x, U32.sub(y, 6), c)

def ui_border_label_right_go(+empty: Bool, +d: Nat, img: Image, +xr: U32, +y: U32, +s: String, +bg: U32, +c: U32) -> Image:
  match empty:
    case True{}: img
    case False{}: ui_border_label(d, img, U32.sub(xr, text_width(s)), y, s, bg, c)

def ui_border_label_right(+d: Nat, img: Image, +xr: U32, +y: U32, +s: String, +bg: U32, +c: U32) -> Image:
  ui_border_label_right_go(String.eq(s, ""), d, img, xr, y, s, bg, c)

# Pane: interior fill (self-clearing inside the border), rounded border
# (accent when focused), title set into the top border, and an optional
# right-aligned border label. Glyphs reach 6px above the pane's top edge.
def ui_pane(+d: Nat, img: Image, +r: Rect, +title: String, +right: String, +focus: Bool) -> Image:
  match r:
    case R{x, y, w, h}:
      +i1 = fill_rect(d, img, U32.add(x, 1), U32.add(y, 1), U32.sub(w, 2), U32.sub(h, 2), col_bg())
      +i2 = ui_box(d, i1, x, y, w, h, ui_pick(focus, col_accent(), col_line()))
      +i3 = ui_border_label(d, i2, U32.add(x, 12), y, title, col_bg(), ui_pick(focus, col_accent(), col_sub()))
      ui_border_label_right(d, i3, U32.sub(U32.add(x, w), 12), y, right, col_bg(), col_faint())

# Overlay card: drop shadow, raised fill, accent border.
def ui_panel(+d: Nat, img: Image, +r: Rect, +th: Theme) -> Image:
  match r:
    case R{x, y, w, h}:
      +i1 = fill_rect(d, img, U32.add(x, 6), U32.add(y, 8), w, h, col_shadow())
      +i2 = fill_rect(d, i1, U32.add(x, 1), U32.add(y, 1), U32.sub(w, 2), U32.sub(h, 2), col_raised())
      ui_box(d, i2, x, y, w, h, col_accent())

# Keycap: a small filled cell behind a key name.
def ui_keycap(+d: Nat, img: Image, +x: U32, +y: U32, +k: String, +on: Bool) -> Image:
  +i1 = fill_rect(d, img, U32.sub(x, 4), U32.sub(y, 2), U32.add(text_width(k), 8), 16, ui_pick(on, col_keycap_on(), col_keycap()))
  draw_text(k, d, i1, x, y, ui_pick(on, col_accent(), col_sub()))

# Draw a label (text) at rect's top-left with padding, clipped to the rect.
# The clip keeps label paint inside its own dirty region: labels render
# unbounded user data (item titles, profile names) that could otherwise
# paint into a neighboring region, which a dirty redraw could not erase.
def ui_label(+d: Nat, img: Image, +r: Rect, s: String, +th: Theme) -> Image:
  match r, th:
    case R{x, y, w, h}, T{_, _, _, text, _}:
      draw_text_clipped(s, d, img, U32.add(x, 8), U32.add(y, 8), text, x, y, U32.add(x, w), U32.add(y, h))

# Hover highlight: True when the mouse hovers theme row n
# (1=all, 2=home, 3=gaming, 4=trip, 5=saved; 0 = none). Threaded from
# app.bend's hover state through shell_render.
def ui_hovered(+hover: U32, +n: U32) -> Bool:
  U32.is_eq(hover, n)

# Legacy tile: a pane with no border label on the right.
def ui_tile(+d: Nat, img: Image, +r: Rect, +title: String, +th: Theme) -> Image:
  ui_pane(d, img, r, title, "", False{})
