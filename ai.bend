# ---------- AI theme auto-grouping (accretive #4) ----------
# Config: $HOME/.config/shell-os/ai.conf, key=value lines:
#   endpoint=https://api.openai.com/v1/chat/completions
#   api_key=...
#   model=gpt-4o-mini
# The file must be owner-only (0600) like gmail.conf; otherwise it is
# treated as absent (fail closed, no AI UI).
# Privacy: the request carries item TITLES ONLY. Never paths, notes,
# terminal content, article bodies, or secrets.
# Flow: AIIdle --Enter--> AISending --IO--> AISugg --Enter--> apply+save
#                                                    --Esc--> AIIdle (files byte-identical)
# Suggestions are shown first; write-back needs explicit Enter on the
# suggestion panel. Cancel leaves items.txt byte-identical.

type AISugg is Data:
  AS{idx: U32, theme: U32}   # 1-based item index -> suggested theme 1..3

type AIInner is Data:
  AIUnknown{}      # config not yet checked
  AINone{}         # unconfigured: absent from UI, not an error
  AIIdle{}         # configured; Enter requests suggestions
  AISending{}      # request in flight
  AISuggSt{suggs: List<&2, AISugg>, cur: U32, applied: Bool}
  AIErr{}          # transport/parse/config error

type AISt is Data:
  AOff{}
  AOn{inner: AIInner}

# ---------- request building (titles only) ----------

def ai_sys_prompt() -> String:
  "You group todo item titles into themes. Reply with ONLY lines of the form N: T where N is the item number (1-based) and T is 1, 2, or 3 (1 home design, 2 gaming, 3 Nov trip). No other text."

def ai_item_groupable(+theme: U32) -> Bool:
  U32.is_lt(theme, 4)

def ai_titles_add(+groupable: Bool, +idx: U32, +title: String, +acc: String) -> String:
  match groupable:
    case False{}: acc
    case True{}:
      String.append(acc, String.append(U32.show(idx), String.append(". ", String.append(title, "\n"))))

# Titles of groupable items only (themes 1-3), numbered by 1-based position.
def ai_titles_go(+items: List<&2, Item>, +idx: U32, acc: String) -> String:
  match items:
    case Nil{}: acc
    case It{title, theme, _, _, _} <> rest:
      ai_titles_go(rest, U32.add(idx, 1), ai_titles_add(ai_item_groupable(theme), idx, title, acc))

def ai_titles(+items: List<&2, Item>) -> String:
  ai_titles_go(items, 1, "")

def ai_sugg_add(m: Maybe<(U32 & U32)>, acc: List<&2, AISugg>) -> List<&2, AISugg>:
  match m:
    case None{}: acc
    case Some{(n, t)}: List.append(&2, AISugg, acc, Con{AS{n, t}, Nil{}})

def ai_content(+body: String) -> Maybe<&2, String>:
  json_field(body, "content")

# ---------- endpoint parsing ----------
# "https://host[:port]/path" -> (True, host, port, path)
# "http://host[:port]/path"  -> (False, host, port, path)

# Endpoint MUST be https:// — plain http:// is rejected (security: API keys
# never travel in cleartext). Returns the rest after "https://".
def ai_ep_scheme_go(+is_https: Bool, +ep: String) -> Maybe<&2, String>:
  match is_https:
    case True{}: Some{String.drop(ep, 8n)}
    case False{}: None{}

def ai_ep_scheme(+ep: String) -> Maybe<&2, String>:
  ai_ep_scheme_go(String.starts_with(ep, "https://"), ep)

def ai_ep_parse4_go(+empty: Bool, +host: String, +port: U32, +path: String) -> Maybe<(String & U32 & String)>:
  match empty:
    case True{}: None{}
    case False{}: Some{(host, port, path)}

def ai_ep_parse4(+host: String, +port: U32, +path: String) -> Maybe<(String & U32 & String)>:
  ai_ep_parse4_go(String.eq(host, ""), host, port, path)

def ai_ep_portdef_go(+is_zero: Bool, +port: U32) -> U32:
  match is_zero:
    case False{}: port
    case True{}: 443

def ai_ep_portdef(+port: U32) -> U32:
  ai_ep_portdef_go(U32.is_eq(port, 0), port)

def ai_ep_parse3(hp2: String & U32, +path: String) -> Maybe<(String & U32 & String)>:
  match hp2:
    case (host, port): ai_ep_parse4(host, ai_ep_portdef(port), path)

def ai_send_req(+host: String, port: U32, +path: String, +key: String, +req_body: String) -> IO(Result<&1,&1, U32 & String, (U32 & String)>):
  tls_req(host, port, http_post_req(host, path,
    String.append("Content-Type: application/json\r\nAuthorization: Bearer ", String.append(key, "\r\n")), req_body))

def ai_send_parsed(mep: Maybe<(String & U32 & String)>, +key: String, +req_body: String) -> IO(Result<&1,&1, U32 & String, (U32 & String)>):
  match mep:
    case None{}: IO.pure(Result<&1,&1, U32 & String, (U32 & String)>, Fail{(0, "ai: bad endpoint (https:// required)")})
    case Some{(host, port, path)}: ai_send_req(host, port, path, key, req_body)

# POST the chat-completions request over TLS. Non-https endpoints are
# rejected before any socket is opened.
def ai_sugg_valid(+sugg: U32) -> Bool:
  U32.is_le(sugg, 3)

def ai_apply_item2(+groupable: Bool, +valid: Bool, +theme: U32, +title: String, +note: String, +saved_at: Nat, +url: String, +sugg: U32) -> Item:
  match groupable, valid:
    case True{}, True{}: It{title, sugg, note, saved_at, url}
    case _, _: It{title, theme, note, saved_at, url}

def ai_apply_item(+theme: U32, +title: String, +note: String, +saved_at: Nat, +url: String, +sugg: U32) -> Item:
  ai_apply_item2(ai_item_groupable(theme), ai_sugg_valid(sugg), theme, title, note, saved_at, url, sugg)

def ai_item_at2(+is_one: Bool, +it: Item, r: Maybe<&2, Item>) -> Maybe<&2, Item>:
  match is_one:
    case True{}: Some{it}
    case False{}: r

def ai_item_at(+items: List<&2, Item>, +idx: U32) -> Maybe<&2, Item>:
  match items:
    case Nil{}: None{}
    case +it <> rest:
      ai_item_at2(U32.is_eq(idx, 1), it, ai_item_at(rest, U32.sub(idx, 1)))

def ai_would_change2(+groupable: Bool, +same: Bool) -> U32:
  match groupable, same:
    case True{}, False{}: 1
    case _, _: 0

def ai_would_change_it(+it: Item, +t: U32) -> U32:
  match it:
    case It{_, theme, _, _, _}: ai_would_change2(ai_item_groupable(theme), U32.is_eq(theme, t))

def ai_would_change(+m: Maybe<&2, Item>, +t: U32) -> U32:
  match m:
    case None{}: 0
    case Some{it}: ai_would_change_it(it, t)

def ai_apply_count(+suggs: List<&2, AISugg>, +items: List<&2, Item>) -> U32:
  match suggs:
    case Nil{}: 0
    case AS{i, t} <> rest: U32.add(ai_would_change(ai_item_at(items, i), t), ai_apply_count(rest, items))

# ---------- AI overlay rendering ----------

def ai_item_title2(+it: Item) -> String:
  match it:
    case It{title, _, _, _, _}: title

def ai_item_title_go(+m: Maybe<&2, Item>) -> String:
  match m:
    case None{}: "?"
    case Some{it}: ai_item_title2(it)

def ai_item_title(+items: List<&2, Item>, +idx: U32) -> String:
  ai_item_title_go(ai_item_at(items, idx))

def ai_sugg_row2(+sel: Bool, +title: String, +t: U32) -> String:
  match sel:
    case True{}: String.append("> ", String.append(str_trunc(title, 30n), String.append(" -> ", theme_name(t))))
    case False{}: String.append("  ", String.append(str_trunc(title, 30n), String.append(" -> ", theme_name(t))))

def ai_sugg_row(+i: U32, +t: U32, +cur: U32, +idx: U32, +items: List<&2, Item>) -> String:
  ai_sugg_row2(U32.is_eq(cur, idx), ai_item_title(items, i), t)

def ai_sugg_rows(+suggs: List<&2, AISugg>, +cur: U32, +items: List<&2, Item>, +idx: U32) -> List<&2, String>:
  match suggs:
    case Nil{}: Nil{}
    case AS{i, t} <> rest:
      Con{ai_sugg_row(i, t, cur, idx, items), ai_sugg_rows(rest, cur, items, U32.add(idx, 1))}

def list_len_sugg(+xs: List<&2, AISugg>) -> U32:
  match xs:
    case Nil{}: 0
    case _ <> rest: U32.add(1, list_len_sugg(rest))

def ai_sugg_lines(+suggs: List<&2, AISugg>, +cur: U32, +items: List<&2, Item>) -> List<&2, String>:
  Con{String.append(U32.show(list_len_sugg(suggs)), " suggestions (Enter: apply, Esc: cancel)"),
    ai_sugg_rows(suggs, cur, items, 0)}

def ai_overlay_lines(+inner: AIInner, +items: List<&2, Item>) -> List<&2, String>:
  match inner:
    case AIIdle{}: Con{"AI theme grouping", Con{"",
      Con{"Enter: request suggestions", Con{"(sends item titles only)", Con{"Esc: close", Nil{}}}}}}
    case AISending{}: Con{"requesting suggestions…", Con{"(titles only, one attempt)", Nil{}}}
    case AISuggSt{suggs, cur, _}: ai_sugg_lines(suggs, cur, items)
    case AIErr{}: Con{"AI request failed", Con{"check ai.conf + network", Con{"Esc: close", Nil{}}}}
    case AIUnknown{}: Con{"checking config…", Nil{}}
    case AINone{}: Con{"", Nil{}}

def ai_overlay(+d: Nat, img: Image, +th: Theme, +inner: AIInner, +items: List<&2, Item>) -> Image:
  +img2 = ui_panel(d, img, rect(212, 150, 600, 420), th)
  +img3 = draw_text("AI grouping", d, img2, 228, 164, col_text())
  +img4 = fill_rect(d, img3, 213, 190, 598, 1, col_line())
  draw_lines(d, ai_overlay_lines(inner, items), img4, 228, 204, 20, col_body())
def json_escape_char(+c: U32) -> String:
  match c:
    case 34: "\\\""
    case 92: "\\\\"
    case 10: "\\n"
    case 13: "\\r"
    case 9: "\\t"
    case _: Char.show(Chr{c})

def json_escape_go(s: String, +acc: String) -> String:
  match s:
    case SNil{}: acc
    case SCon{Chr{+c}, +t}:
      json_escape_go(t, String.append(acc, json_escape_char(c)))

def json_escape(+s: String) -> String:
  json_escape_go(s, "")

def ai_req_body(+titles: String, +model: String) -> String:
  String.append("{\"model\":\"", String.append(json_escape(model),
    String.append("\",\"messages\":[{\"role\":\"system\",\"content\":\"", String.append(json_escape(ai_sys_prompt()),
      String.append("\"},{\"role\":\"user\",\"content\":\"", String.append(json_escape(titles),
        "\"]},\"temperature\":0}"))))))

# ---------- suggestion parsing ----------
# Strict "idx: theme" line parser. Positive indexes only (saturating at
# 999999), themes 1/2/3 only, trims space/tab/CR, skips prose and malformed
# lines, never throws. Cap: 64 parsed lines.

def ai_is_ws(+c: U32) -> Bool:
  Bool.or(U32.is_eq(c, 32), Bool.or(U32.is_eq(c, 9), U32.is_eq(c, 13)))

def ai_is_digit(+c: U32) -> Bool:
  Bool.and(U32.is_le(48, c), U32.is_le(c, 57))

def ai_ltrim_put(+ws: Bool, +c: U32, +t: String, r: String) -> String:
  match ws:
    case True{}: r
    case False{}: String.append(Char.show(Chr{c}), t)

def ai_ltrim(s: String) -> String:
  match s:
    case SNil{}: s
    case SCon{Chr{+c}, +t}: ai_ltrim_put(ai_is_ws(c), c, t, ai_ltrim(t))

def ai_rev_go(s: String, +acc: String) -> String:
  match s:
    case SNil{}: acc
    case SCon{Chr{c}, t}: ai_rev_go(t, String.append(Char.show(Chr{c}), acc))

def ai_trim(+s: String) -> String:
  ai_ltrim(ai_rev_go(ai_ltrim(ai_rev_go(s, "")), ""))

def ai_split_colon_at(+is_colon: Bool, +acc: String, +t: String, r: Maybe<(String & String)>) -> Maybe<(String & String)>:
  match is_colon:
    case True{}: Some{(acc, t)}
    case False{}: r

def ai_split_colon_go(s: String, +acc: String) -> Maybe<(String & String)>:
  match s:
    case SNil{}: None{}
    case SCon{Chr{+c}, +t}:
      ai_split_colon_at(U32.is_eq(c, 58), acc, t,
        ai_split_colon_go(t, String.append(acc, Char.show(Chr{c}))))

def ai_dig_sat(+le: Bool, +v: U32) -> U32:
  match le:
    case True{}: v
    case False{}: 999999

def ai_dig_step(+acc: U32, +d: U32) -> U32:
  ai_dig_sat(U32.is_le(U32.add(U32.mul(acc, 10), d), 999999), U32.add(U32.mul(acc, 10), d))

def ai_digits_end(+any: Bool, +acc: U32) -> Maybe<&2, U32>:
  match any:
    case True{}: Some{acc}
    case False{}: None{}

def ai_digits_at(+isd: Bool, +c: U32, +t: String, +acc: U32, r: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match isd:
    case True{}: r
    case False{}: None{}

def ai_digits_go(s: String, +acc: U32, +any: Bool) -> Maybe<&2, U32>:
  match s:
    case SNil{}: ai_digits_end(any, acc)
    case SCon{Chr{+c}, +t}:
      ai_digits_at(ai_is_digit(c), c, t, acc,
        ai_digits_go(t, ai_dig_step(acc, U32.sub(c, 48)), True{}))

def ai_parse_idx_pos(+is_zero: Bool, +n: U32) -> Maybe<&2, U32>:
  match is_zero:
    case True{}: None{}
    case False{}: Some{n}

def ai_parse_idx_nz(m: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match m:
    case None{}: None{}
    case Some{+n}: ai_parse_idx_pos(U32.is_eq(n, 0), n)

def ai_parse_idx_len_go(+ok: Bool, +s: String) -> Maybe<&2, U32>:
  match ok:
    case True{}: ai_parse_idx_nz(ai_digits_go(s, 0, False{}))
    case False{}: None{}

def ai_parse_idx_len(+s: String) -> Maybe<&2, U32>:
  ai_parse_idx_len_go(Nat.is_le(String.length(s), 6n), s)

def ai_parse_idx(+s: String) -> Maybe<&2, U32>:
  ai_parse_idx_len(ai_trim(s))

def ai_theme_ok(+c: U32) -> Bool:
  Bool.and(U32.is_le(49, c), U32.is_le(c, 51))

def ai_theme_at(+ok: Bool, +c: U32) -> Maybe<&2, U32>:
  match ok:
    case True{}: Some{U32.sub(c, 48)}
    case False{}: None{}

def ai_theme_single(+c: U32) -> Maybe<&2, U32>:
  ai_theme_at(ai_theme_ok(c), c)

def ai_theme_one_t(t: String, r: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match t:
    case SNil{}: r
    case _: None{}

def ai_theme_one(s: String) -> Maybe<&2, U32>:
  match s:
    case SNil{}: None{}
    case SCon{Chr{c}, t}: ai_theme_one_t(t, ai_theme_single(c))

def ai_parse_theme(+s: String) -> Maybe<&2, U32>:
  ai_theme_one(ai_trim(s))

def ai_line_both_i(mi: Maybe<&2, U32>, +t: U32) -> Maybe<(U32 & U32)>:
  match mi:
    case None{}: None{}
    case Some{i}: Some{(i, t)}

def ai_line_both_t(mi: Maybe<&2, U32>, mt: Maybe<&2, U32>) -> Maybe<(U32 & U32)>:
  match mt:
    case None{}: None{}
    case Some{t}: ai_line_both_i(mi, t)

def ai_line_parts(m: Maybe<(String & String)>) -> Maybe<(U32 & U32)>:
  match m:
    case None{}: None{}
    case Some{(l, r)}: ai_line_both_t(ai_parse_idx(l), ai_parse_theme(r))

# Char lookahead classification, mirroring json_cls_next/json_str_go:
# the _go def matches on the PRECOMPUTED (class, value) pair (a param —
# matching the char binder itself is illegal). 0 = newline, 1 = other,
# 2 = end of input.
def ai_ch_cls_c(+is_nl: Bool, +c: U32) -> (U32 & U32):
  match is_nl:
    case True{}: (0, 0)
    case False{}: (1, c)

def ai_ch_cls(s: String) -> (U32 & U32):
  match s:
    case SNil{}: (2, 0)
    case SCon{Chr{+c}, _}: ai_ch_cls_c(U32.is_eq(c, 10), c)

# Single self-recursive char scan: on '\n' the accumulated line is parsed;
# at end-of-input the final line is parsed too. Cap counts parsed lines.
# (Structural recursion on the string tail + precomputed (class, char) pair,
# triple-nested matches mirroring json_ids_go. `match s` is outermost so the
# SNil arm always parses the tail; when cap hit 0 the tail is necessarily ""
# which parses to None — a no-op.)
def ai_sugg_scan(s: String, line: String, acc: List<&2, AISugg>, cap: Nat, av: (U32 & U32)) -> List<&2, AISugg>:
  match s:
    case SNil{}: ai_sugg_add(ai_line_parts(ai_split_colon_go(line, "")), acc)
    case SCon{Chr{_}, +t}:
      match cap:
        case 0n: acc
        case 1n+m:
          match av:
            case (0, _):
              ai_sugg_scan(t, "", ai_sugg_add(ai_line_parts(ai_split_colon_go(line, "")), acc),
                m, ai_ch_cls(t))
            case (1, c):
              ai_sugg_scan(t, String.append(line, Char.show(Chr{c})), acc,
                Nat.add(1n, m), ai_ch_cls(t))
            case _: acc

def ai_parse_sugg(+text: String) -> List<&2, AISugg>:
  ai_sugg_scan(text, "", Nil{}, 64n, ai_ch_cls(text))

def ai_ep_hostpath_put(+is_slash: Bool, +acc: String, +t: String, r: String & String) -> (String & String):
  match is_slash:
    case True{}: (acc, String.append("/", t))
    case False{}: r

def ai_ep_hostpath_go(s: String, +acc: String) -> (String & String):
  match s:
    case SNil{}: (acc, "/")
    case SCon{Chr{+c}, +t}:
      ai_ep_hostpath_put(U32.is_eq(c, 47), acc, t, ai_ep_hostpath_go(t, String.append(acc, Char.show(Chr{c}))))

def ai_ep_hostpath(+rest: String) -> (String & String):
  ai_ep_hostpath_go(rest, "")

def ai_ep_port_put(+isd: Bool, +acc: U32, +r: U32) -> U32:
  match isd:
    case False{}: acc
    case True{}: r

def ai_ep_port_go(s: String, +acc: U32) -> U32:
  match s:
    case SNil{}: acc
    case SCon{Chr{+c}, +t}:
      ai_ep_port_put(json_is_digit(c), acc, ai_ep_port_go(t, U32.add(U32.mul(acc, 10), U32.sub(c, 48))))

def ai_ep_host_put(+is_colon: Bool, +acc: String, +t: String, r: String & U32) -> (String & U32):
  match is_colon:
    case True{}: (acc, ai_ep_port_go(t, 0))
    case False{}: r

def ai_ep_host_go(s: String, +acc: String) -> (String & U32):
  match s:
    case SNil{}: (acc, 0)
    case SCon{Chr{+c}, +t}:
      ai_ep_host_put(U32.is_eq(c, 58), acc, t, ai_ep_host_go(t, String.append(acc, Char.show(Chr{c}))))

# ---------- endpoint dispatch (https-only) ----------

def ai_ep_hostsplit(+hostport: String) -> (String & U32):
  ai_ep_host_go(hostport, "")

def ai_ep_parse2(hp: String & String) -> Maybe<(String & U32 & String)>:
  match hp:
    case (hostport, path): ai_ep_parse3(ai_ep_hostsplit(hostport), path)

def ai_ep_parse_go(+ms: Maybe<&2, String>) -> Maybe<(String & U32 & String)>:
  match ms:
    case None{}: None{}
    case Some{rest}: ai_ep_parse2(ai_ep_hostpath(rest))

def ai_ep_parse(+ep: String) -> Maybe<(String & U32 & String)>:
  ai_ep_parse_go(ai_ep_scheme(ep))

def ai_send(+ep: String, +key: String, +req_body: String) -> IO(Result<&1,&1, U32 & String, (U32 & String)>):
  ai_send_parsed(ai_ep_parse(ep), key, req_body)

# ---------- apply suggestions ----------

def ai_sugg_put(+eq: Bool, +t: U32, +r: U32) -> U32:
  match eq:
    case True{}: t
    case False{}: r

def ai_sugg_for(+suggs: List<&2, AISugg>, +idx: U32) -> U32:
  match suggs:
    case Nil{}: 0
    case AS{i, t} <> rest:
      ai_sugg_put(U32.is_eq(i, idx), t, ai_sugg_for(rest, idx))

def ai_apply_go(+items: List<&2, Item>, +suggs: List<&2, AISugg>, +idx: U32, acc: List<&2, Item>) -> List<&2, Item>:
  match items:
    case Nil{}: acc
    case It{title, theme, note, saved_at, url} <> rest:
      ai_apply_go(rest, suggs, U32.add(idx, 1),
        List.append(&2, Item, acc, Con{ai_apply_item(theme, title, note, saved_at, url, ai_sugg_for(suggs, idx)), Nil{}}))

def ai_apply(+items: List<&2, Item>, +suggs: List<&2, AISugg>) -> List<&2, Item>:
  ai_apply_go(items, suggs, 1, Nil{})

