# img.bend — pure pixel-quadtree image construction for the purist shell.
# Requires font.bend (import Base + font_byte) concatenated BEFORE this file.
#
# Color convention (project-wide): U32 color = 0xRRGGBB
#   R = (c >> 16) & 0xFF, G = (c >> 8) & 0xFF, B = c & 0xFF.
# There is no runtime to contradict: this module owns the PPM encoder,
# so the convention is established here and documented here.
#
# Performance design: `paint` reuses untouched subtrees by reference and
# substitutes shared `solid_tree` nodes for fully-covered regions, so a
# fill_rect costs O(boundary) new nodes, not O(pixels).

# ---------- color ----------

def rgb(+r: U32, +g: U32, +b: U32) -> U32:
  U32.add(U32.add(U32.mul(r, 65536), U32.mul(g, 256)), b)

def chan_r(+c: U32) -> U32:
  U32.and(U32.shrn(c, 16n), 255)

def chan_g(+c: U32) -> U32:
  U32.and(U32.shrn(c, 8n), 255)

def chan_b(+c: U32) -> U32:
  U32.and(c, 255)

# ---------- quadtree construction ----------

def pow2(d: Nat) -> U32:
  match d:
    case 0n: 1
    case 1n+d2: U32.mul(2, pow2(d2))

# Full depth-d tree of one color. The tag param defeats Bend's common
# subexpression elimination (each recursive call is syntactically distinct).
def solid_tree_go(d: Nat, +c: U32, +tag: U32) -> Image:
  match d:
    case 0n: Pix{c}
    case 1n+d2:
      +d2c = d2
      Qua{solid_tree_go(d2c, c, 0),
          solid_tree_go(d2c, c, 1),
          solid_tree_go(d2c, c, 2),
          solid_tree_go(d2c, c, 3)}
def solid_tree(d: Nat, +c: U32) -> Image:
  solid_tree_go(d, c, 0)

# ---------- paint ----------
# paint_code: 0 = disjoint (or empty rect), 1 = node fully inside rect,
# 2 = partial overlap.

def paint_disjoint(+x: U32, +y: U32, +side: U32, +rx0: U32, +ry0: U32, +rx1: U32, +ry1: U32) -> Bool:
  Bool.or(Bool.or(U32.is_le(rx1, x), U32.is_ge(rx0, U32.add(x, side))),
          Bool.or(U32.is_le(ry1, y), U32.is_ge(ry0, U32.add(y, side))))

def paint_inside(+x: U32, +y: U32, +side: U32, +rx0: U32, +ry0: U32, +rx1: U32, +ry1: U32) -> Bool:
  Bool.and(Bool.and(U32.is_le(rx0, x), U32.is_le(ry0, y)),
           Bool.and(U32.is_le(U32.add(x, side), rx1), U32.is_le(U32.add(y, side), ry1)))

type PCode is Data:
  PDisjoint{}
  PInside{}
  PPartial{}

def paint_code_in(+x: U32, +y: U32, +side: U32, +rx0: U32, +ry0: U32, +rx1: U32, +ry1: U32, ins: Bool) -> PCode:
  match ins:
    case True{}: PInside{}
    case False{}: PPartial{}

def paint_code_dj(+x: U32, +y: U32, +side: U32, +rx0: U32, +ry0: U32, +rx1: U32, +ry1: U32, dj: Bool) -> PCode:
  match dj:
    case True{}: PDisjoint{}
    case False{}: paint_code_in(x, y, side, rx0, ry0, rx1, ry1, paint_inside(x, y, side, rx0, ry0, rx1, ry1))

def paint_code_ey(+x: U32, +y: U32, +side: U32, +rx0: U32, +ry0: U32, +rx1: U32, +ry1: U32, ey: Bool) -> PCode:
  match ey:
    case True{}: PDisjoint{}
    case False{}: paint_code_dj(x, y, side, rx0, ry0, rx1, ry1, paint_disjoint(x, y, side, rx0, ry0, rx1, ry1))

def paint_code_ex(+x: U32, +y: U32, +side: U32, +rx0: U32, +ry0: U32, +rx1: U32, +ry1: U32, ex: Bool) -> PCode:
  match ex:
    case True{}: PDisjoint{}
    case False{}: paint_code_ey(x, y, side, rx0, ry0, rx1, ry1, U32.is_ge(ry0, ry1))

def paint_code(+x: U32, +y: U32, +side: U32, +rx0: U32, +ry0: U32, +rx1: U32, +ry1: U32) -> PCode:
  paint_code_ex(x, y, side, rx0, ry0, rx1, ry1, U32.is_ge(rx0, rx1))

# P: the single directly-self-recursive painter.
# Single top-level multi-scrutinee match (d, img, code) in binder order:
# nested matches would violate the binder-order rule (code is the last param),
# and moving code first breaks the termination checker (code changes per call).
# Invariant: img is a well-formed depth-d tree (Qua at every level when d>0).
# The `1n+d2, Pix{p}` arm is therefore unreachable; it returns a well-formed
# tree so the shape invariant survives even if the invariant were broken.
def P(d: Nat, img: Image, +x: U32, +y: U32, +rx0: U32, +ry0: U32, +rx1: U32, +ry1: U32, +c: U32, code: PCode) -> Image:
  match d, img, code:
    case _, _, PDisjoint{}: img
    case _, _, PInside{}: solid_tree(d, c)
    case 0n, _, PPartial{}: Pix{c}
    case 1n+d2, Qua{tl, tr, bl, br}, PPartial{}:
      +d2c = d2
      +half = pow2(d2c)
      +xh = U32.add(x, half)
      +yh = U32.add(y, half)
      Qua{P(d2c, tl, x, y, rx0, ry0, rx1, ry1, c, paint_code(x, y, half, rx0, ry0, rx1, ry1)),
          P(d2c, tr, xh, y, rx0, ry0, rx1, ry1, c, paint_code(xh, y, half, rx0, ry0, rx1, ry1)),
          P(d2c, bl, x, yh, rx0, ry0, rx1, ry1, c, paint_code(x, yh, half, rx0, ry0, rx1, ry1)),
          P(d2c, br, xh, yh, rx0, ry0, rx1, ry1, c, paint_code(xh, yh, half, rx0, ry0, rx1, ry1))}
    case _, Pix{p}, PPartial{}: solid_tree(d, c)

# Wrapper: normalizes the (unreachable-by-construction) Pix-at-depth>0 case
# so P only ever destructures Qua at depth > 0.
def paint_pix(d: Nat, +p: U32, +x: U32, +y: U32, +rx0: U32, +ry0: U32, +rx1: U32, +ry1: U32, +c: U32) -> Image:
  match d:
    case 0n:
      P(d, Pix{p}, x, y, rx0, ry0, rx1, ry1, c, paint_code(x, y, 1, rx0, ry0, rx1, ry1))
    case 1n+_:
      # Unreachable: paint normalizes (d>0, Pix) via the Qua arm, so paint_pix
      # only sees Pix at d=0. Shape-preserving fallback keeps the tree well-formed.
      solid_tree(d, c)

def paint(+d: Nat, img: Image, +x: U32, +y: U32, +rx0: U32, +ry0: U32, +rx1: U32, +ry1: U32, +c: U32) -> Image:
  match img:
    case Pix{p}:
      paint_pix(d, p, x, y, rx0, ry0, rx1, ry1, c)
    case Qua{tl, tr, bl, br}:
      +side = pow2(d)
      P(d, Qua{tl, tr, bl, br}, x, y, rx0, ry0, rx1, ry1, c, paint_code(x, y, side, rx0, ry0, rx1, ry1))


# Fill [x,x+w) x [y,y+h), clipped to the canvas by construction.
def fill_rect(d: Nat, img: Image, +x: U32, +y: U32, +w: U32, +h: U32, +c: U32) -> Image:
  paint(d, img, 0, 0, x, y, U32.add(x, w), U32.add(y, h), c)

# Clip-aware paint: intersects the rect with the clip rect first.
# Empty intersections become code 0 via paint_code's empty-rect guard.
def cpaint(d: Nat, img: Image, +x: U32, +y: U32, +rx0: U32, +ry0: U32, +rx1: U32, +ry1: U32, +c: U32, +kx0: U32, +ky0: U32, +kx1: U32, +ky1: U32) -> Image:
  paint(d, img, x, y, U32.max(rx0, kx0), U32.max(ry0, ky0), U32.min(rx1, kx1), U32.min(ry1, ky1), c)

def cfill_rect(d: Nat, img: Image, +x: U32, +y: U32, +w: U32, +h: U32, +c: U32, +kx0: U32, +ky0: U32, +kx1: U32, +ky1: U32) -> Image:
  cpaint(d, img, 0, 0, x, y, U32.add(x, w), U32.add(y, h), c, kx0, ky0, kx1, ky1)

# ---------- glyphs & text (font.bend: font_byte) ----------

def paint_bit(+on: Bool, d: Nat, img: Image, +x: U32, +y: U32, +fg: U32) -> Image:
  match on:
    case True{}: paint(d, img, 0, 0, x, y, U32.add(x, 1), U32.add(y, 1), fg)
    case False{}: img

def paint_bit_clipped(+on: Bool, d: Nat, img: Image, +x: U32, +y: U32, +fg: U32, +kx0: U32, +ky0: U32, +kx1: U32, +ky1: U32) -> Image:
  match on:
    case True{}: cpaint(d, img, 0, 0, x, y, U32.add(x, 1), U32.add(y, 1), fg, kx0, ky0, kx1, ky1)
    case False{}: img

def blit_byte(n: Nat, +d: Nat, img: Image, +x: U32, +y: U32, +byte: U32, +fg: U32) -> Image:
  match n:
    case 0n: img
    case 1n+m:
      +mc = m
      # font8x8 convention: bit 0 = leftmost pixel (LSB-first). mc descends
      # 7->0 as x ascends, so test bit (7-mc): first pixel gets bit 0.
      +on = U32.is_ne(U32.and(byte, U32.shln(1, Nat.sub(7n, mc))), 0)
      blit_byte(mc, d, paint_bit(on, d, img, x, y, fg), U32.add(x, 1), y, byte, fg)

def blit_byte_clipped(n: Nat, +d: Nat, img: Image, +x: U32, +y: U32, +byte: U32, +fg: U32, +kx0: U32, +ky0: U32, +kx1: U32, +ky1: U32) -> Image:
  match n:
    case 0n: img
    case 1n+m:
      +mc = m
      # font8x8 convention: bit 0 = leftmost pixel (LSB-first). See blit_byte.
      +on = U32.is_ne(U32.and(byte, U32.shln(1, Nat.sub(7n, mc))), 0)
      blit_byte_clipped(mc, d, paint_bit_clipped(on, d, img, x, y, fg, kx0, ky0, kx1, ky1), U32.add(x, 1), y, byte, fg, kx0, ky0, kx1, ky1)

def blit_rows(n: Nat, +tbl: List<&2, U32>, +d: Nat, img: Image, +gx: U32, +gy: U32, +code: U32, +fg: U32) -> Image:
  match n:
    case 0n: img
    case 1n+m:
      +mc = m
      +row = Nat.sub(7n, mc)
      +yy = U32.add(gy, U32.from_nat(row))
      +byte = font_byte(tbl, U32.add(U32.mul(code, 8), U32.from_nat(row)))
      blit_rows(mc, tbl, d, blit_byte(8n, d, img, gx, yy, byte, fg), gx, gy, code, fg)

def blit_rows_clipped(n: Nat, +tbl: List<&2, U32>, +d: Nat, img: Image, +gx: U32, +gy: U32, +code: U32, +fg: U32, +kx0: U32, +ky0: U32, +kx1: U32, +ky1: U32) -> Image:
  match n:
    case 0n: img
    case 1n+m:
      +mc = m
      +row = Nat.sub(7n, mc)
      +yy = U32.add(gy, U32.from_nat(row))
      +byte = font_byte(tbl, U32.add(U32.mul(code, 8), U32.from_nat(row)))
      blit_rows_clipped(mc, tbl, d, blit_byte_clipped(8n, d, img, gx, yy, byte, fg, kx0, ky0, kx1, ky1), gx, gy, code, fg, kx0, ky0, kx1, ky1)

def blit_glyph(+tbl: List<&2, U32>, d: Nat, img: Image, +gx: U32, +gy: U32, +code: U32, +fg: U32) -> Image:
  blit_rows(8n, tbl, d, img, gx, gy, code, fg)

def blit_glyph_clipped(+tbl: List<&2, U32>, d: Nat, img: Image, +gx: U32, +gy: U32, +code: U32, +fg: U32, +kx0: U32, +ky0: U32, +kx1: U32, +ky1: U32) -> Image:
  blit_rows_clipped(8n, tbl, d, img, gx, gy, code, fg, kx0, ky0, kx1, ky1)

def str_len(s: String) -> Nat:
  match s:
    case SNil{}: 0n
    case SCon{_, t}: Nat.add(1n, str_len(t))

def text_width(s: String) -> U32:
  U32.mul(8, U32.from_nat(str_len(s)))

# Single-line text. For multi-line, split first and call per line.
# The font table is built once per string (not per glyph).
def draw_text_go(s: String, +tbl: List<&2, U32>, +d: Nat, img: Image, +x: U32, +y: U32, +fg: U32) -> Image:
  match s:
    case SNil{}: img
    case SCon{Chr{code}, t}:
      draw_text_go(t, tbl, d, blit_glyph(tbl, d, img, x, y, code, fg), U32.add(x, 8), y, fg)

def draw_text(s: String, +d: Nat, img: Image, +x: U32, +y: U32, +fg: U32) -> Image:
  draw_text_go(s, font_data(), d, img, x, y, fg)

def draw_text_clipped_go(s: String, +tbl: List<&2, U32>, +d: Nat, img: Image, +x: U32, +y: U32, +fg: U32, +kx0: U32, +ky0: U32, +kx1: U32, +ky1: U32) -> Image:
  match s:
    case SNil{}: img
    case SCon{Chr{code}, t}:
      draw_text_clipped_go(t, tbl, d, blit_glyph_clipped(tbl, d, img, x, y, code, fg, kx0, ky0, kx1, ky1), U32.add(x, 8), y, fg, kx0, ky0, kx1, ky1)

def draw_text_clipped(s: String, +d: Nat, img: Image, +x: U32, +y: U32, +fg: U32, +kx0: U32, +ky0: U32, +kx1: U32, +ky1: U32) -> Image:
  draw_text_clipped_go(s, font_data(), d, img, x, y, fg, kx0, ky0, kx1, ky1)

# ---------- PPM encoding (P6 binary) ----------
# Row-major traversal via get_pixel. The quadtree's natural quadrant-major
# order is NOT row-major for depth>1, so we query each pixel by coordinates.

# get_pixel: descend the quadtree to find the color at (x, y).
def select_quad(tl: Image, tr: Image, bl: Image, br: Image, idx: U32) -> Image:
  match idx:
    case 0: tl
    case 1: tr
    case 2: bl
    case _: br

def get_pixel(d: Nat, img: Image, +x: U32, +y: U32) -> U32:
  match d, img:
    case 0n, Pix{c}: c
    case 1n+d2, Qua{tl, tr, bl, br}:
      +d2c = d2
      +half = pow2(d2c)
      +x_div = U32.div(x, half)
      +y_div = U32.div(y, half)
      +idx = U32.add(U32.mul(y_div, 2), x_div)
      +q = select_quad(tl, tr, bl, br, idx)
      +nx = U32.sub(x, U32.mul(x_div, half))
      +ny = U32.sub(y, U32.mul(y_div, half))
      get_pixel(d2c, q, nx, ny)
    case _, Pix{c}: c
    case 0n, Qua{_, _, _, _}: 0

def str_bytes_rev(s: String, acc: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}: acc
    case SCon{Chr{c}, t}: str_bytes_rev(t, Con{c, acc})

def rev_u32(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case h <> t: rev_u32(t, Con{h, acc})

# Forward-order RGB bytes for one pixel, prepended to acc.
# Processing x right-to-left with prepend yields left-to-right order.
def pix_bytes_fwd(+c: U32, acc: List<&2, U32>) -> List<&2, U32>:
  Con{U32.and(U32.shrn(c, 16n), 255), Con{U32.and(U32.shrn(c, 8n), 255), Con{U32.and(c, 255), acc}}}

# Build row y (0-indexed from top), pixels x=w-1 down to 0, prepending bytes.
# Result is forward-order RGB bytes for the row: [R0,G0,B0, R1,G1,B1, ...].
def ppm_row_bytes(+d: Nat, +img: Image, +y: U32, x: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match x:
    case 0n: acc
    case 1n+x2:
      +x2c = x2
      +xx = U32.from_nat(x2c)
      +c = get_pixel(d, img, xx, y)
      ppm_row_bytes(d, img, y, x2c, pix_bytes_fwd(c, acc))

# Append two byte lists (forward order).
def ppm_list_append(xs: List<&2, U32>, ys: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: ys
    case h <> t: Con{h, ppm_list_append(t, ys)}

# Build all rows y=h-1 down to 0, prepending each row's bytes.
# Result is forward-order bytes: [row0, row1, ..., row_{h-1}].
def ppm_rows_rev(+d: Nat, +img: Image, y: Nat, +w: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match y:
    case 0n: acc
    case 1n+y2:
      +y2c = y2
      +yy = U32.from_nat(y2c)
      +row = ppm_row_bytes(d, img, yy, w, Nil{})
      # Prepend row bytes (forward) to acc. Since y descends, acc becomes
      # [row0, row1, ...] in forward order.
      ppm_rows_rev(d, img, y2c, w, ppm_list_append(row, acc))

# String to forward-order bytes.
def str_bytes_fwd(s: String, acc: List<&2, U32>) -> List<&2, U32>:
  match s:
    case SNil{}: rev_u32(acc, Nil{})
    case SCon{Chr{c}, t}: str_bytes_fwd(t, Con{c, acc})

def ppm_bytes(img: Image, d: Nat, +w: Nat, +h: Nat) -> List<&2, U32>:
  +hdr = String.append("P6\n", String.append(Nat.show(w), String.append(" ", String.append(Nat.show(h), "\n255\n"))))
  +hdr_bytes = str_bytes_fwd(hdr, Nil{})
  +px = ppm_rows_rev(d, img, h, w, Nil{})
  ppm_list_append(hdr_bytes, px)

# ---------- PPM file output (the headless proof path) ----------

def write_ppm_written2(f2: File, rres: Result<&1,&1, U32 & String, Unit>) -> IO(Unit):
  match rres:
    case Fail{e}:
      do IO<Unit>:
        _u : Unit <- File.close(f2)
        IO.print("ppm write failed")
    case Done{_}:
      File.close(f2)

def write_ppm_written(wr: File & Result<&1,&1, U32 & String, Unit>) -> IO(Unit):
  (f2, rres) = wr
  write_ppm_written2(f2, rres)

def write_ppm_opened(or_: Result<&1,&1, U32 & String, File>, img: Image, d: Nat, +w: Nat, +h: Nat) -> IO(Unit):
  match or_:
    case Fail{e}: IO.print("ppm open failed")
    case Done{f}:
      do IO<Unit>:
        wr : File & Result<&1,&1, U32 & String, Unit> <- File.write_bytes(f, ppm_bytes(img, d, w, h))
        write_ppm_written(wr)

def write_ppm(path: String, img: Image, d: Nat, +w: Nat, +h: Nat) -> IO(Unit):
  do IO<Unit>:
    or_ : Result<&1,&1, U32 & String, File> <- File.open(path, "w")
    write_ppm_opened(or_, img, d, w, h)
