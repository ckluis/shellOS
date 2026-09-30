# Line count test (updated 2026-09-24: reader_n_lines/scroll_max removed;
# use the cached ViewSt lines via reader_lines/scroll_max_lines).
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.append("art0 lines: ", U32.show(list_len_str(reader_lines(0, "")))))
    IO.print(String.append("art1 lines: ", U32.show(list_len_str(reader_lines(1, "")))))
    IO.print(String.append("art2 lines: ", U32.show(list_len_str(reader_lines(2, "")))))
    IO.print(String.append("art0 maxscroll: ", U32.show(scroll_max_lines(reader_lines(0, "")))))
    IO.print(String.append("art1 maxscroll: ", U32.show(scroll_max_lines(reader_lines(1, "")))))
    IO.print(String.append("art2 maxscroll: ", U32.show(scroll_max_lines(reader_lines(2, "")))))
