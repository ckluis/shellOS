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
# Simple theme: bg, panel, accent, text, dim
type Theme is Data:
  T{bg: U32, panel: U32, accent: U32, text: U32, dim: U32}

def theme_dark() -> Theme:
  T{rgb(16, 18, 24), rgb(28, 32, 42), rgb(80, 160, 255), rgb(230, 230, 230), rgb(120, 130, 150)}

# ---------- Widgets (pure draw functions) ----------
# Draw a filled panel with 1px border.
def ui_panel(+d: Nat, img: Image, +r: Rect, +th: Theme) -> Image:
  match r, th:
    case R{x, y, w, h}, T{bg, panel, accent, text, dim}:
      +img2 = fill_rect(d, img, x, y, w, h, panel)
      # top border
      +img3 = fill_rect(d, img2, x, y, w, 1, dim)
      # bottom border
      +img4 = fill_rect(d, img3, x, U32.sub(U32.add(y, h), 1), w, 1, dim)
      # left border
      +img5 = fill_rect(d, img4, x, y, 1, h, dim)
      # right border
      fill_rect(d, img5, U32.sub(U32.add(x, w), 1), y, 1, h, dim)

# Draw a label (text) at rect's top-left with padding, clipped to the rect.
# The clip keeps label paint inside its own dirty region: labels render
# unbounded user data (item titles, profile names) that could otherwise
# paint into a neighboring region, which a dirty redraw could not erase.
# For text that fits its rect (all fixed UI strings) this changes nothing.
def ui_label(+d: Nat, img: Image, +r: Rect, s: String, +th: Theme) -> Image:
  match r, th:
    case R{x, y, w, h}, T{_, _, _, text, _}:
      draw_text_clipped(s, d, img, U32.add(x, 8), U32.add(y, 8), text, x, y, U32.add(x, w), U32.add(y, h))

# Draw a button: panel + centered label. Returns new image.
# (No interaction in headless proof; hot/active state would tint.)
def ui_button_bc(+hot: Bool, +panel: U32, +accent: U32) -> U32:
  match hot:
    case True{}: accent
    case False{}: panel

# Hover highlight: True when the mouse hovers theme button n
# (1=all, 2=home, 3=gaming, 4=trip; 0 = none). Threaded from app.bend's
# hover state through shell_render.
def ui_hovered(+hover: U32, +n: U32) -> Bool:
  U32.is_eq(hover, n)

# Border color: brighter when hovered.
def ui_button_bord(+hovered: Bool, +dim: U32) -> U32:
  match hovered:
    case True{}: rgb(120, 140, 180)
    case False{}: dim

# Side borders: drawn only when hovered, so the resting look is unchanged.
def ui_button_side(+d: Nat, img: Image, +x: U32, +y: U32, +h: U32, +c: U32, +hovered: Bool) -> Image:
  match hovered:
    case True{}: fill_rect(d, img, x, y, 1, h, c)
    case False{}: img

def ui_button(+d: Nat, img: Image, +r: Rect, +s: String, +th: Theme, +hot: Bool, +hovered: Bool) -> Image:
  match r, th:
    case R{x, y, w, h}, T{bg, panel, accent, text, dim}:
      +bc = ui_button_bc(hot, panel, accent)
      +bcol = ui_button_bord(hovered, dim)
      +img2 = fill_rect(d, img, x, y, w, h, bc)
      +img3 = fill_rect(d, img2, x, y, w, 1, bcol)
      +img4 = fill_rect(d, img3, x, U32.sub(U32.add(y, h), 1), w, 1, bcol)
      +img5 = ui_button_side(d, img4, x, y, h, bcol, hovered)
      +img6 = ui_button_side(d, img5, U32.sub(U32.add(x, w), 1), y, h, bcol, hovered)
      # centered text (approx: 8px per char, 8px tall)
      +tw = U32.mul(U32.from_nat(String.length(s)), 8)
      +tx = U32.add(x, U32.div(U32.sub(w, tw), 2))
      +ty = U32.add(y, U32.div(U32.sub(h, 8), 2))
      draw_text(s, d, img6, tx, ty, text)

# Draw a tile: panel with title label.
def ui_tile(+d: Nat, img: Image, +r: Rect, title: String, +th: Theme) -> Image:
  match r:
    case R{_, _, _, _}:
      +img2 = ui_panel(d, img, r, th)
      ui_label(d, img2, r, title, th)
