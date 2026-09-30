# Headless proof render for the integrated shell.
# Not a module: this file supplies `main` and is concatenated AFTER
# font.bend img.bend ui.bend reader.bend term.bend shell.bend.
# Build:  cat font.bend img.bend ui.bend reader.bend term.bend shell.bend render_main.bend > build/render_all.bend
#         bend build/render_all.bend -o build/render_all.js && bun build/render_all.js
# Output: proofs/shell_all_live.ppm (1024x1024, integrated reader + terminal tiles)
#
# NOTE (2026-09-24): shell_render signature is (d, sel_idx, items, t, tfocus, vs, hover,
# tab_idx, tab_count, profile) — feed removed; reader tile uses cached ViewSt lines.
# Keep this main in sync with shell.bend.

def main() -> IO(Unit):
  do IO<Unit>:
    items : List<&2, Item> <- load_items()
    +w : Nat = Nat.mul(32n, 32n)
    +d : Nat = Nat.add(5n, 5n)
    +img : Image = shell_render(d, 0, items, term_new(), False{}, viewst_new(""), 0, 0, 1, "default")
    write_ppm("proofs/shell_all_live.ppm", img, d, w, w)
