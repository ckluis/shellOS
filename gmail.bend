# ---------- Gmail read-only tile (accretive #3) ----------
# Config: $HOME/.config/shell-os/gmail.conf, key=value lines:
#   client_id=...  client_secret=...  refresh_token=...
# The file MUST be owner-only (0600): any group/other permission bit set
# fails closed (MBadPerm) BEFORE reading. Absent file -> MNotCfg.
# Scope used at token time: https://www.googleapis.com/auth/gmail.readonly
# Read-only by construction: only token refresh, message list, and
# single-message metadata/snippet read exist. No send/modify paths.
# Wave 6: the list accepts a server-side search query (`/` opens the query
# box; the query is percent-encoded and passed as the messages.list `q`
# parameter). The encoded query is a URL parameter value only — it never
# reaches a shell, eval, or any other interpreter.
# Wave 2 (pagination): the list pages through the Gmail API's `pageToken`
# mechanism. `n` = next page, `p` = prev page (list level only; both are free
# there because open accessory panels strip keys from the main stream, so the
# reader's `n` and the profile key `p` never fire while this tile is open).
# Page state (number, token history, next-page token, one-shot fetch error)
# rides in a MailPage value threaded through MList/MReading/MFetchMsg, so it
# survives Esc round-trips; committing a new query resets to page 1. A failed
# page fetch restores the previous page with an error line (fail closed: never
# another page's messages). The pageToken is percent-encoded like `q` and
# capped at 1024 chars; it travels only in the GET request line over the
# existing TLS path.
# Secrets (client_secret, refresh_token, access_token) live in memory
# only: never rendered, never logged, never written to disk.

def filemode_raw(path: String) -> IO(Result<&1,&1, U32 & String, U32>):
  import "./effs/file_mode.c"
  import "./effs/file_mode.js"

type MailMeta is Data:
  MM{id: String, from: String, subject: String, date: String}

# ---------- pagination state (Wave 2) ----------
# page: 1-based page number. toks: pageToken history — toks[i] is the
# pageToken that fetches page i+1 (toks[0] = "" fetches page 1); appended
# only when a brand-new page is fetched, so back-navigation replays the
# exact token chain. nxt: nextPageToken from the last list response
# (None = last page known). perr: one-shot page-fetch error, rendered as a
# status line and cleared on the next successful navigation.
type MailPage is Data:
  MPg{page: U32, toks: List<&2, String>, nxt: Maybe<&2, String>, perr: Maybe<&2, String>}

def mail_pg_fresh() -> MailPage:
  MPg{1, Nil{}, None{}, None{}}

type MailInner is Data:
  MUnknown{}       # config not yet checked (first IO pass checks)
  MNotCfg{}        # no config file
  MBadPerm{}       # config exists but is not owner-only
  MCfgErr{msg: String}  # config unreadable or missing fields
  MLoading{cid: String, csec: String, rtok: String, q: String, pg: MailPage, ptok: String, prev: Maybe<&2, MailInner>}  # creds held; next pass fetches (q = committed search query, "" = unfiltered; pg = TARGET page, ptok = pageToken for it, prev = page we came from or None)
  # List/reading/fetch carry the full context (creds + list position) so Esc
  # returns to the exact list and a retry key can re-run the config check.
  # pg = pagination state (Wave 2): 1-based page, pageToken history, the
  # nextPageToken from the last list response (None = last page), and a
  # one-shot page-fetch error. Threaded through reading/fetch so Esc lands
  # back on the same page.
  MList{cid: String, csec: String, rtok: String, token: String, exp: Nat, q: String, cur: U32, metas: List<&2, MailMeta>, pg: MailPage}
  MReading{cid: String, csec: String, rtok: String, token: String, exp: Nat, q: String, meta: MailMeta, body: String, cur: U32, metas: List<&2, MailMeta>, pg: MailPage}
  MFetchMsg{cid: String, csec: String, rtok: String, token: String, exp: Nat, q: String, meta: MailMeta, cur: U32, metas: List<&2, MailMeta>, pg: MailPage}
  # Query box (Wave 6): `/` opens it from any list-level state. draft = text
  # being edited (capped at 256 chars); base = state to return to on Esc, or
  # to refetch from on Enter (Enter from a non-list base just returns to base).
  MQry{draft: String, base: MailInner}
  MAuthErr{}       # 401/invalid_grant: re-auth needed
  MNetErr{msg: String}  # transport/TLS/HTTP failure (msg shown, never secrets)

type MailSt is Data:
  MOff{}
  MOn{inner: MailInner}

# ---------- config ----------

type KV is Data:
  KV{k: String, v: String}

type CfgRes is Data:
  CfgAbsent{}
  CfgBadPerm{}
  CfgBad{}
  CfgOk{kv: List<&2, KV>}

def cfg_path(+name: String, +home: String) -> String:
  String.append(home, String.append("/.config/shell-os/", name))

def cfg_val_nonempty(+val_empty: Bool, +key: String, +val: String) -> Maybe<&2, KV>:
  match val_empty:
    case True{}: None{}
    case False{}: Some{KV{key, val}}

def cfg_parse_line_val(+key_empty: Bool, +key: String, +val: String) -> Maybe<&2, KV>:
  match key_empty:
    case True{}: None{}
    case False{}: cfg_val_nonempty(String.eq(val, ""), key, val)

def cfg_line_usable_c(+is_hash: Bool) -> Bool:
  match is_hash:
    case True{}: False{}
    case False{}: True{}

def cfg_line_usable(+l: String) -> Bool:
  match l:
    case SNil{}: False{}
    case SCon{Chr{c}, _}: cfg_line_usable_c(U32.is_eq(c, 35))

def cfg_parse_line_add2(+mkv: Maybe<&2, KV>, acc: List<&2, KV>) -> List<&2, KV>:
  match mkv:
    case None{}: acc
    case Some{kv}: List.append(&2, KV, acc, Con{kv, Nil{}})

def json_is_ws(+c: U32) -> Bool:
  Bool.or(Bool.or(U32.is_eq(c, 32), U32.is_eq(c, 9)), Bool.or(U32.is_eq(c, 10), U32.is_eq(c, 13)))

def json_esc_char(+c: U32) -> U32:
  match c:
    case 110: 10
    case 116: 9
    case 114: 13
    case 92: 92
    case 34: 34
    case 47: 47
    case _: 63

def json_hex_digit(+c: U32) -> Bool:
  Bool.or(Bool.and(U32.is_le(48, c), U32.is_le(c, 57)),
    Bool.or(Bool.and(U32.is_le(97, c), U32.is_le(c, 102)), Bool.and(U32.is_le(65, c), U32.is_le(c, 70))))

def json_hex_val3_go(+is_lower: Bool, +c: U32) -> U32:
  match is_lower:
    case True{}: U32.sub(c, 87)
    case False{}: U32.sub(c, 55)

# Parse a JSON string literal starting AFTER the opening quote.
# Returns (decoded value, rest after the closing quote).
def json_hex_val3(+c: U32) -> U32:
  json_hex_val3_go(Bool.and(U32.is_le(97, c), U32.is_le(c, 102)), c)

def json_hex_val2_go(+is_digit: Bool, +c: U32) -> U32:
  match is_digit:
    case True{}: U32.sub(c, 48)
    case False{}: json_hex_val3(c)

def json_hex_val2(+c: U32) -> U32:
  json_hex_val2_go(Bool.and(U32.is_le(48, c), U32.is_le(c, 57)), c)

def json_hex_val_go(+is_hex: Bool, +c: U32) -> U32:
  match is_hex:
    case False{}: 0
    case True{}: json_hex_val2(c)

def json_hex_val(+c: U32) -> U32:
  json_hex_val_go(json_hex_digit(c), c)

# Find `"key"` and return (string value, rest after value). Single pass.
def json_field_pick(mr: Maybe<(String & String)>) -> Maybe<&2, String>:
  match mr:
    case None{}: None{}
    case Some{(v, _)}: Some{v}

# Nat field: `"key": 1234`.
def json_colon_pos2(+is_colon: Bool, +t: String) -> Maybe<String>:
  match is_colon:
    case False{}: None{}
    case True{}: Some{t}

def json_colon_pos_go(+s: String) -> Maybe<String>:
  match s:
    case SNil{}: None{}
    case SCon{Chr{c}, t}: json_colon_pos2(U32.is_eq(c, 58), t)

def json_is_digit(+c: U32) -> Bool:
  Bool.and(U32.is_le(48, c), U32.is_le(c, 57))

def json_opt(+m: Maybe<&2, String>) -> String:
  match m:
    case None{}: ""
    case Some{v}: v

# ---------- HTTPS request plumbing ----------
# One attempt per call: connect, send, receive-all, validate, close.
# No retries (no retry storm); truncation and status are fail-closed.

def http_post_req(+host: String, +path: String, +headers: String, +body: String) -> String:
  String.append("POST ", String.append(path, String.append(" HTTP/1.0\r\nHost: ",
    String.append(host, String.append("\r\n", String.append(headers,
      String.append("Content-Length: ", String.append(Nat.show(String.length(body)),
        String.append("\r\nConnection: close\r\n\r\n", body)))))))))

def http_get_req(+host: String, +path: String, +headers: String) -> String:
  String.append("GET ", String.append(path, String.append(" HTTP/1.0\r\nHost: ",
    String.append(host, String.append("\r\n", String.append(headers, "Connection: close\r\n\r\n"))))))

def tls_req_got2(+ok: Bool, +status: U32, tls: Tls, +body: String) -> IO(Result<&1,&1, U32 & String, (U32 & String)>):
  match ok:
    case False{}:
      do IO<Result<&1,&1, U32 & String, (U32 & String)>>:
        _u : Unit <- Tls.close(tls)
        IO.pure(Result<&1,&1, U32 & String, (U32 & String)>, Fail{(0, "https: truncated response")})
    case True{}:
      do IO<Result<&1,&1, U32 & String, (U32 & String)>>:
        _u : Unit <- Tls.close(tls)
        IO.pure(Result<&1,&1, U32 & String, (U32 & String)>, Done{(status, http_strip_headers(body))})

def sock_req_got2(+ok: Bool, +status: U32, sock: Sock, +body: String) -> IO(Result<&1,&1, U32 & String, (U32 & String)>):
  match ok:
    case False{}:
      do IO<Result<&1,&1, U32 & String, (U32 & String)>>:
        _u : Unit <- Sock.close(sock)
        IO.pure(Result<&1,&1, U32 & String, (U32 & String)>, Fail{(0, "http: truncated response")})
    case True{}:
      do IO<Result<&1,&1, U32 & String, (U32 & String)>>:
        _u : Unit <- Sock.close(sock)
        IO.pure(Result<&1,&1, U32 & String, (U32 & String)>, Done{(status, http_strip_headers(body))})

def gmail_token_body(+cid: String, +csec: String, +rtok: String) -> String:
  String.append("client_id=", String.append(cid, String.append("&client_secret=",
    String.append(csec, String.append("&refresh_token=", String.append(rtok, "&grant_type=refresh_token"))))))

def gmail_refresh_exp(+mexp: Maybe<&2, Nat>, +tok: String) -> Result<&1,&1, U32 & String, (String & Nat)>:
  match mexp:
    case None{}: Done{(tok, Nat.mul(3600n, 1000n))}
    case Some{e}: Done{(tok, Nat.mul(e, 1000n))}

# ---------- URL query encoding (Wave 6) ----------
# Percent-encodes a Gmail search query for the messages.list `q` parameter.
# Unreserved chars (RFC 3986: A-Z a-z 0-9 - _ . ~) pass through; every other
# codepoint is UTF-8-encoded in pure Bend, then each byte becomes %XX with
# UPPERCASE hex. UTF-16 surrogates and codepoints > U+10FFFF can never appear
# in valid text; they encode as U+FFFD (fail-safe, never a raw byte).
# The result is a URL parameter VALUE only: it is concatenated into the GET
# request line sent over the existing TLS path. It never reaches a shell,
# eval, or any other interpreter.

def url_hexdig(+v: U32) -> String:
  match v:
    case 0: "0"
    case 1: "1"
    case 2: "2"
    case 3: "3"
    case 4: "4"
    case 5: "5"
    case 6: "6"
    case 7: "7"
    case 8: "8"
    case 9: "9"
    case 10: "A"
    case 11: "B"
    case 12: "C"
    case 13: "D"
    case 14: "E"
    case 15: "F"
    case _: "?"

def url_pct(+b: U32) -> String:
  String.append("%", String.append(url_hexdig(U32.div(b, 16)), url_hexdig(U32.mod(b, 16))))

def url_is_unreserved(+c: U32) -> Bool:
  Bool.or(Bool.and(U32.is_le(48, c), U32.is_le(c, 57)),
    Bool.or(Bool.and(U32.is_le(65, c), U32.is_le(c, 90)),
      Bool.or(Bool.and(U32.is_le(97, c), U32.is_le(c, 122)),
        Bool.or(U32.is_eq(c, 45),
          Bool.or(U32.is_eq(c, 95),
            Bool.or(U32.is_eq(c, 46), U32.is_eq(c, 126)))))))

def url_enc_2byte(+c: U32) -> String:
  String.append(url_pct(U32.add(192, U32.shrn(c, 6n))),
    url_pct(U32.add(128, U32.and(c, 63))))

def url_enc_3byte(+c: U32) -> String:
  String.append(url_pct(U32.add(224, U32.shrn(c, 12n))),
    String.append(url_pct(U32.add(128, U32.and(U32.shrn(c, 6n), 63))),
      url_pct(U32.add(128, U32.and(c, 63)))))

def url_enc_4byte(+c: U32) -> String:
  String.append(url_pct(U32.add(240, U32.shrn(c, 18n))),
    String.append(url_pct(U32.add(128, U32.and(U32.shrn(c, 12n), 63))),
      String.append(url_pct(U32.add(128, U32.and(U32.shrn(c, 6n), 63))),
        url_pct(U32.add(128, U32.and(c, 63))))))

def url_enc_fffd() -> String:
  "%EF%BF%BD"

def url_enc_hi4_go(+ok: Bool, +c: U32) -> String:
  match ok:
    case True{}: url_enc_4byte(c)
    case False{}: url_enc_fffd()

def url_enc_hi4(+c: U32) -> String:
  url_enc_hi4_go(U32.is_le(c, 1114111), c)

def url_enc_hi_nonsurr_go(+is_3: Bool, +c: U32) -> String:
  match is_3:
    case True{}: url_enc_3byte(c)
    case False{}: url_enc_hi4(c)

def url_enc_hi_nonsurr(+c: U32) -> String:
  url_enc_hi_nonsurr_go(U32.is_le(c, 65535), c)

def url_enc_hi_surr_go(+is_surr: Bool, +c: U32) -> String:
  match is_surr:
    case True{}: url_enc_fffd()
    case False{}: url_enc_hi_nonsurr(c)

def url_enc_hi_go(+is_2: Bool, +c: U32) -> String:
  match is_2:
    case True{}: url_enc_2byte(c)
    case False{}: url_enc_hi_surr_go(Bool.and(U32.is_le(55296, c), U32.is_le(c, 57343)), c)

# c >= 0x80 here (ASCII handled by the caller).
def url_enc_hi(+c: U32) -> String:
  url_enc_hi_go(U32.is_le(c, 2047), c)

def url_enc_byte_go(+is_ascii: Bool, +c: U32) -> String:
  match is_ascii:
    case True{}: url_pct(c)
    case False{}: url_enc_hi(c)

def url_enc_char_go(+unres: Bool, +c: U32) -> String:
  match unres:
    case True{}: Char.show(Chr{c})
    case False{}: url_enc_byte_go(U32.is_le(c, 127), c)

def url_enc_char(+c: U32) -> String:
  url_enc_char_go(url_is_unreserved(c), c)

def url_encode_go(+s: String, acc: String) -> String:
  match s:
    case SNil{}: acc
    case SCon{Chr{c}, t}: url_encode_go(t, String.append(acc, url_enc_char(c)))

def url_encode(+s: String) -> String:
  url_encode_go(s, "")

def gmail_list_path_go(+empty: Bool, +q: String) -> String:
  match empty:
    case True{}: "/gmail/v1/users/me/messages?maxResults=10"
    case False{}: String.append("/gmail/v1/users/me/messages?maxResults=10&q=", url_encode(q))

def gmail_list_path(+q: String) -> String:
  gmail_list_path_go(String.eq(q, ""), q)

def gmail_get_req(+token: String, +id: String) -> String:
  http_get_req("gmail.googleapis.com",
    String.append("/gmail/v1/users/me/messages/", String.append(id,
      "?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date")),
    String.append("Authorization: Bearer ", String.append(token, "\r\n")))

def str_trunc_go(s: String, n: Nat, acc: String) -> String:
  match s, n:
    case SNil{}, _: acc
    case _, 0n: acc
    case SCon{Chr{c}, t}, 1n+m: str_trunc_go(t, m, String.append(acc, Char.show(Chr{c})))

def str_trunc(+s: String, n: Nat) -> String:
  str_trunc_go(s, n, "")

# Gmail search queries are capped at 256 CHARS (codepoints) BEFORE encoding —
# the same 256 cap the note editor uses. Enforced while typing (the query box
# refuses a 257th char) and again at commit (defense in depth).
def mail_q_cap(+q: String) -> String:
  str_trunc(q, 256n)

# ---------- pagination: pageToken request + page indicator (Wave 2) ----------

def mail_u32_show(+x: U32) -> String:
  Nat.show(U32.to_nat(x))

# Page tokens are server-opaque but untrusted input to the request builder:
# cap at 1024 chars (real tokens are ~100-200) and percent-encode like `q`.
# The result is a URL parameter VALUE only — same confinement as the query.
def gmail_list_path_ptok(+empty: Bool, +ptok: String) -> String:
  match empty:
    case True{}: ""
    case False{}: String.append("&pageToken=", url_encode(str_trunc(ptok, 1024n)))

def gmail_list_path2(+q: String, +ptok: String) -> String:
  String.append(gmail_list_path(q), gmail_list_path_ptok(String.eq(ptok, ""), ptok))

def gmail_list_req(+token: String, +q: String, +ptok: String) -> String:
  http_get_req("gmail.googleapis.com", gmail_list_path2(q, ptok),
    String.append("Authorization: Bearer ", String.append(token, "\r\n")))

# Page indicator. Page size is the list maxResults (10). Page 0 can never
# arrive from the key handlers but hostile probes can build it — clamp to 1
# (U32.sub would underflow otherwise).
def mail_pg_page1(+is_zero: Bool, +page: U32) -> U32:
  match is_zero:
    case True{}: 1
    case False{}: page

def mail_pg_ind2(+last: Bool, +page: U32, +lo: U32, +hi: U32) -> String:
  match last:
    case True{}:
      String.append("page ", String.append(mail_u32_show(page),
        String.append(" (last) msgs ", String.append(mail_u32_show(lo), String.append("-", mail_u32_show(hi))))))
    case False{}:
      String.append("page ", String.append(mail_u32_show(page),
        String.append("/... msgs ", String.append(mail_u32_show(lo), String.append("-", mail_u32_show(hi))))))

def mail_pg_ind_go(+empty: Bool, +page: U32, +nxt: Maybe<&2, String>, +count: U32) -> String:
  match empty:
    case True{}: "no messages"
    case False{}:
      match nxt:
        case None{}: mail_pg_ind2(True{}, page, U32.add(U32.mul(U32.sub(page, 1), 10), 1), U32.add(U32.mul(U32.sub(page, 1), 10), count))
        case Some{_}: mail_pg_ind2(False{}, page, U32.add(U32.mul(U32.sub(page, 1), 10), 1), U32.add(U32.mul(U32.sub(page, 1), 10), count))

def mail_pg_ind(+page: U32, +nxt: Maybe<&2, String>, +count: U32) -> String:
  mail_pg_ind_go(U32.is_eq(count, 0), mail_pg_page1(U32.is_eq(page, 0), page), nxt, count)

def mail_list_headline_q(+empty: Bool, +q: String) -> String:
  match empty:
    case True{}: "inbox (Enter open, n/p page, / q)"
    case False{}: String.append("q:", String.append(str_trunc(q, 14n), " (n/p page, / q)"))

def mail_list_headline(+q: String) -> String:
  mail_list_headline_q(String.eq(q, ""), q)

def mail_list_perr(+perr: Maybe<&2, String>, +lines: List<&2, String>) -> List<&2, String>:
  match perr:
    case None{}: lines
    case Some{m}: Con{String.append("(!) ", str_trunc(m, 28n)), lines}

def mail_loading_line2(+is_first: Bool, +page: U32) -> String:
  match is_first:
    case True{}: "loading…"
    case False{}: String.append("loading page ", String.append(mail_u32_show(page), "…"))

def mail_loading_line(+pg: MailPage) -> String:
  match pg:
    case MPg{page, _, _, _}: mail_loading_line2(U32.is_eq(page, 1), page)

def mail_title(+inner: MailInner) -> String:
  match inner:
    case MUnknown{}: "MAIL"
    case MNotCfg{}: "MAIL"
    case MBadPerm{}: "MAIL"
    case MCfgErr{msg}: "MAIL"
    case MLoading{_, _, _, _, _, _, _}: "MAIL"
    case MList{_, _, _, _, _, _, _, _, _}: "MAIL"
    case MReading{_, _, _, _, _, _, _, _, _, _, _}: "MAIL"
    case MFetchMsg{_, _, _, _, _, _, _, _, _, _}: "MAIL"
    case MQry{_, _}: "MAIL"
    case MAuthErr{}: "MAIL"
    case MNetErr{_}: "MAIL"

def mail_notcfg_lines() -> List<&2, String>:
  Con{"Gmail not configured", Con{"", Con{"1. Google Cloud: OAuth client",
    Con{"   type Web application", Con{"   redirect:", Con{"   https://developers.google.com/oauthplayground",
      Con{"2. Scope: gmail.readonly", Con{"3. Playground: exchange code", Con{"   for a refresh_token",
        Con{"4. Write ~/.config/shell-os/", Con{"   gmail.conf (mode 0600):", Con{"   client_id=...",
          Con{"   client_secret=...", Con{"   refresh_token=...", Con{"",
            Con{"Full steps: REPORT.md", Nil{}}}}}}}}}}}}}}}}}

def mail_badperm_lines() -> List<&2, String>:
  Con{"gmail.conf is not owner-only", Con{"",
    Con{"Run: chmod 600", Con{"  ~/.config/shell-os/gmail.conf", Con{"",
      Con{"Refusing to read it until", Con{"group/other bits are clear.", Nil{}}}}}}}}

def mail_row2(+sel: Bool, +from: String, +subject: String) -> String:
  match sel:
    case True{}: String.append("> ", str_trunc(String.append(from, String.append(" - ", subject)), 33n))
    case False{}: String.append("  ", str_trunc(String.append(from, String.append(" - ", subject)), 33n))

def mail_row(+from: String, +subject: String, +cur: U32, +idx: U32) -> String:
  mail_row2(U32.is_eq(cur, idx), from, subject)

def mail_list_rows(+metas: List<&2, MailMeta>, +cur: U32, +idx: U32) -> List<&2, String>:
  match metas:
    case Nil{}: Nil{}
    case MM{id, from, subject, date} <> rest:
      Con{mail_row(from, subject, cur, idx), mail_list_rows(rest, cur, U32.add(idx, 1))}

def mail_metas_count(+metas: List<&2, MailMeta>) -> U32:
  match metas:
    case Nil{}: 0
    case _ <> rest: U32.add(1, mail_metas_count(rest))

def mail_list_lines(+q: String, +metas: List<&2, MailMeta>, +cur: U32, +pg: MailPage) -> List<&2, String>:
  match pg:
    case MPg{page, _, nxt, perr}:
      mail_list_perr(perr, Con{mail_list_headline(q),
        Con{mail_pg_ind(page, nxt, mail_metas_count(metas)), mail_list_rows(metas, cur, 0)}})

# Focused query box (Wave 6): the draft being typed plus its exact encoded
# form (what will be sent as `q=`). A focused box (not the list underneath)
# keeps rendering non-recursive, which Bend requires.
def mail_qry_lines(+draft: String) -> List<&2, String>:
  Con{String.append("q> ", String.append(str_trunc(draft, 28n), "_")),
    Con{String.append("-> ", str_trunc(url_encode(draft), 30n)),
      Con{"(Enter: search, Esc: cancel)", Nil{}}}}

def mail_read_body2(+empty: Bool, +body: String) -> List<&2, String>:
  match empty:
    case True{}: Con{"(loading…)", Nil{}}
    case False{}: word_wrap(body, 34n)

def mail_read_body(+body: String) -> List<&2, String>:
  mail_read_body2(String.eq(body, ""), body)

def mail_read_lines2(+from: String, +subject: String, +date: String, +body: String) -> List<&2, String>:
  Con{String.append("From: ", str_trunc(from, 27n)),
    Con{String.append("Date: ", str_trunc(date, 27n)),
      Con{String.append("Subj: ", str_trunc(subject, 27n)),
        Con{"", mail_read_body(body)}}}}

def mail_read_lines(+meta: MailMeta, +body: String) -> List<&2, String>:
  match meta:
    case MM{id, from, subject, date}: mail_read_lines2(from, subject, date, body)

def mail_lines(+inner: MailInner) -> List<&2, String>:
  match inner:
    case MUnknown{}: Con{"checking config…", Nil{}}
    case MNotCfg{}: mail_notcfg_lines()
    case MBadPerm{}: mail_badperm_lines()
    case MCfgErr{msg}: Con{"config error", Con{str_trunc(msg, 40n), Con{"press m to retry", Nil{}}}}
    case MLoading{_, _, _, _, pg, _, _}: Con{mail_loading_line(pg), Nil{}}
    case MList{_, _, _, _, _, q, cur, metas, pg}: mail_list_lines(q, metas, cur, pg)
    case MReading{_, _, _, _, _, _, meta, body, _, _, _}: mail_read_lines(meta, body)
    case MFetchMsg{_, _, _, _, _, _, meta, _, _, _}: Con{"fetching…", mail_read_lines(meta, "")}
    case MQry{draft, _}: mail_qry_lines(draft)
    case MAuthErr{}: Con{"auth expired or revoked", Con{"re-auth required:", Con{"repeat the REPORT.md setup", Con{"to mint a fresh refresh_token", Con{"", Con{"press m to retry", Nil{}}}}}}}
    case MNetErr{msg}: Con{"network error", Con{str_trunc(msg, 34n), Con{"press m to retry", Nil{}}}}

# ---------- list navigation + message fetch staging (used by app.bend) ----------

def mail_meta_at2(+is_zero: Bool, +m: MailMeta, +rest_r: Maybe<&2, MailMeta>) -> Maybe<&2, MailMeta>:
  match is_zero:
    case True{}: Some{m}
    case False{}: rest_r

def mail_meta_at(+metas: List<&2, MailMeta>, +cur: U32) -> Maybe<&2, MailMeta>:
  match metas:
    case Nil{}: None{}
    case +m <> rest:
      mail_meta_at2(U32.is_eq(cur, 0), m, mail_meta_at(rest, U32.sub(cur, 1)))

def mail_cur_up_go(+is_zero: Bool, +cur: U32) -> U32:
  match is_zero:
    case True{}: 0
    case False{}: U32.sub(cur, 1)

def mail_cur_up(+cur: U32) -> U32:
  mail_cur_up_go(U32.is_eq(cur, 0), cur)

def mail_cur_down_pick(+nxt: U32, +lt: Bool) -> U32:
  match lt:
    case True{}: nxt
    case False{}: 0

def mail_cur_down2(+nxt: U32, +n: U32) -> U32:
  mail_cur_down_pick(nxt, U32.is_lt(nxt, n))

def mail_cur_down_go(+no_items: Bool, +cur: U32, +n: U32) -> U32:
  match no_items:
    case True{}: 0
    case False{}: mail_cur_down2(U32.add(cur, 1), n)

def mail_cur_down(+cur: U32, +n: U32) -> U32:
  mail_cur_down_go(U32.is_eq(n, 0), cur, n)

def mail_list_cur_up(+inner: MailInner) -> MailInner:
  match inner:
    case MList{cid, csec, rtok, token, exp, q, cur, metas, pg}:
      MList{cid, csec, rtok, token, exp, q, mail_cur_up(cur), metas, pg}
    case _: inner

def mail_list_cur_down(+inner: MailInner) -> MailInner:
  match inner:
    case MList{cid, csec, rtok, token, exp, q, cur, metas, pg}:
      MList{cid, csec, rtok, token, exp, q, mail_cur_down(cur, mail_metas_count(metas)), metas, pg}
    case _: inner

def mail_list_enter_at(+mmeta: Maybe<&2, MailMeta>, +cid: String, +csec: String, +rtok: String, +token: String, +exp: Nat, +q: String, +cur: U32, +metas: List<&2, MailMeta>, +pg: MailPage) -> MailInner:
  match mmeta:
    case None{}: MList{cid, csec, rtok, token, exp, q, cur, metas, pg}
    case Some{meta}: MFetchMsg{cid, csec, rtok, token, exp, q, meta, cur, metas, pg}

def mail_list_enter(+inner: MailInner) -> MailInner:
  match inner:
    case MList{cid, csec, rtok, token, exp, q, cur, metas, pg}:
      mail_list_enter_at(mail_meta_at(metas, cur), cid, csec, rtok, token, exp, q, cur, metas, pg)
    case _: inner

# ---------- pagination navigation (Wave 2) ----------
# Next page: only when the last list response carried a nextPageToken.
# The target MLoading replays the token chain; the previous MList rides
# along so a failed fetch restores it (fail closed) instead of stranding
# the tile on a terminal error.
def mail_list_next_nx(+nxt: Maybe<&2, String>, +inner: MailInner, +cid: String, +csec: String, +rtok: String, +q: String, +pg: MailPage) -> MailInner:
  match nxt:
    case None{}: inner
    case Some{t}:
      match pg:
        case MPg{page, toks, _, _}:
          MLoading{cid, csec, rtok, q, MPg{U32.add(page, 1), toks, None{}, None{}}, t, Some{inner}}

def mail_list_next(+inner: MailInner) -> MailInner:
  match inner:
    case MList{cid, csec, rtok, _, _, q, _, _, pg}:
      match pg:
        case MPg{_, _, nxt, _}: mail_list_next_nx(nxt, inner, cid, csec, rtok, q, pg)
    case _: inner

# History lookup: toks[i] fetches page i+1. Out of range (cannot happen via
# the key handlers, only via hostile construction) fails safe to "" — the
# page-1 token — rather than crashing.
def mail_tok_at_pick(+is_zero: Bool, +h: String, +rest_r: String) -> String:
  match is_zero:
    case True{}: h
    case False{}: rest_r

def mail_tok_at(+toks: List<&2, String>, +i: U32) -> String:
  match toks:
    case Nil{}: ""
    case Con{h, t}: mail_tok_at_pick(U32.is_eq(i, 0), h, mail_tok_at(t, U32.sub(i, 1)))

def mail_list_prev_go(+is_first: Bool, +inner: MailInner, +cid: String, +csec: String, +rtok: String, +q: String, +pg: MailPage) -> MailInner:
  match is_first:
    case True{}: inner
    case False{}:
      match pg:
        case MPg{page, toks, _, _}:
          MLoading{cid, csec, rtok, q, MPg{U32.sub(page, 1), toks, None{}, None{}}, mail_tok_at(toks, U32.sub(page, 2)), Some{inner}}

def mail_list_prev(+inner: MailInner) -> MailInner:
  match inner:
    case MList{cid, csec, rtok, _, _, q, _, _, pg}:
      match pg:
        case MPg{page, _, _, _}: mail_list_prev_go(U32.is_eq(page, 1), inner, cid, csec, rtok, q, pg)
    case _: inner

# Append this page's token to the history only when fetching a brand-new
# page (len == page-1); revisits keep the existing chain.
def mail_toks_len(+toks: List<&2, String>) -> U32:
  match toks:
    case Nil{}: 0
    case _ <> t: U32.add(1, mail_toks_len(t))

def mail_toks_push_go(+at_end: Bool, +toks: List<&2, String>, +ptok: String) -> List<&2, String>:
  match at_end:
    case True{}: List.append(&2, String, toks, Con{ptok, Nil{}})
    case False{}: toks

def mail_toks_push(+toks: List<&2, String>, +page: U32, +ptok: String) -> List<&2, String>:
  mail_toks_push_go(U32.is_eq(mail_toks_len(toks), U32.sub(page, 1)), toks, ptok)

def mail_pg_err(+pg: MailPage, +msg: String) -> MailPage:
  match pg:
    case MPg{page, toks, nxt, _}: MPg{page, toks, nxt, Some{msg}}

# Open the query box. The draft is prefilled with the committed query when
# opened from a list (so `/` edits the active query); otherwise it starts
# empty. MQry is never opened from MQry (it is not slashable), so base is
# never itself an MQry.
def mqry_open(+inner: MailInner) -> MailInner:
  match inner:
    case MList{_, _, _, _, _, q, _, _, _}: MQry{q, inner}
    case _: MQry{"", inner}

# Commit the draft. From a list/reading base this stages a refetch with the
# new query (empty draft = unfiltered) — always from page 1 with no previous
# page: changing the query resets pagination. From any other base there is
# nothing to apply the query to, so the draft is discarded and base is returned.
def mqry_commit(+base: MailInner, +draft: String) -> MailInner:
  match base:
    case MList{cid, csec, rtok, _, _, _, _, _, _}: MLoading{cid, csec, rtok, mail_q_cap(draft), mail_pg_fresh(), "", None{}}
    case MReading{cid, csec, rtok, _, _, _, _, _, _, _, _}: MLoading{cid, csec, rtok, mail_q_cap(draft), mail_pg_fresh(), "", None{}}
    case _: base

# Map a (status, msg) failure to a terminal mail state: 401 means the refresh
# token is dead (re-auth); anything else is a network error. No retry storm:
# the state only advances on an explicit `m` keypress (see app.bend).
def mail_err_inner_go2(+is_400: Bool, +msg: String) -> MailInner:
  match is_400:
    case True{}: MAuthErr{}
    case False{}: MNetErr{msg}

def mail_err_inner_go(+is_401: Bool, +status: U32, +msg: String) -> MailInner:
  match is_401:
    case True{}: MAuthErr{}
    case False{}: mail_err_inner_go2(U32.is_eq(status, 400), msg)

def mail_err_inner(e: U32 & String) -> MailInner:
  match e:
    case (+status, msg): mail_err_inner_go(U32.is_eq(status, 401), status, msg)

# Page-fetch failure (Wave 2): fail closed. A fresh load (no previous page)
# keeps the existing terminal error; a mid-pagination failure restores the
# previous page's MList with a one-shot error line — the indicator keeps
# showing the correct page and another page's messages are never shown.
def mail_page_fail_msg(+is401: Bool, +msg: String) -> String:
  match is401:
    case True{}: "auth expired or revoked"
    case False{}: msg

def mail_page_fail_mlist(+cid: String, +csec: String, +rtok: String, +token: String, +exp: Nat, +q: String, +cur: U32, +metas: List<&2, MailMeta>, +pg: MailPage, e: U32 & String) -> MailInner:
  match e:
    case (+status, msg):
      MList{cid, csec, rtok, token, exp, q, cur, metas, mail_pg_err(pg, mail_page_fail_msg(U32.is_eq(status, 401), msg))}

def mail_page_fail(+prev: MailInner, e: U32 & String) -> MailInner:
  match prev:
    case MList{cid, csec, rtok, token, exp, q, cur, metas, pg}:
      mail_page_fail_mlist(cid, csec, rtok, token, exp, q, cur, metas, pg, e)
    case _: mail_err_inner(e)

def mail_list_fail(+prev: Maybe<&2, MailInner>, e: U32 & String) -> MailInner:
  match prev:
    case None{}: mail_err_inner(e)
    case Some{p}: mail_page_fail(p, e)

def shell_mail_tile(+d: Nat, img: Image, +r: Rect, +th: Theme, +inner: MailInner) -> Image:
  match r, th:
    case R{x, y, _, _}, T{_, _, _, _, dim}:
      +img2 = ui_tile(d, img, r, mail_title(inner), th)
      draw_lines(d, mail_lines(inner), img2, U32.add(x, 8), U32.add(y, 30), 32, dim)
def cfg_get_put(+v: String, r: Maybe<&2, String>, +hit: Bool) -> Maybe<&2, String>:
  match hit:
    case False{}: r
    case True{}: Some{v}

def cfg_get(+kv: List<&2, KV>, +key: String) -> Maybe<&2, String>:
  match kv:
    case Nil{}: None{}
    case KV{k, v} <> t:
      cfg_get_put(v, cfg_get(t, key), String.eq(k, key))

def cfg_parse_line_pick(+is_eq: Bool, +key: String, +t: String, r: Maybe<&2, KV>) -> Maybe<&2, KV>:
  match is_eq:
    case True{}: cfg_parse_line_val(String.eq(key, ""), key, t)
    case False{}: r

def cfg_parse_line_go(s: String, +key: String) -> Maybe<&2, KV>:
  match s:
    case SNil{}: None{}
    case SCon{Chr{+c}, +t}:
      cfg_parse_line_pick(U32.is_eq(c, 61), key, t, cfg_parse_line_go(t, String.append(key, Char.show(Chr{c}))))

def cfg_parse_line(+line: String) -> Maybe<&2, KV>:
  cfg_parse_line_go(line, "")

def cfg_parse_line_add(+usable: Bool, +l: String, acc: List<&2, KV>) -> List<&2, KV>:
  match usable:
    case False{}: acc
    case True{}: cfg_parse_line_add2(cfg_parse_line(l), acc)

def cfg_parse_lines(+lines: List<&2, String>, acc: List<&2, KV>) -> List<&2, KV>:
  match lines:
    case Nil{}: acc
    case l <> rest: cfg_parse_lines(rest, cfg_parse_line_add(cfg_line_usable(l), l, acc))

def cfg_load_read(fr: File & Result<&1,&1, U32 & String, String>) -> IO(CfgRes):
  (f2, rres) = fr
  match rres:
    case Fail{e}:
      do IO<CfgRes>:
        _u : Unit <- File.close(f2)
        IO.pure(CfgRes, CfgBad{})
    case Done{text}:
      do IO<CfgRes>:
        _u : Unit <- File.close(f2)
        IO.pure(CfgRes, CfgOk{cfg_parse_lines(String.lines(text), Nil{})})

def cfg_load_opened(or_: Result<&1,&1, U32 & String, File>) -> IO(CfgRes):
  match or_:
    case Fail{e}: IO.pure(CfgRes, CfgBad{})
    case Done{f}:
      do IO<CfgRes>:
        fr : File & Result<&1,&1, U32 & String, String> <- File.read(f, 8192)
        cfg_load_read(fr)

def cfg_load_file(+path: String) -> IO(CfgRes):
  do IO<CfgRes>:
    or_ : Result<&1,&1, U32 & String, File> <- File.open(path, "r")
    cfg_load_opened(or_)

def cfg_load_perm2(+ok: Bool, +path: String) -> IO(CfgRes):
  match ok:
    case True{}: cfg_load_file(path)
    case False{}: IO.pure(CfgRes, CfgBadPerm{})

def cfg_load_mode2(mr: Result<&1,&1, U32 & String, U32>, +path: String) -> IO(CfgRes):
  match mr:
    case Fail{e}: IO.pure(CfgRes, CfgAbsent{})
    case Done{mode}: cfg_load_perm2(U32.is_eq(U32.and(mode, 63), 0), path)

def cfg_load_mode(+path: String) -> IO(CfgRes):
  do IO<CfgRes>:
    mr : Result<&1,&1, U32 & String, U32> <- filemode_raw(path)
    cfg_load_mode2(mr, path)

def cfg_load_home(hr: Result<&1,&1, U32 & String, String>, +name: String) -> IO(CfgRes):
  match hr:
    case Fail{e}: IO.pure(CfgRes, CfgAbsent{})
    case Done{home}: cfg_load_mode(cfg_path(name, home))

# Config load: $HOME must exist; the file must exist and be owner-only.
# Any failure is fail-closed (never read a too-permissive file).
def cfg_load(+name: String) -> IO(CfgRes):
  do IO<CfgRes>:
    hr : Result<&1,&1, U32 & String, String> <- IO.get_env("HOME")
    cfg_load_home(hr, name)

# ---------- minimal JSON readers ----------
# Only what the Gmail/AI paths need: top-level string fields, a Nat
# field, repeated "id" strings, and name/value header pairs. Strict:
# full Unicode (escapes + \uXXXX + surrogate pairs), rejects malformed,
# truncated, and garbage input. Linear scans only -- no nesting recursion,
# so hostile deep nesting cannot overflow the stack.

def json_skip_ws_pick(+ws: Bool, +c: U32, +t: String, r: String) -> String:
  match ws:
    case True{}: r
    case False{}: String.append(Char.show(Chr{c}), t)

def json_skip_ws(+s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{+c}, +t}:
      json_skip_ws_pick(json_is_ws(c), c, t, json_skip_ws(t))

def json_colon_pos(+s: String) -> Maybe<String>:
  json_colon_pos_go(json_skip_ws(s))

# ---------- strict JSON string scanner ----------
# Parses one JSON string starting AFTER its opening quote.
# Returns Some{(decoded, rest_after_closing_quote)} or None on ANY malformed
# input: truncated string/escape/unicode, bad escape, unescaped control char,
# isolated or malformed surrogate, missing closing quote.
# Full Unicode: ordinary escapes decoded, \uXXXX decoded (Char.show emits
# proper UTF-8), valid surrogate pairs combined, isolated surrogates rejected.
# State: ud = unicode phase (0 normal, 1 last hi digit, 2-4 hi digits,
#   5 expect backslash, 6 expect u, 7 last lo digit, 8-10 lo digits),
#   uv = accumulated code value, uhi = high surrogate value.

def json_uni_cp(+hi: U32, +lo: U32) -> U32:
  U32.add(65536, U32.add(U32.mul(U32.sub(hi, 55296), 1024), U32.sub(lo, 56320)))

def json_cls_ud5(+c: U32) -> (U32 & U32):
  match c:
    case 92: (9, 0)
    case _: (15, 0)

def json_cls_ud6(+c: U32) -> (U32 & U32):
  match c:
    case 117: (10, 0)
    case _: (15, 0)

def json_uni_cls4(+le_dfff: Bool, +v: U32) -> (U32 & U32):
  match le_dfff:
    case True{}: (15, 0)
    case False{}: (6, v)

def json_uni_cls3(+le_dbff: Bool, +le_dfff: Bool, +v: U32) -> (U32 & U32):
  match le_dbff:
    case True{}: (7, v)
    case False{}: json_uni_cls4(le_dfff, v)

def json_uni_cls2(+ge_d800: Bool, +v: U32) -> (U32 & U32):
  match ge_d800:
    case True{}: json_uni_cls3(U32.is_le(v, 56319), U32.is_le(v, 57343), v)
    case False{}: (6, v)

def json_uni_cls1(+v: U32) -> (U32 & U32):
  json_uni_cls2(U32.is_le(55296, v), v)

def json_cls_lo2(+ok: Bool, +lo: U32, +uhi: U32) -> (U32 & U32):
  match ok:
    case True{}: (8, json_uni_cp(uhi, lo))
    case False{}: (15, 0)

def json_cls_lo(+lo: U32, +uhi: U32) -> (U32 & U32):
  json_cls_lo2(Bool.and(U32.is_le(56320, lo), U32.is_le(lo, 57343)), lo, uhi)

def json_cls_last72(+ok: Bool, +uhi: U32, +uv: U32, +c: U32) -> (U32 & U32):
  match ok:
    case True{}: json_cls_lo(U32.add(U32.mul(uv, 16), json_hex_val(c)), uhi)
    case False{}: (15, 0)

def json_cls_last7(+uhi: U32, +uv: U32, +c: U32) -> (U32 & U32):
  json_cls_last72(json_hex_digit(c), uhi, uv, c)

def json_cls_last12(+ok: Bool, +uv: U32, +c: U32) -> (U32 & U32):
  match ok:
    case True{}: json_uni_cls1(U32.add(U32.mul(uv, 16), json_hex_val(c)))
    case False{}: (15, 0)

def json_cls_last1(+uv: U32, +c: U32) -> (U32 & U32):
  json_cls_last12(json_hex_digit(c), uv, c)

def json_cls_hexm2(+ok: Bool, +c: U32) -> (U32 & U32):
  match ok:
    case True{}: (5, json_hex_val(c))
    case False{}: (15, 0)

def json_cls_hexm(+c: U32) -> (U32 & U32):
  json_cls_hexm2(json_hex_digit(c), c)

def json_cls_ctl(+is_ctl: Bool, +c: U32) -> (U32 & U32):
  match is_ctl:
    case True{}: (15, 0)
    case False{}: (2, c)

def json_cls_norm(+c: U32) -> (U32 & U32):
  match c:
    case 34: (0, 0)
    case 92: (1, 0)
    case _: json_cls_ctl(U32.is_lt(c, 32), c)

def json_cls_ud(+ud: U32, +uv: U32, +uhi: U32, +c: U32) -> (U32 & U32):
  match ud:
    case 5: json_cls_ud5(c)
    case 6: json_cls_ud6(c)
    case 1: json_cls_last1(uv, c)
    case 7: json_cls_last7(uhi, uv, c)
    case _: json_cls_hexm(c)

def json_cls_esc(+c: U32) -> (U32 & U32):
  match c:
    case 117: (4, 0)
    case 110: (3, 10)
    case 116: (3, 9)
    case 114: (3, 13)
    case 98: (3, 8)
    case 102: (3, 12)
    case 47: (3, 47)
    case 34: (3, 34)
    case 92: (3, 92)
    case _: (15, 0)

def json_cls(+esc: Bool, +ud: U32, +uv: U32, +uhi: U32, +c: U32) -> (U32 & U32):
  match esc:
    case True{}: json_cls_esc(c)
    case False{}:
      match ud:
        case 0: json_cls_norm(c)
        case _: json_cls_ud(ud, uv, uhi, c)

def json_cls_next(+esc: Bool, +ud: U32, +uv: U32, +uhi: U32, s: String) -> (U32 & U32):
  match s:
    case SNil{}: (15, 0)
    case SCon{Chr{c}, t}: json_cls(esc, ud, uv, uhi, c)

def json_str_emit(+acc: String, +v: U32) -> String:
  String.append(acc, Char.show(Chr{v}))

def json_str_go(s: String, +esc: Bool, +ud: U32, +uv: U32, +uhi: U32, +acc: String, av: (U32 & U32)) -> (Bool & (String & String)):
  match s:
    case SNil{}: (False{}, (acc, ""))
    case SCon{Chr{c}, +t}:
      match av:
        case (0, _): (True{}, (acc, t))
        case (1, _): json_str_go(t, True{}, 0, 0, 0, acc, json_cls_next(True{}, 0, 0, 0, t))
        case (2, v): json_str_go(t, False{}, 0, 0, 0, json_str_emit(acc, v), json_cls_next(False{}, 0, 0, 0, t))
        case (3, v): json_str_go(t, False{}, 0, 0, 0, json_str_emit(acc, v), json_cls_next(False{}, 0, 0, 0, t))
        case (4, _): json_str_go(t, False{}, 4, 0, 0, acc, json_cls_next(False{}, 4, 0, 0, t))
        case (5, +v): json_str_go(t, False{}, U32.sub(ud, 1), U32.add(U32.mul(uv, 16), v), uhi, acc, json_cls_next(False{}, U32.sub(ud, 1), U32.add(U32.mul(uv, 16), v), uhi, t))
        case (6, v): json_str_go(t, False{}, 0, 0, 0, json_str_emit(acc, v), json_cls_next(False{}, 0, 0, 0, t))
        case (7, +v): json_str_go(t, False{}, 5, v, v, acc, json_cls_next(False{}, 5, v, v, t))
        case (8, v): json_str_go(t, False{}, 0, 0, 0, json_str_emit(acc, v), json_cls_next(False{}, 0, 0, 0, t))
        case (9, _): json_str_go(t, False{}, 6, uv, uhi, acc, json_cls_next(False{}, 6, uv, uhi, t))
        case (10, _): json_str_go(t, False{}, 10, 0, uhi, acc, json_cls_next(False{}, 10, 0, uhi, t))
        case _: (False{}, (acc, ""))

def json_parse_str_ok(r: (Bool & (String & String))) -> Maybe<(String & String)>:
  match r:
    case (True{}, p): Some{p}
    case _: None{}

def json_parse_str(+s: String) -> Maybe<(String & String)>:
  json_parse_str_ok(json_str_go(s, False{}, 0, 0, 0, "", json_cls_next(False{}, 0, 0, 0, s)))

def json_field_str2(+is_q: Bool, +t: String) -> Maybe<(String & String)>:
  match is_q:
    case False{}: None{}
    case True{}: json_parse_str(t)

def json_field_str(+s: String) -> Maybe<(String & String)>:
  match s:
    case SNil{}: None{}
    case SCon{Chr{c}, t}: json_field_str2(U32.is_eq(c, 34), t)

def json_field_colon(+is_colon: Bool, +t: String) -> Maybe<(String & String)>:
  match is_colon:
    case False{}: None{}
    case True{}: json_field_str(json_skip_ws(t))

def json_field_val(+s: String) -> Maybe<(String & String)>:
  match s:
    case SNil{}: None{}
    case SCon{Chr{c}, t}: json_field_colon(U32.is_eq(c, 58), t)

def json_find_after_put(+starts: Bool, +json: String, +pat: String, r: Maybe<String>) -> Maybe<String>:
  match starts:
    case True{}: Some{String.drop(json, String.length(pat))}
    case False{}: r

def json_find_after(+json: String, +pat: String) -> Maybe<String>:
  match json:
    case SNil{}: None{}
    case SCon{Chr{+c}, +t}:
      json_find_after_put(String.starts_with(json, pat), json, pat, json_find_after(t, pat))

def json_field_from(mafter: Maybe<String>) -> Maybe<&2, String>:
  match mafter:
    case None{}: None{}
    case Some{after}: json_field_pick(json_field_val(json_skip_ws(after)))

def json_field(+json: String, +key: String) -> Maybe<&2, String>:
  json_field_from(json_find_after(json, String.append("\"", String.append(key, "\""))))

def json_digits_put(+isd: Bool, +acc: Nat, r: Nat) -> Nat:
  match isd:
    case False{}: acc
    case True{}: r

def json_digits(s: String, +acc: Nat) -> Nat:
  match s:
    case SNil{}: acc
    case SCon{Chr{+c}, +t}:
      json_digits_put(json_is_digit(c), acc, json_digits(t, Nat.add(Nat.mul(acc, 10n), U32.to_nat(U32.sub(c, 48)))))

# All `"id"` string values in a messages-list body.

def json_nat_colon(+is_colon: Bool, +t: String) -> Maybe<&2, Nat>:
  match is_colon:
    case False{}: None{}
    case True{}: Some{json_digits(json_skip_ws(t), 0n)}

def json_nat_val(+s: String) -> Maybe<&2, Nat>:
  match s:
    case SNil{}: None{}
    case SCon{Chr{c}, t}: json_nat_colon(U32.is_eq(c, 58), t)

def json_nat_from(mafter: Maybe<String>) -> Maybe<&2, Nat>:
  match mafter:
    case None{}: None{}
    case Some{after}: json_nat_val(json_skip_ws(after))

def json_nat_field(+json: String, +key: String) -> Maybe<&2, Nat>:
  json_nat_from(json_find_after(json, String.append("\"", String.append(key, "\""))))

def gmail_refresh_tok(+mtok: Maybe<&2, String>, +body: String) -> Result<&1,&1, U32 & String, (String & Nat)>:
  match mtok:
    case None{}: Fail{(0, "gmail: no access_token in response")}
    case Some{tok}: gmail_refresh_exp(json_nat_field(body, "expires_in"), tok)

def gmail_refresh_parse2(+ok: Bool, +status: U32, +body: String) -> Result<&1,&1, U32 & String, (String & Nat)>:
  match ok:
    case False{}: Fail{(status, "gmail: token refresh failed")}
    case True{}: gmail_refresh_tok(json_field(body, "access_token"), body)

def gmail_refresh_parse(rr: Result<&1,&1, U32 & String, (U32 & String)>) -> Result<&1,&1, U32 & String, (String & Nat)>:
  match rr:
    case Fail{e}: Fail{e}
    case Done{(+status, body)}: gmail_refresh_parse2(U32.is_eq(status, 200), status, body)

# Extract every `"id": "<string>"` value from a messages.list body.
# Whitespace- and order-independent: strict `"id"` key match at each position,
# then strict `: "string"` parse (escapes + full Unicode decoded). Malformed
# id fields are skipped, not fatal. Cap 64 ids per response (UI bound).
# Runs over the whole body; the list response carries no other "id" keys.
def json_ids_rev(+xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case Con{h, t}: json_ids_rev(t, Con{h, acc})

def json_id_at2(+ok: Bool, +s: String) -> Maybe<(String & String)>:
  match ok:
    case False{}: None{}
    case True{}: json_field_val(json_skip_ws(String.drop(s, 4n)))

def json_id_at(+s: String) -> Maybe<(String & String)>:
  json_id_at2(String.starts_with(s, "\"id\""), s)

def json_ids_go(s: String, +acc: List<&2, String>, mid: Maybe<(String & String)>, +cap: Nat) -> List<&2, String>:
  match s:
    case SNil{}: json_ids_rev(acc, Nil{})
    case SCon{Chr{c}, +t}:
      match mid:
        case None{}: json_ids_go(t, acc, json_id_at(t), cap)
        case Some{(v, _)}:
          match cap:
            case 0n: json_ids_rev(acc, Nil{})
            case 1n+p: json_ids_go(t, Con{v, acc}, json_id_at(t), p)

def json_ids(+json: String) -> List<&2, String>:
  json_ids_go(json, Nil{}, json_id_at(json), 64n)

# nextPageToken from a messages.list body (Wave 2). Server-opaque: cap at
# 1024 chars (hostile overlong input truncated, never a raw giant in the
# request line); absent/empty/malformed (strict parser rejects NUL, control
# chars, unquoted garbage) -> None = last page.
def mail_next_tok_some(+empty: Bool, +t: String) -> Maybe<&2, String>:
  match empty:
    case True{}: None{}
    case False{}: Some{str_trunc(t, 1024n)}

def mail_next_tok(+m: Maybe<&2, String>) -> Maybe<&2, String>:
  match m:
    case None{}: None{}
    case Some{t}: mail_next_tok_some(String.eq(t, ""), t)

def gmail_list_next(+body: String) -> Maybe<&2, String>:
  mail_next_tok(json_field(body, "nextPageToken"))

def gmail_list_parse2(+ok: Bool, +status: U32, +body: String) -> Result<&1,&1, U32 & String, (List<&2, String> & Maybe<&2, String>)>:
  match ok:
    case False{}: Fail{(status, "gmail: list failed")}
    case True{}: Done{(json_ids(body), gmail_list_next(body))}

def gmail_list_parse(rr: Result<&1,&1, U32 & String, (U32 & String)>) -> Result<&1,&1, U32 & String, (List<&2, String> & Maybe<&2, String>)>:
  match rr:
    case Fail{e}: Fail{e}
    case Done{(+status, body)}: gmail_list_parse2(U32.is_eq(status, 200), status, body)

# Find the value of the header named `name` in a message.get payload.
# Whitespace- and order-independent: at each position, check for a strict
# `"name": "<name>"` pair (name must EQUAL, not contain), then require
# `, "value": "<string>"` with strict string parsing. Malformed entries are
# skipped; the scan continues. Returns None when absent or malformed.
def json_header_here3(mv: Maybe<(String & String)>, +name: String) -> Bool:
  match mv:
    case None{}: False{}
    case Some{(v, _)}: String.eq(v, name)

def json_header_here2(+ok: Bool, +s: String, +name: String) -> Bool:
  match ok:
    case False{}: False{}
    case True{}: json_header_here3(json_field_val(json_skip_ws(String.drop(s, 6n))), name)

def json_header_at_here(+s: String, +name: String) -> Bool:
  json_header_here2(String.starts_with(s, "\"name\""), s, name)

def json_header_getvkey2(+ok: Bool, +s: String) -> Maybe<&2, String>:
  match ok:
    case False{}: None{}
    case True{}: json_field_pick(json_field_val(json_skip_ws(String.drop(s, 7n))))

def json_header_getvkey(+s: String) -> Maybe<&2, String>:
  json_header_getvkey2(String.starts_with(s, "\"value\""), s)

def json_header_getcomma2(+is_comma: Bool, +t: String) -> Maybe<&2, String>:
  match is_comma:
    case False{}: None{}
    case True{}: json_header_getvkey(json_skip_ws(t))

def json_header_getcomma(+s: String) -> Maybe<&2, String>:
  match s:
    case SNil{}: None{}
    case SCon{Chr{c}, t}: json_header_getcomma2(U32.is_eq(c, 44), t)

def json_header_getval2(mv: Maybe<(String & String)>) -> Maybe<&2, String>:
  match mv:
    case None{}: None{}
    case Some{(_, rest)}: json_header_getcomma(json_skip_ws(rest))

def json_header_getval(+s: String, +name: String) -> Maybe<&2, String>:
  json_header_getval2(json_field_val(json_skip_ws(String.drop(s, 6n))))

# Find the value of the header named `name` in a message.get payload.
# Whitespace- and order-independent: at each position, check for a strict
# `"name": "<name>"` pair (name must EQUAL, not contain), then require
# `, "value": "<string>"` with strict string parsing. The FIRST well-formed
# entry wins; an entry whose value fails strict parsing is SKIPPED (not
# fatal) and the scan continues. Returns None when absent or all malformed.
# (Wave 1 hardening: previously a malformed first entry masked a later
# well-formed duplicate, collapsing the whole header to absent.)
def json_header_best(+best: Maybe<&2, String>, mv: Maybe<&2, String>) -> Maybe<&2, String>:
  match best:
    case Some{_}: best
    case None{}: mv

# Non-recursive arm helper: parse this position's entry only when `"name"`
# matched here; otherwise keep the best-so-far. Keeps json_header_go as the
# sole recursive def (Bend forbids mutual recursion).
def json_header_arm(+s: String, +name: String, +best: Maybe<&2, String>, +here: Bool) -> Maybe<&2, String>:
  match here:
    case True{}: json_header_best(best, json_header_getval(s, name))
    case False{}: best

def json_header_go(+s: String, +name: String, +best: Maybe<&2, String>) -> Maybe<&2, String>:
  match s:
    case SNil{}: best
    case SCon{Chr{c}, +t}:
      json_header_go(t, name, json_header_arm(s, name, best, json_header_at_here(s, name)))

def json_header(+json: String, +name: String) -> Maybe<&2, String>:
  json_header_go(json, name, None{})

# ---------- header value unfolding (RFC 5322 obs-fold) ----------
# Any run of CR/LF/SP/TAB containing at least one CR or LF collapses to a
# single space, trimmed at the ends. Runs of spaces/tabs WITHOUT a newline
# are preserved verbatim, so well-formed values pass through byte-identical.
def str_rtrim_ws_char(+c: U32) -> String:
  match c:
    case 32: ""
    case 9: ""
    case 13: ""
    case 10: ""
    case _: Char.show(Chr{c})

def str_rtrim_ws_put(+c: U32, +r: String) -> String:
  match r:
    case SNil{}: str_rtrim_ws_char(c)
    case _: String.append(Char.show(Chr{c}), r)

def str_rtrim_ws(+s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{c}, +t}: str_rtrim_ws_put(c, str_rtrim_ws(t))

def hdr_unfold_sep(+acc: String) -> String:
  match acc:
    case SNil{}: ""
    case _: " "

# Single recursive def (Bend forbids mutual recursion, and a scrutinee bound
# via Chr{+c} cannot be re-matched, so every char class is an arm of the one
# `match c`): any run of CR/LF/SP/TAB containing a CR or LF collapses to one
# space, trimmed at the ends; WSP runs without a newline pass through
# verbatim.
def hdr_unfold_go(+s: String, +acc: String, +nl: Bool) -> String:
  match s:
    case SNil{}: acc
    case SCon{Chr{+c}, +t}:
      match c:
        case 13: hdr_unfold_go(t, str_rtrim_ws(acc), True{})
        case 10: hdr_unfold_go(t, str_rtrim_ws(acc), True{})
        case 32:
          match nl:
            case True{}: hdr_unfold_go(t, acc, True{})
            case False{}: hdr_unfold_go(t, String.append(acc, Char.show(Chr{c})), False{})
        case 9:
          match nl:
            case True{}: hdr_unfold_go(t, acc, True{})
            case False{}: hdr_unfold_go(t, String.append(acc, Char.show(Chr{c})), False{})
        case _:
          match nl:
            case True{}: hdr_unfold_go(t, String.append(String.append(acc, hdr_unfold_sep(acc)), Char.show(Chr{c})), False{})
            case False{}: hdr_unfold_go(t, String.append(acc, Char.show(Chr{c})), False{})

def hdr_unfold(+s: String) -> String:
  hdr_unfold_go(s, "", False{})

def gmail_meta_hdr(+body: String, +name: String) -> String:
  hdr_unfold(json_opt(json_header(body, name)))

def gmail_meta(+id: String, +body: String) -> (MailMeta & String):
  (MM{id, gmail_meta_hdr(body, "From"), gmail_meta_hdr(body, "Subject"), gmail_meta_hdr(body, "Date")},
   json_opt(json_field(body, "snippet")))

def gmail_get_parse2(+ok: Bool, +status: U32, +id: String, +body: String) -> Result<&1,&1, U32 & String, (MailMeta & String)>:
  match ok:
    case False{}: Fail{(status, "gmail: message read failed")}
    case True{}: Done{gmail_meta(id, body)}

def gmail_get_parse(rr: Result<&1,&1, U32 & String, (U32 & String)>, +id: String) -> Result<&1,&1, U32 & String, (MailMeta & String)>:
  match rr:
    case Fail{e}: Fail{e}
    case Done{(+status, body)}: gmail_get_parse2(U32.is_eq(status, 200), status, id, body)

# Read one message's metadata + snippet (read-only).
def http_status_put(+isd: Bool, +r: U32) -> U32:
  match isd:
    case False{}: 0
    case True{}: r

def http_status_digits(s: String, n: Nat, +acc: U32) -> U32:
  match s, n:
    case _, 0n: acc
    case SNil{}, _: 0
    case SCon{Chr{+c}, +t}, 1n+m:
      http_status_put(json_is_digit(c), http_status_digits(t, m, U32.add(U32.mul(acc, 10), U32.sub(c, 48))))

def http_status_sp_put(+is_sp: Bool, +t: String, +r: U32) -> U32:
  match is_sp:
    case False{}: r
    case True{}: http_status_digits(t, 3n, 0)

def http_status_sp(+s: String) -> U32:
  match s:
    case SNil{}: 0
    case SCon{Chr{+c}, +t}:
      http_status_sp_put(U32.is_eq(c, 32), t, http_status_sp(t))

def http_status(+resp: String) -> U32:
  http_status_sp(resp)

def tls_req_got(rr: Tls & String) -> IO(Result<&1,&1, U32 & String, (U32 & String)>):
  match rr:
    case (tls, body):
      +b2 = body
      tls_req_got2(http_resp_ok(b2), http_status(b2), tls, b2)

def tls_req_sent(sr: Tls & Result<&1,&1, U32 & String, Unit>) -> IO(Result<&1,&1, U32 & String, (U32 & String)>):
  match sr:
    case (tls, Fail{e}):
      do IO<Result<&1,&1, U32 & String, (U32 & String)>>:
        _u : Unit <- Tls.close(tls)
        IO.pure(Result<&1,&1, U32 & String, (U32 & String)>, Fail{e})
    case (tls, Done{_}):
      do IO<Result<&1,&1, U32 & String, (U32 & String)>>:
        rr : Tls & String <- tls_recv_all(tls)
        tls_req_got(rr)

def tls_req_conn(cr: Result<&1,&1, U32 & String, Tls>, +req: String) -> IO(Result<&1,&1, U32 & String, (U32 & String)>):
  match cr:
    case Fail{e}: IO.pure(Result<&1,&1, U32 & String, (U32 & String)>, Fail{e})
    case Done{tls}:
      do IO<Result<&1,&1, U32 & String, (U32 & String)>>:
        sr : Tls & Result<&1,&1, U32 & String, Unit> <- Tls.send(tls, req)
        tls_req_sent(sr)

# TLS request. Success returns (http_status, body); transport errors Fail.
def tls_req(+host: String, port: U32, +req: String) -> IO(Result<&1,&1, U32 & String, (U32 & String)>):
  do IO<Result<&1,&1, U32 & String, (U32 & String)>>:
    cr : Result<&1,&1, U32 & String, Tls> <- Tls.connect(host, port)
    tls_req_conn(cr, req)

# Plain-socket request (http:// endpoints only: localhost test backends).
def sock_req_got(rs: Sock & String) -> IO(Result<&1,&1, U32 & String, (U32 & String)>):
  match rs:
    case (sock, body):
      +b2 = body
      sock_req_got2(http_resp_ok(b2), http_status(b2), sock, b2)

def sock_req_sent(sr: Sock & Result<&1,&1, U32 & String, Unit>) -> IO(Result<&1,&1, U32 & String, (U32 & String)>):
  match sr:
    case (sock, Fail{e}):
      do IO<Result<&1,&1, U32 & String, (U32 & String)>>:
        _u : Unit <- Sock.close(sock)
        IO.pure(Result<&1,&1, U32 & String, (U32 & String)>, Fail{e})
    case (sock, Done{_}):
      do IO<Result<&1,&1, U32 & String, (U32 & String)>>:
        rs : Sock & String <- sock_recv_all(sock)
        sock_req_got(rs)

def sock_req_conn(cr: Result<&1,&1, U32 & String, Sock>, +req: String) -> IO(Result<&1,&1, U32 & String, (U32 & String)>):
  match cr:
    case Fail{e}: IO.pure(Result<&1,&1, U32 & String, (U32 & String)>, Fail{e})
    case Done{sock}:
      do IO<Result<&1,&1, U32 & String, (U32 & String)>>:
        sr : Sock & Result<&1,&1, U32 & String, Unit> <- Sock.send(sock, req)
        sock_req_sent(sr)

def sock_req(+host: String, port: U32, +req: String) -> IO(Result<&1,&1, U32 & String, (U32 & String)>):
  do IO<Result<&1,&1, U32 & String, (U32 & String)>>:
    cr : Result<&1,&1, U32 & String, Sock> <- Sock.connect(host, port)
    sock_req_conn(cr, req)

# ---------- Gmail API (read-only) ----------

# Exchange the refresh token for a short-lived access token.
# Returns (access_token, expires_in_ms). 401/invalid_grant -> caller maps to MAuthErr.
def gmail_refresh(+cid: String, +csec: String, +rtok: String) -> IO(Result<&1,&1, U32 & String, (String & Nat)>):
  do IO<Result<&1,&1, U32 & String, (String & Nat)>>:
    rr : Result<&1,&1, U32 & String, (U32 & String)> <- tls_req("oauth2.googleapis.com", 443,
      http_post_req("oauth2.googleapis.com", "/token",
        "Content-Type: application/x-www-form-urlencoded\r\n", gmail_token_body(cid, csec, rtok)))
    IO.pure(Result<&1,&1, U32 & String, (String & Nat)>, gmail_refresh_parse(rr))

def gmail_list(+token: String, +q: String, +ptok: String) -> IO(Result<&1,&1, U32 & String, (List<&2, String> & Maybe<&2, String>)>):
  do IO<Result<&1,&1, U32 & String, (List<&2, String> & Maybe<&2, String>)>>:
    rr : Result<&1,&1, U32 & String, (U32 & String)> <- tls_req("gmail.googleapis.com", 443, gmail_list_req(token, q, ptok))
    IO.pure(Result<&1,&1, U32 & String, (List<&2, String> & Maybe<&2, String>)>, gmail_list_parse(rr))

def gmail_get(+token: String, +id: String) -> IO(Result<&1,&1, U32 & String, (MailMeta & String)>):
  do IO<Result<&1,&1, U32 & String, (MailMeta & String)>>:
    rr : Result<&1,&1, U32 & String, (U32 & String)> <- tls_req("gmail.googleapis.com", 443, gmail_get_req(token, id))
    IO.pure(Result<&1,&1, U32 & String, (MailMeta & String)>, gmail_get_parse(rr, id))

# ---------- mail tile rendering ----------
# Renders into the reader tile rect (416,512,280,496) when mail is open.


