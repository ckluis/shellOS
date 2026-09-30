# Direct scroll logic test with synthetic values
def main() -> IO(Unit):
  do IO<Unit>:
    # scroll_down_go(cur, max)
    IO.print(String.append("down(0,10)=", U32.show(scroll_down_go(0, 10))))  # expect 1
    IO.print(String.append("down(5,10)=", U32.show(scroll_down_go(5, 10))))  # expect 6
    IO.print(String.append("down(10,10)=", U32.show(scroll_down_go(10, 10))))  # expect 10 (saturate)
    IO.print(String.append("down(10,5)=", U32.show(scroll_down_go(10, 5))))  # expect 10 (already past max)
    # scroll_up_go(cur)
    IO.print(String.append("up(0)=", U32.show(scroll_up_go(0))))  # expect 0 (saturate, was bug)
    IO.print(String.append("up(5)=", U32.show(scroll_up_go(5))))  # expect 4
    IO.print(String.append("up(1)=", U32.show(scroll_up_go(1))))  # expect 0
