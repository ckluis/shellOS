# test_wave5_help.bend — Wave 5 `?` shortcut overlay interpreter probes.

def h5_acc_closed() -> AccSt:
  Acc{"", False{}, 0, MOff{}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", False{}, 0, 0}, HOff{}}

def h5_acc_help(+ctx: U32) -> AccSt:
  Acc{"", False{}, 0, MOff{}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", False{}, 0, 0}, HOn{ctx}}

def h5_acc_search() -> AccSt:
  Acc{"q", True{}, 0, MOff{}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", False{}, 0, 0}, HOff{}}

def h5_acc_pal() -> AccSt:
  Acc{"", False{}, 0, MOff{}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", True{}, 0, 0}, HOff{}}

def h5_vs() -> ViewSt:
  VSt{0, False{}, 0, 0, Nil{}}

def h5_vs_rfocus() -> ViewSt:
  VSt{0, True{}, 0, 0, Nil{}}

def h5_check(+name: String, +cond: Bool) -> String:
  match cond:
    case True{}: String.append("PASS ", String.append(name, "\n"))
    case False{}: String.append("FAIL ", String.append(name, "\n"))

def h5_t1_go(r: (AccSt & Bool)) -> String:
  match r:
    case (acc, con):
      match acc:
        case Acc{_, _, _, _, _, _, _, _, _, _, HOn{ctx}}:
          String.append(h5_check("help-opens", con), h5_check("help-ctx0", U32.is_eq(ctx, 0)))
        case _: h5_check("help-opens", False{})

def h5_t1() -> String:
  h5_t1_go(acc_scan_key(h5_acc_closed(), Nil{}, 63, False{}, 0, h5_vs(), "", Nil{}))

def h5_t2_go(r: (AccSt & Bool)) -> String:
  match r:
    case (acc, con):
      match acc:
        case Acc{_, _, _, _, _, _, _, _, _, _, HOff{}}: h5_check("help-toggle-closes", con)
        case _: h5_check("help-toggle-closes", False{})

def h5_t2() -> String:
  h5_t2_go(acc_scan_key(h5_acc_help(0), Nil{}, 63, False{}, 0, h5_vs(), "", Nil{}))

def h5_t3_go(r: (AccSt & Bool)) -> String:
  match r:
    case (acc, con):
      match acc:
        case Acc{_, _, _, _, _, _, _, _, _, _, HOff{}}: h5_check("help-esc-closes", con)
        case _: h5_check("help-esc-closes", False{})

def h5_t3() -> String:
  h5_t3_go(acc_scan_key(h5_acc_help(3), Nil{}, 27, False{}, 0, h5_vs(), "", Nil{}))

def h5_t4_go(r: (AccSt & Bool)) -> String:
  match r:
    case (acc, con):
      match acc:
        case Acc{_, _, _, _, _, _, _, _, _, _, HOn{_}}: h5_check("help-swallows-a", con)
        case _: h5_check("help-swallows-a", False{})

def h5_t4() -> String:
  h5_t4_go(acc_scan_key(h5_acc_help(0), Nil{}, 97, False{}, 0, h5_vs(), "", Nil{}))

def h5_t5() -> String:
  h5_check("help-tag-6", U32.is_eq(acc_panel_tag(h5_acc_help(5)), 6))

def h5_t6_go(r: (AccSt & Bool)) -> String:
  match r:
    case (acc, _):
      match acc:
        case Acc{_, _, _, _, _, _, _, _, _, _, HOn{ctx}}: h5_check("help-ctx-search", U32.is_eq(ctx, 1))
        case _: h5_check("help-ctx-search", False{})

def h5_t6() -> String:
  h5_t6_go(acc_scan_key(h5_acc_search(), Nil{}, 63, False{}, 0, h5_vs(), "", Nil{}))

def h5_t7_go(r: (AccSt & Bool)) -> String:
  match r:
    case (acc, _):
      match acc:
        case Acc{_, _, _, _, _, _, _, _, _, _, HOn{ctx}}: h5_check("help-ctx-palette", U32.is_eq(ctx, 5))
        case _: h5_check("help-ctx-palette", False{})

def h5_t7() -> String:
  h5_t7_go(acc_scan_key(h5_acc_pal(), Nil{}, 63, False{}, 0, h5_vs(), "", Nil{}))

def h5_t8_go(r: (AccSt & Bool)) -> String:
  match r:
    case (acc, _):
      match acc:
        case Acc{_, _, _, _, _, _, _, _, _, _, HOn{ctx}}: h5_check("help-ctx-term", U32.is_eq(ctx, 8))
        case _: h5_check("help-ctx-term", False{})

def h5_t8() -> String:
  h5_t8_go(acc_scan_key(h5_acc_closed(), Nil{}, 63, True{}, 0, h5_vs(), "", Nil{}))

def h5_t9_go(r: (AccSt & Bool)) -> String:
  match r:
    case (acc, _):
      match acc:
        case Acc{_, _, _, _, _, _, _, _, _, _, HOn{ctx}}: h5_check("help-ctx-entry", U32.is_eq(ctx, 6))
        case _: h5_check("help-ctx-entry", False{})

def h5_t9() -> String:
  h5_t9_go(acc_scan_key(h5_acc_closed(), Nil{}, 63, False{}, 1, h5_vs(), "", Nil{}))

def h5_t10_go(r: (AccSt & Bool)) -> String:
  match r:
    case (acc, _):
      match acc:
        case Acc{_, _, _, _, _, _, _, _, _, _, HOn{ctx}}: h5_check("help-ctx-reader", U32.is_eq(ctx, 7))
        case _: h5_check("help-ctx-reader", False{})

def h5_t10() -> String:
  h5_t10_go(acc_scan_key(h5_acc_closed(), Nil{}, 63, False{}, 0, h5_vs_rfocus(), "", Nil{}))

def h5_t11() -> String:
  String.append(h5_check("table-ctx0", U32.is_lt(0, help_count(help_binds_for(0)))),
  String.append(h5_check("table-ctx1", U32.is_lt(0, help_count(help_binds_for(1)))),
  h5_check("table-ctx8", U32.is_lt(0, help_count(help_binds_for(8))))))

# t12: opening and closing help marks the frame touched, so it repaints
# (it was invisible in native builds while accd was preserved).
def h5_t12_open(r: (AccSt & Bool)) -> Bool:
  match r:
    case (acc, _): acc_is_touched(acc)

def h5_t12() -> String:
  String.append(h5_check("help-open-repaints", h5_t12_open(acc_scan_key(h5_acc_closed(), Nil{}, 63, False{}, 0, h5_vs(), "", Nil{}))),
  h5_check("help-close-repaints", acc_is_touched(acc_help_close(h5_acc_help(0)))))

# t13: keys are stripped from the normal keymap while help is open and on
# the key that closes it (Esc closing help used to quit the app).
def h5_t13() -> String:
  String.append(h5_check("help-open-strips-keys", acc_strip_q(h5_acc_help(0), h5_acc_help(0))),
  h5_check("help-close-strips-esc", acc_strip_q(h5_acc_help(0), acc_help_close(h5_acc_help(0)))))

def h5_main() -> String:
  String.append(h5_t1(), String.append(h5_t2(), String.append(h5_t3(),
  String.append(h5_t4(), String.append(h5_t5(), String.append(h5_t6(),
  String.append(h5_t7(), String.append(h5_t8(), String.append(h5_t9(),
  String.append(h5_t10(), String.append(h5_t11(), String.append(h5_t12(), h5_t13()))))))))))))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(h5_main())
