# Scroll logic test — concatenated after shell.bend (no app.bend, no pty.bend).
# Tests that viewst_scroll changes the ViewSt when reader is focused.

def get_scroll(+vs: ViewSt) -> U32:
  match vs:
    case VSt{page, rfocus, rart, rscroll, _}: rscroll

def main() -> IO(Unit):
  do IO<Unit>:
    # Create initial ViewSt
    vs0 : ViewSt = viewst_new("")
    s0 : U32 = get_scroll(vs0)
    IO.print(String.append("initial scroll: ", U32.show(s0)))
    
    # Focus reader (vs0 is consumed by viewst_new? no, vs0 already used)
    # Use + for reusable ViewSt bindings
    +vs1 : ViewSt = viewst_focus_reader(viewst_new(""))
    IO.print(String.append("reader focused, scroll: ", U32.show(get_scroll(vs1))))
    
    # Scroll down (up=False)
    +vs2 : ViewSt = viewst_scroll(vs1, False{})
    IO.print(String.append("after scroll down: ", U32.show(get_scroll(vs2))))
    
    # Scroll down again
    +vs3 : ViewSt = viewst_scroll(vs2, False{})
    IO.print(String.append("after 2nd scroll down: ", U32.show(get_scroll(vs3))))
    
    # Scroll up (up=True)
    +vs4 : ViewSt = viewst_scroll(vs3, True{})
    IO.print(String.append("after scroll up: ", U32.show(get_scroll(vs4))))
    
    # Switch to article 2 (longer) and test scroll
    +vs5 : ViewSt = viewst_rart_next(viewst_rart_next(vs1, ""), "")
    IO.print(String.append("article 2, initial scroll: ", U32.show(get_scroll(vs5))))
    +vs6 : ViewSt = viewst_scroll(vs5, False{})
    IO.print(String.append("article 2, after scroll down: ", U32.show(get_scroll(vs6))))
    +vs7 : ViewSt = viewst_scroll(vs6, False{})
    IO.print(String.append("article 2, after 2nd scroll down: ", U32.show(get_scroll(vs7))))
