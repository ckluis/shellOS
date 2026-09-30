# Headless proof render for the entry-bar UI overlay.
# Not a module: concatenated AFTER font.bend img.bend ui.bend reader.bend
# term.bend shell.bend. (app.bend NOT included — the three entry-bar defs are
# copied here verbatim from app.bend so this proof does not depend on the
# interactive app or its effect seam.)
# Build: cat font.bend img.bend ui.bend reader.bend term.bend shell.bend \
#          entrybar_main.bend > build/entrybar_all.bend
#        bend build/entrybar_all.bend -o build/entrybar_all.js \
#          && bun build/entrybar_all.js
# Output: proofs/shell_entrybar.ppm (1024x1024, entry bar in ADD [0] mode)
#          proofs/shell_entrybar_edit.ppm (EDIT mode, empty entry: placeholder)
#
# NOTE (2026-09-24): shell_render signature is (d, sel_idx, items, t, tfocus,
# vs, hover, tab_idx, tab_count, profile) — feed removed; reader tile uses cached ViewSt lines.
# Keep this main in sync with shell.bend.

# --- verbatim from app.bend (2026-09-24 entry-bar polish) ---
def entry_mode_label(entry_mode: U32) -> String:
  match entry_mode:
    case 0: ""
    case 1: "ADD [0]"
    case 2: "ADD [1]"
    case 3: "ADD [2]"
    case 4: "ADD [3]"
    case _: "EDIT"

# Label color: orange for ADD modes, teal for EDIT.
def entry_label_color(entry_mode: U32) -> U32:
  match entry_mode:
    case 5: rgb(120, 220, 200)
    case _: rgb(255, 200, 100)

# Block cursor: filled 8x20 rect at the end of the typed text (entries are
# input-capped at 64 chars, so the cursor always lands inside the bar).
def draw_entry_cursor(+d: Nat, img: Image, +entry: String) -> Image:
  +cx = U32.add(160, U32.mul(8, U32.from_nat(String.length(entry))))
  fill_rect(d, img, cx, 986, 8, 20, rgb(230, 230, 230))

# Empty entry shows a dimmed placeholder; non-empty shows text + block cursor.
def draw_entry_text_go(+d: Nat, img: Image, +entry: String, is_empty: Bool) -> Image:
  match is_empty:
    case True{}:
      draw_text("type a title...", d, img, 160, 988, rgb(110, 114, 128))
    case False{}:
      +t1 = draw_text(entry, d, img, 160, 988, rgb(230, 230, 230))
      draw_entry_cursor(d, t1, entry)

def draw_entry_text(+d: Nat, img: Image, +entry: String) -> Image:
  draw_entry_text_go(d, img, entry, U32.is_eq(U32.from_nat(String.length(entry)), 0))

def draw_entry_bar_go(+d: Nat, img: Image, +entry: String, +entry_mode: U32, is_zero: Bool) -> Image:
  match is_zero:
    case True{}: img
    case False{}:
      +bar = fill_rect(d, img, 0, 976, 1024, 48, rgb(32, 36, 48))
      +bar1 = draw_text(entry_mode_label(entry_mode), d, bar, 16, 988, entry_label_color(entry_mode))
      draw_entry_text(d, bar1, entry)

def draw_entry_bar(+d: Nat, img: Image, +entry: String, +entry_mode: U32) -> Image:
  draw_entry_bar_go(d, img, entry, entry_mode, U32.is_eq(entry_mode, 0))
# --- end verbatim from app.bend ---

# Pure helper: frame + entry-bar overlay in one place; + params are freely
# reusable in pure helpers (unlike consecutive pure binds in do-blocks).
def frame_with_bar(+d: Nat, +items: List<&2, Item>) -> Image:
  +base = shell_render(d, 0, items, term_new(), False{}, viewst_new(""), 0, 0, 1, "default")
  draw_entry_bar(d, base, "hello world", 1)

def frame_with_bar_edit(+d: Nat, +items: List<&2, Item>) -> Image:
  +base = shell_render(d, 0, items, term_new(), False{}, viewst_new(""), 0, 0, 1, "default")
  draw_entry_bar(d, base, "", 5)

def main() -> IO(Unit):
  do IO<Unit>:
    items : List<&2, Item> <- load_items()
    +w : Nat = Nat.mul(32n, 32n)
    +d : Nat = Nat.add(5n, 5n)
    +img : Image = frame_with_bar(d, items)
    write_ppm("proofs/shell_entrybar.ppm", img, d, w, w)
    items2 : List<&2, Item> <- load_items()
    +img2 : Image = frame_with_bar_edit(d, items2)
    write_ppm("proofs/shell_entrybar_edit.ppm", img2, d, w, w)
