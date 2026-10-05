# Mouse click probe: click_action / mouse_action on the REAL app bundle.
# Not a module: concatenated AFTER app.bend.
# Build: cat font.bend img.bend ui.bend reader.bend term.bend shell.bend \
#          pty.bend sock.bend app.bend mouseclick_main.bend > build/mouseclick_all.bend
#        bend build/mouseclick_all.bend -o build/mouseclick_all.js \
#          && bun build/mouseclick_all.js
# Expected: theme2=11 theme0=10 reader=23 term=24 outside=0
#           edge_reader_tl=23 edge_term_br=24 edge_outside=0
#           rightbtn=0 release=0

def kv(name: String, v: U32) -> IO(Unit):
  IO.print(String.append(name, U32.show(v)))

def main() -> IO(Unit):
  do IO<Unit>:
    kv("theme2=", click_action(300, 148))
    kv("theme0=", click_action(300, 112))
    kv("reader=", click_action(556, 760))
    kv("term=", click_action(852, 760))
    kv("outside=", click_action(10, 10))
    kv("edge_reader_tl=", click_action(416, 512))
    kv("edge_term_br=", click_action(991, 1007))
    kv("edge_outside=", click_action(992, 1008))
    kv("rightbtn=", mouse_action(556, 760, 1, True{}))
    kv("release=", mouse_action(556, 760, 0, False{}))
