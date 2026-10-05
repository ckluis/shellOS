# Wave 2 Gmail pagination hostile probe (pure Bend, interpreter).
# Bundle: the full app bundle, app main renamed; run it with tests/run_suites.sh.
# (It once took only sock.bend + gmail.bend; gmail.bend now uses ui.bend's types.)
# Run:    BEND_NO_TELEMETRY=1 ~/.bend-2.0.25/bend/bin/bend run build/w2_gmail_page_all.bend
# (see build/w2_gmail_page_run.sh)
# Covers: nextPageToken parse (empty/garbage/overlong/NUL), pageToken request
# building + encoding, page clamping (page 0, page beyond history), token
# history push rules, query-change resets page, next/prev key transitions,
# empty inbox / partial last page / perr indicator rendering, fail-closed
# page-fetch failure (previous page's messages preserved), Esc-state pg
# threading via mail_list_enter.

def p_eq(+got: String, +want: String) -> Bool:
  String.eq(got, want)

def p_eqb(+got: Bool, +want: Bool) -> Bool:
  match got:
    case True{}: want
    case False{}:
      match want:
        case True{}: False{}
        case False{}: True{}

def ck(+ok: Bool, +n: Nat, +name: String) -> String:
  match ok:
    case True{}: String.append("PASS ", String.append(Nat.show(n), String.append(": ", String.append(name, "\n"))))
    case False{}: String.append("FAIL ", String.append(Nat.show(n), String.append(": ", String.append(name, "\n"))))

def rep_go(+n: Nat, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+m: rep_go(m, String.append(acc, "z"))

def rep(+n: Nat) -> String:
  rep_go(n, "")

def mm(+id: String) -> MailMeta:
  MM{id, "from@x", "subj", "date"}

def metas_n_go(+n: Nat, acc: List<&2, MailMeta>) -> List<&2, MailMeta>:
  match n:
    case 0n: acc
    case 1n+m: metas_n_go(m, Con{mm(Nat.show(m)), acc})

def metas_n(+n: Nat) -> List<&2, MailMeta>:
  metas_n_go(n, Nil{})

def mklist(+page: U32, +toks: List<&2, String>, +nxt: Maybe<&2, String>, +metas: List<&2, MailMeta>) -> MailInner:
  MList{"c", "s", "r", "tok", 0n, "", 0, metas, MPg{page, toks, nxt, None{}}}

def mklist_perr(+page: U32, +toks: List<&2, String>, +nxt: Maybe<&2, String>, +metas: List<&2, MailMeta>, +perr: String) -> MailInner:
  MList{"c", "s", "r", "tok", 0n, "", 0, metas, MPg{page, toks, nxt, Some{perr}}}

def pg_of(+inner: MailInner) -> MailPage:
  match inner:
    case MList{_, _, _, _, _, _, _, _, pg}: pg
    case MLoading{_, _, _, _, pg, _, _}: pg
    case MFetchMsg{_, _, _, _, _, _, _, _, _, pg}: pg
    case MReading{_, _, _, _, _, _, _, _, _, _, pg}: pg
    case _: mail_pg_fresh()

def pg_page(+pg: MailPage) -> U32:
  match pg:
    case MPg{page, _, _, _}: page

def pg_nxt_some(+pg: MailPage) -> Bool:
  match pg:
    case MPg{_, _, nxt, _}:
      match nxt:
        case Some{_}: True{}
        case None{}: False{}

def pg_perr_str(+pg: MailPage) -> String:
  match pg:
    case MPg{_, _, _, perr}:
      match perr:
        case Some{m}: m
        case None{}: ""

def mloading_ptok(+inner: MailInner) -> String:
  match inner:
    case MLoading{_, _, _, _, _, ptok, _}: ptok
    case _: "NOT-LOADING"

def mloading_prev_some(+inner: MailInner) -> Bool:
  match inner:
    case MLoading{_, _, _, _, _, _, prev}:
      match prev:
        case Some{_}: True{}
        case None{}: False{}
    case _: False{}

def inner_tag(+inner: MailInner) -> String:
  match inner:
    case MList{_, _, _, _, _, _, _, _, _}: "MList"
    case MLoading{_, _, _, _, _, _, _}: "MLoading"
    case MFetchMsg{_, _, _, _, _, _, _, _, _, _}: "MFetchMsg"
    case MReading{_, _, _, _, _, _, _, _, _, _, _}: "MReading"
    case MNetErr{_}: "MNetErr"
    case MAuthErr{}: "MAuthErr"
    case _: "other"

def lines_at2(+is_zero: Bool, +h: String, +rest_r: String) -> String:
  match is_zero:
    case True{}: h
    case False{}: rest_r

def lines_at(+lines: List<&2, String>, +n: U32) -> String:
  match lines:
    case Nil{}: "<eol>"
    case Con{h, t}: lines_at2(U32.is_eq(n, 0), h, lines_at(t, U32.sub(n, 1)))

def nxt_str(+m: Maybe<&2, String>) -> String:
  match m:
    case Some{t}: t
    case None{}: "<none>"

def meta_id(+m: MailMeta) -> String:
  match m:
    case MM{id, _, _, _}: id

def first_meta_id(+inner: MailInner) -> String:
  match inner:
    case MList{_, _, _, _, _, _, _, metas, _}:
      match metas:
        case Con{m, _}: meta_id(m)
        case Nil{}: "<empty>"
    case _: "<notalist>"

def metas_count_p(+inner: MailInner) -> U32:
  match inner:
    case MList{_, _, _, _, _, _, _, metas, _}: mail_metas_count(metas)
    case _: 999

# --- the 29 cases ---

def c01() -> String:
  ck(p_eq(nxt_str(gmail_list_next("{\"messages\": [{\"id\": \"a\"}], \"nextPageToken\": \"CAEQARgB\", \"resultSizeEstimate\": 25}")), "CAEQARgB"), 1n, "valid nextPageToken parsed")

def c02() -> String:
  ck(p_eq(nxt_str(gmail_list_next("{\"messages\": [{\"id\": \"a\"}], \"resultSizeEstimate\": 3}")), "<none>"), 2n, "absent nextPageToken -> None (last page)")

def c03() -> String:
  ck(p_eq(nxt_str(gmail_list_next("{\"messages\": [], \"nextPageToken\": \"\"}")), "<none>"), 3n, "empty nextPageToken -> None")

def c04() -> String:
  ck(p_eq(nxt_str(gmail_list_next("{\"messages\": [], \"nextPageToken\": 123}")), "<none>"), 4n, "non-string nextPageToken -> None")

def c05() -> String:
  ck(p_eq(Nat.show(String.length(nxt_str(gmail_list_next(String.append("{\"nextPageToken\": \"", String.append(rep(2000n), "\"}")))))), "1024"), 5n, "overlong nextPageToken truncated to 1024 chars")

def c06() -> String:
  ck(p_eq(nxt_str(gmail_list_next(String.append("{\"nextPageToken\": \"ab", String.append(Char.show(Chr{0}), "cd\"}")))), "<none>"), 6n, "NUL inside token -> strict reject, no crash")

def c07() -> String:
  ck(p_eq(gmail_list_path2("", ""), "/gmail/v1/users/me/messages?maxResults=10"), 7n, "empty ptok -> no pageToken param")

def c08() -> String:
  ck(p_eq(gmail_list_path2("hello world", ""), "/gmail/v1/users/me/messages?maxResults=10&q=hello%20world"), 8n, "q encoding unchanged without ptok")

def c09() -> String:
  ck(p_eq(gmail_list_path2("", "a&b=c+d/e"), "/gmail/v1/users/me/messages?maxResults=10&pageToken=a%26b%3Dc%2Bd%2Fe"), 9n, "hostile ptok chars percent-encoded")

def c10() -> String:
  ck(p_eq(gmail_list_path2("", rep(2000n)), String.append("/gmail/v1/users/me/messages?maxResults=10&pageToken=", rep(1024n))), 10n, "overlong ptok truncated to 1024 in request")

def c11() -> String:
  ck(p_eqb(U32.is_eq(pg_page(pg_of(mail_list_next(mklist(1, Con{"", Nil{}}, Some{"tokA"}, metas_n(10n))))), 2), True{}), 11n, "n on page 1 with nxt -> target page 2")

def c11b() -> String:
  ck(p_eq(mloading_ptok(mail_list_next(mklist(1, Con{"", Nil{}}, Some{"tokA"}, metas_n(10n)))), "tokA"), 11n, "n carries the nextPageToken as ptok")

def c11c() -> String:
  ck(p_eqb(mloading_prev_some(mail_list_next(mklist(1, Con{"", Nil{}}, Some{"tokA"}, metas_n(10n)))), True{}), 11n, "n stashes previous MList for fail-closed restore")

def c12() -> String:
  ck(p_eq(inner_tag(mail_list_next(mklist(1, Con{"", Nil{}}, None{}, metas_n(10n)))), "MList"), 12n, "n on last page -> no-op, stays MList")

def c12b() -> String:
  ck(p_eqb(U32.is_eq(pg_page(pg_of(mail_list_next(mklist(1, Con{"", Nil{}}, None{}, metas_n(10n))))), 1), True{}), 12n, "n on last page keeps page 1")

def c13() -> String:
  ck(p_eq(inner_tag(mail_list_prev(mklist(1, Nil{}, None{}, metas_n(10n)))), "MList"), 13n, "p on page 1 -> no-op, stays MList")

def c14() -> String:
  ck(p_eqb(U32.is_eq(pg_page(pg_of(mail_list_prev(mklist(3, Con{"", Con{"tokA", Nil{}}}, Some{"tokB"}, metas_n(10n))))), 2), True{}), 14n, "p on page 3 -> target page 2")

def c14b() -> String:
  ck(p_eq(mloading_ptok(mail_list_prev(mklist(3, Con{"", Con{"tokA", Nil{}}}, Some{"tokB"}, metas_n(10n)))), "tokA"), 14n, "p replays token history (toks[1])")

def c15() -> String:
  ck(p_eq(mloading_ptok(mail_list_prev(mklist(2, Con{"", Nil{}}, None{}, metas_n(10n)))), ""), 15n, "p to page 1 uses empty token")

def c16() -> String:
  ck(p_eq(inner_tag(mail_list_prev(mklist(5, Con{"x", Nil{}}, Some{"t"}, metas_n(3n)))), "MLoading"), 16n, "hostile page-beyond-history -> MLoading, no crash")

def c16b() -> String:
  ck(p_eq(mloading_ptok(mail_list_prev(mklist(5, Con{"x", Nil{}}, Some{"t"}, metas_n(3n)))), ""), 16n, "hostile page-beyond-history -> ptok fails safe to empty")

def c17() -> String:
  ck(p_eq(Nat.show(U32.to_nat(mail_toks_len(mail_toks_push(Nil{}, 1, "t")))), "1"), 17n, "toks_push appends on brand-new page")

def c17b() -> String:
  ck(p_eq(Nat.show(U32.to_nat(mail_toks_len(mail_toks_push(Con{"a", Nil{}}, 1, "b")))), "1"), 17n, "toks_push keeps chain on revisit (no dup)")

def c17c() -> String:
  ck(p_eq(mail_tok_at(mail_toks_push(Con{"a", Nil{}}, 2, "b"), 1), "b"), 17n, "toks_push appends second page token")

def c18() -> String:
  ck(p_eqb(U32.is_eq(pg_page(pg_of(mqry_commit(mklist(3, Con{"", Con{"tokA", Nil{}}}, Some{"tokB"}, metas_n(10n)), "newq"))), 1), True{}), 18n, "query commit resets to page 1")

def c18b() -> String:
  ck(p_eq(inner_tag(mqry_commit(mklist(3, Con{"", Con{"tokA", Nil{}}}, Some{"tokB"}, metas_n(10n)), "newq")), "MLoading"), 18n, "query commit stages a fresh load")

def c18c() -> String:
  ck(p_eqb(mloading_prev_some(mqry_commit(mklist(3, Con{"", Con{"tokA", Nil{}}}, Some{"tokB"}, metas_n(10n)), "newq")), False{}), 18n, "query commit drops previous page (no restore)")

def c19() -> String:
  ck(p_eqb(U32.is_eq(pg_page(pg_of(mail_page_fail(mklist(2, Con{"", Con{"tokA", Nil{}}}, Some{"tokB"}, Con{mm("keepme"), Nil{}}), (0, "boom")))), 2), True{}), 19n, "page-fetch failure restores previous page number")

def c19b() -> String:
  ck(p_eqb(U32.is_eq(metas_count_p(mail_page_fail(mklist(2, Con{"", Con{"tokA", Nil{}}}, Some{"tokB"}, Con{mm("keepme"), Nil{}}), (0, "boom"))), 1), True{}), 19n, "fail closed: previous page's messages preserved")

def c19c() -> String:
  ck(p_eq(first_meta_id(mail_page_fail(mklist(2, Con{"", Con{"tokA", Nil{}}}, Some{"tokB"}, Con{mm("keepme"), Nil{}}), (0, "boom"))), "keepme"), 19n, "fail closed: exact message identity kept")

def c19d() -> String:
  ck(p_eq(pg_perr_str(pg_of(mail_page_fail(mklist(2, Con{"", Con{"tokA", Nil{}}}, Some{"tokB"}, Con{mm("keepme"), Nil{}}), (0, "boom")))), "boom"), 19n, "failure surfaces as one-shot perr line")

def c20() -> String:
  ck(p_eq(inner_tag(mail_list_fail(None{}, (0, "net down"))), "MNetErr"), 20n, "fresh-load failure keeps terminal MNetErr")

def c21() -> String:
  ck(p_eq(pg_perr_str(pg_of(mail_page_fail(mklist(2, Con{"", Nil{}}, Some{"t"}, Nil{}), (401, "invalid_grant")))), "auth expired or revoked"), 21n, "401 mid-pages -> auth message on restored page")

def c22() -> String:
  ck(p_eq(lines_at(mail_lines(mklist(2, Con{"", Con{"tokA", Nil{}}}, Some{"tokB"}, metas_n(10n))), 1), "page 2/... msgs 11-20"), 22n, "indicator: full middle page")

def c23() -> String:
  ck(p_eq(lines_at(mail_lines(mklist(1, Nil{}, None{}, Nil{})), 1), "no messages"), 23n, "indicator: empty result set")

def c24() -> String:
  ck(p_eq(lines_at(mail_lines(mklist(2, Con{"", Con{"tokA", Nil{}}}, None{}, metas_n(3n))), 1), "page 2 (last) msgs 11-13"), 24n, "indicator: last partial page")

def c25() -> String:
  ck(p_eq(lines_at(mail_lines(mklist_perr(2, Con{"", Con{"tokA", Nil{}}}, Some{"tokB"}, metas_n(10n), "net down")), 0), "(!) net down"), 25n, "perr renders as status line")

def c25b() -> String:
  ck(p_eq(lines_at(mail_lines(mklist_perr(2, Con{"", Con{"tokA", Nil{}}}, Some{"tokB"}, metas_n(10n), "net down")), 2), "page 2/... msgs 11-20"), 25n, "indicator still correct under perr")

def c26() -> String:
  ck(p_eqb(U32.is_eq(pg_page(pg_of(mail_list_enter(mklist(2, Con{"", Con{"tokA", Nil{}}}, Some{"tokB"}, Con{mm("m1"), Nil{}})))), 2), True{}), 26n, "Enter threads pg into MFetchMsg (Esc returns to same page)")

def c27() -> String:
  ck(p_eq(mail_pg_ind(0, Some{"t"}, 10), "page 1/... msgs 1-10"), 27n, "hostile page 0 clamped, no underflow")

def c28() -> String:
  ck(p_eq(pg_perr_str(pg_of(mail_list_next(mklist_perr(1, Con{"", Nil{}}, Some{"tokA"}, metas_n(10n), "old err")))), ""), 28n, "successful nav clears one-shot perr")

def c29() -> String:
  ck(p_eq(lines_at(mail_lines(mklist(1, Nil{}, Some{"tokA"}, metas_n(10n))), 0), "inbox (Enter open, n/p page, / q)"), 29n, "header line documents n/p keys")

def probe_all() -> String:
  String.append(c01(),String.append(c02(),String.append(c03(),String.append(c04(),String.append(
    c05(),String.append(c06(),String.append(c07(),String.append(c08(),String.append(c09(),
    String.append(c10(),String.append(c11(),String.append(c11b(),String.append(c11c(),
    String.append(c12(),String.append(c12b(),String.append(c13(),String.append(c14(),
    String.append(c14b(),String.append(c15(),String.append(c16(),String.append(c16b(),
    String.append(c17(),String.append(c17b(),String.append(c17c(),String.append(c18(),
    String.append(c18b(),String.append(c18c(),String.append(c19(),String.append(c19b(),
    String.append(c19c(),String.append(c19d(),String.append(c20(),String.append(c21(),
    String.append(c22(),String.append(c23(),String.append(c24(),String.append(c25(),String.append(
    c25b(),String.append(c26(),String.append(c27(),String.append(c28(),c29()))))))))))))))))))))))
    )))))))))))))))))))

def main() -> IO(Unit):
  IO.print(probe_all())
