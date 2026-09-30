# shell.bend: Shell-OS composition in pure Bend (simplified).
# Profile sidebar, theme sidebar, main tile area with theme filtering.

# Item: a task/idea row. theme 0-3 are the classic themes; theme 4 is
# "saved" (articles saved from the reader). Saved items carry metadata:
#   note     — the user's annotation ("" for plain items)
#   saved_at — IO.now() ms timestamp of the save (0n for plain items)
#   url      — the article's source URL ("" for plain items)
# An item is "legacy" (plain) iff note=="" && saved_at==0n && url=="",
# and legacy items serialize to the exact historical "d|title" bytes.
type Item is Data:
  It{title: String, theme: U32, note: String, saved_at: Nat, url: String}

# A plain (non-saved) item constructor, for call sites that only know
# title+theme.
def item_plain(+title: String, +theme: U32) -> Item:
  It{title, theme, "", 0n, ""}

# ---------- profiles ----------
# Three hardcoded profiles; each owns its item file. The profile string in
# SSt only ever comes from profile_next (a closed cycle over the three
# literals below), so profile_file's filename literals are never derived
# from UI text — persistence paths stay hardcoded.
# (String.eq is Base 2.0.25's total string equality.)

def profile_next_go(+is_def: Bool, +is_work: Bool) -> String:
  match is_def:
    case True{}: "work"
    case False{}:
      match is_work:
        case True{}: "personal"
        case False{}: "default"

def profile_next(+p: String) -> String:
  profile_next_go(String.eq(p, "default"), String.eq(p, "work"))

def profile_file_go(+is_def: Bool, +is_work: Bool) -> String:
  match is_def:
    case True{}: "items.txt"
    case False{}:
      match is_work:
        case True{}: "items-work.txt"
        case False{}: "items-personal.txt"

def profile_file(+p: String) -> String:
  profile_file_go(String.eq(p, "default"), String.eq(p, "work"))

# ---------- item persistence ----------
# Items load from items.txt at startup: one `theme|title` per line, where
# theme is a digit (0=all-only, 1=home design, 2=gaming, 3=Nov trip).
# Falls back to hardcoded defaults if the file is missing or unreadable.

def default_items() -> List<&2, Item>:
  Con{It{"Inbox Zero", 0, "", 0n, ""},
  Con{It{"Sofa Ideas", 1, "", 0n, ""},
  Con{It{"GPU Deals", 2, "", 0n, ""},
  Con{It{"Flight LAX", 3, "", 0n, ""},
  Con{It{"Paint Colors", 1, "", 0n, ""},
  Con{It{"Speedrun VOD", 2, "", 0n, ""}, Nil{}}}}}}}

# Escape scheme for titles in items.txt (backlog #4, landed 2026-09-21):
#   '\' (92)  -> "\\"      (two chars)
#   LF  (10)  -> "\" + "n"
# Unescape: "\" + "n" -> LF, "\\" -> "\", "\" + anything-else -> keep both
# (a trailing lone '\' is kept as-is: legacy pre-escape files survive).
# Single self-recursive defs over SCon{Chr{c}, t}, tok_go-style: the
# unescaper carries an after-backslash Bool and matches the char FIRST,
# then the Bool param (params are always scrutable; a computed value or
# grandparent binder as scrutinee would fail typecheck).
def str_escape_go(s: String, acc: String) -> String:
  match s:
    case SNil{}: acc
    case SCon{Chr{c}, t}:
      match c:
        case 10: str_escape_go(t, String.append(acc, "\\n"))
        case 92: str_escape_go(t, String.append(acc, "\\\\"))
        case _: str_escape_go(t, String.append(acc, Char.show(Chr{c})))

def str_escape(+s: String) -> String:
  str_escape_go(s, "")

def str_unescape_go(s: String, esc: Bool, acc: String) -> String:
  match s:
    case SNil{}:
      match esc:
        case True{}: String.append(acc, "\\")
        case False{}: acc
    case SCon{Chr{c}, t}:
      match c:
        case 92:  # backslash
          match esc:
            case True{}: str_unescape_go(t, False{}, String.append(acc, "\\"))
            case False{}: str_unescape_go(t, True{}, acc)
        case 110:  # 'n'
          match esc:
            case True{}: str_unescape_go(t, False{}, String.append(acc, "\n"))
            case False{}: str_unescape_go(t, False{}, String.append(acc, "n"))
        case _:
          match esc:
            case True{}: str_unescape_go(t, False{}, String.append(String.append(acc, "\\"), Char.show(Chr{c})))
            case False{}: str_unescape_go(t, False{}, String.append(acc, Char.show(Chr{c})))

def str_unescape(+s: String) -> String:
  str_unescape_go(s, False{}, "")

# Parse one "d|title" line to a 0-or-1-element list (empty on malformed).
# (Bend match can't scrutinize computed values, so each computed step
# goes through a helper def that takes it as a param. Defs precede use.)
# Theme must be 0-4; other digits are rejected (malformed line -> skip).
# Theme 4 = saved articles (written by the save flow as "v2|..." lines).
def parse_item_theme_num(+theme: U32, +title: String) -> List<&2, Item>:
  match theme:
    case 0: Con{item_plain(title, 0), Nil{}}
    case 1: Con{item_plain(title, 1), Nil{}}
    case 2: Con{item_plain(title, 2), Nil{}}
    case 3: Con{item_plain(title, 3), Nil{}}
    case 4: Con{item_plain(title, 4), Nil{}}
    case _: Nil{}

def parse_item_digit(+is_dig: Bool, +c: Char, +title: String) -> List<&2, Item>:
  match is_dig:
    case True{}: parse_item_theme_num(U32.sub(Char.to_u32(c), 48), title)
    case False{}: Nil{}

def parse_item_char(+mc: Maybe<&2, Char>, +title: String) -> List<&2, Item>:
  match mc:
    case None{}: Nil{}
    case Some{c}: parse_item_digit(Char.is_digit(c), c, title)

def parse_item_len(+ok: Bool, +th_s: String, +title: String) -> List<&2, Item>:
  match ok:
    case True{}: parse_item_char(String.get(th_s, 0n), title)
    case False{}: Nil{}

def parse_item_theme(+th_s: String, +title: String) -> List<&2, Item>:
  parse_item_len(Nat.is_eq(String.length(th_s), 1n), th_s, title)

# HARDEN 2026-09-21: split on every '|' but REJOIN the tail with "|".
# Old code kept only the first title segment, silently dropping a '|...'
# suffix on reload. Now the single-digit theme stays the head and the
# whole rest (pipes included) is the title: pipe titles round-trip exact.
# ESCAPE 2026-09-21: the rejoined tail is str_unescape'd, so titles with
# embedded newlines / backslashes (escaped at serialize time) round-trip.
def parse_item_rest(+th_s: String, +rest: List<&2, String>) -> List<&2, Item>:
  match rest:
    case _ <> _:
      parse_item_theme(th_s, str_unescape(String.join(rest, "|")))
    case _: Nil{}

def parse_item_parts(+parts: List<&2, String>) -> List<&2, Item>:
  match parts:
    case th_s <> rest:
      parse_item_rest(th_s, rest)
    case _: Nil{}

# ---------- saved-article ("v2") field codec ----------
# v2 line: v2|4|<esc title>|<esc note>|<saved_at>|<esc url>
# Escapes: \ -> \\, | -> \|, newline -> \n. Split on unescaped '|'.
def v2_esc_go(s: String, acc: String) -> String:
  match s:
    case SNil{}: acc
    case SCon{Chr{c}, t}:
      match c:
        case 10: v2_esc_go(t, String.append(acc, "\\n"))
        case 92: v2_esc_go(t, String.append(acc, "\\\\"))
        case 124: v2_esc_go(t, String.append(acc, "\\|"))
        case _: v2_esc_go(t, String.append(acc, Char.show(Chr{c})))

def v2_esc(+s: String) -> String:
  v2_esc_go(s, "")

# Non-recursive classifiers (PreSt pattern): compute next state, no recursion.
def v2_unesc_next_esc(esc: Bool, c: U32) -> Bool:
  match esc, c:
    case True{}, _: False{}
    case False{}, 92: True{}
    case False{}, _: False{}

def v2_unesc_next_acc(esc: Bool, c: U32, acc: String) -> String:
  match esc, c:
    case True{}, 110: String.append(acc, "\n")
    case True{}, 124: String.append(acc, "|")
    case True{}, 92: String.append(acc, "\\")
    case True{}, ch: String.append(String.append(acc, "\\"), Char.show(Chr{ch}))
    case False{}, 92: acc
    case False{}, ch: String.append(acc, Char.show(Chr{ch}))

def v2_unesc_end(esc: Bool, acc: String) -> String:
  match esc:
    case True{}: String.append(acc, "\\")
    case False{}: acc

def v2_unesc_go(s: String, +esc: Bool, acc: String) -> String:
  match s:
    case SNil{}: v2_unesc_end(esc, acc)
    case SCon{Chr{+c}, t}:
      v2_unesc_go(t, v2_unesc_next_esc(esc, c), v2_unesc_next_acc(esc, c, acc))

def v2_unesc(+s: String) -> String:
  v2_unesc_go(s, False{}, "")

# Escape-aware split on '|': a backslash quotes the next char (the
# backslash is preserved so per-field v2_unesc can decode it).
# Non-recursive classifiers for v2_split (PreSt pattern).
def v2_split_next_esc(esc: Bool, c: U32) -> Bool:
  match esc, c:
    case True{}, _: False{}
    case False{}, 92: True{}
    case False{}, _: False{}

def v2_split_next_cur(esc: Bool, c: U32, cur: String) -> String:
  match esc, c:
    case True{}, ch: String.append(cur, String.append("\\", Char.show(Chr{ch})))
    case False{}, 92: cur
    case False{}, 124: ""
    case False{}, ch: String.append(cur, Char.show(Chr{ch}))

def v2_split_next_acc(esc: Bool, c: U32, cur: String, acc: List<&2, String>) -> List<&2, String>:
  match esc, c:
    case False{}, 124: List.append(&2, String, acc, Con{cur, Nil{}})
    case _, _: acc

def v2_split_go(s: String, +esc: Bool, +cur: String, acc: List<&2, String>) -> List<&2, String>:
  match s:
    case SNil{}: List.append(&2, String, acc, Con{cur, Nil{}})
    case SCon{Chr{+c}, t}:
      v2_split_go(t, v2_split_next_esc(esc, c), v2_split_next_cur(esc, c, cur), v2_split_next_acc(esc, c, cur, acc))

def v2_split_esc(+s: String) -> List<&2, String>:
  v2_split_go(s, False{}, "", Nil{})

def nat_digit_acc(+isd: Bool, +c: U32, +acc: Nat) -> Maybe<&2, Nat>:
  match isd:
    case True{}: Some{Nat.add(Nat.mul(acc, 10n), U32.to_nat(U32.sub(c, 48)))}
    case False{}: None{}

def nat_parse_go(s: String, macc: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match s, macc:
    case SNil{}, m: m
    case SCon{Chr{c}, t}, None{}: None{}
    case SCon{Chr{+c}, t}, Some{acc}:
      nat_parse_go(t, nat_digit_acc(Char.is_digit(Chr{c}), c, acc))

def nat_parse(+s: String) -> Maybe<&2, Nat>:
  nat_parse_go(s, Some{0n})

def parse_item_v2theme(+theme: U32, +title: String, +note: String, +sat: Nat, +url: String) -> List<&2, Item>:
  match theme:
    case 0: Con{It{title, 0, note, sat, url}, Nil{}}
    case 1: Con{It{title, 1, note, sat, url}, Nil{}}
    case 2: Con{It{title, 2, note, sat, url}, Nil{}}
    case 3: Con{It{title, 3, note, sat, url}, Nil{}}
    case 4: Con{It{title, 4, note, sat, url}, Nil{}}
    case _: Nil{}

def parse_item_v2meta(+sat: Maybe<&2, Nat>, +theme: U32, +title: String, +note: String, +url: String) -> List<&2, Item>:
  match sat:
    case None{}: Nil{}
    case Some{at}: parse_item_v2theme(theme, title, note, at, url)

def parse_item_v2len(+ok: Bool, +c: Char, +title: String, +note: String, +sat_s: String, +url: String) -> List<&2, Item>:
  match ok:
    case True{}: parse_item_v2meta(nat_parse(sat_s), U32.sub(Char.to_u32(c), 48), v2_unesc(title), v2_unesc(note), v2_unesc(url))
    case False{}: Nil{}

def parse_item_v2dig(+isd: Bool, +c: Char, +th_s: String, +title: String, +note: String, +sat_s: String, +url: String) -> List<&2, Item>:
  match isd:
    case False{}: Nil{}
    case True{}: parse_item_v2len(Nat.is_eq(String.length(th_s), 1n), c, title, note, sat_s, url)

def parse_item_v2th(+mc: Maybe<&2, Char>, +th_s: String, +title: String, +note: String, +sat_s: String, +url: String) -> List<&2, Item>:
  match mc:
    case None{}: Nil{}
    case Some{c}: parse_item_v2dig(Char.is_digit(c), c, th_s, title, note, sat_s, url)

# Exactly 6 fields: v2|theme|title|note|saved_at|url. Anything else is
# malformed and the line is skipped (fail clean).
def parse_item_v2fields(+fields: List<&2, String>) -> List<&2, Item>:
  match fields:
    case _ <> th_s <> title <> note <> sat_s <> url <> Nil{}:
      parse_item_v2th(String.get(th_s, 0n), th_s, title, note, sat_s, url)
    case _: Nil{}

# Simple append (direct recursion; avoids Base kind-param friction).
def parse_item_marker(+is_v2: Bool, +fields: List<&2, String>, +line: String) -> List<&2, Item>:
  match is_v2:
    case True{}: parse_item_v2fields(fields)
    case False{}: parse_item_parts(String.split(line, '|'))

def parse_item_dispatch(+fields: List<&2, String>, +line: String) -> List<&2, Item>:
  match fields:
    case h <> _:
      parse_item_marker(String.eq(h, "v2"), fields, line)
    case _: Nil{}

def parse_item_line(+line: String) -> List<&2, Item>:
  parse_item_dispatch(v2_split_esc(line), line)

# Dispatch: field 0 "v2" marks a saved-article line. Unambiguous because
# legacy themes are single digits 0-4, so field 0 can never be "v2" on a
# legacy line.
def append_item(+xs: List<&2, Item>, +ys: List<&2, Item>) -> List<&2, Item>:
  match xs:
    case Nil{}: ys
    case h <> t: Con{h, append_item(t, ys)}

def parse_items_go(+lines: List<&2, String>) -> List<&2, Item>:
  match lines:
    case Nil{}: Nil{}
    case l <> rest: append_item(parse_item_line(l), parse_items_go(rest))

def parse_items_fallback(+parsed: List<&2, Item>) -> List<&2, Item>:
  match parsed:
    case Nil{}: default_items()
    case it <> rest: Con{it, rest}

def parse_items(+lines: List<&2, String>) -> List<&2, Item>:
  parse_items_fallback(parse_items_go(lines))

def load_items_read(fr: File & Result<&1,&1, U32 & String, String>) -> IO(List<&2, Item>):
  (f2, rres) = fr
  match rres:
    case Fail{e}:
      do IO<List<&2, Item>>:
        _u : Unit <- File.close(f2)
        IO.pure(List<&2, Item>, default_items())
    case Done{text}:
      do IO<List<&2, Item>>:
        _u : Unit <- File.close(f2)
        IO.pure(List<&2, Item>, parse_items(String.lines(text)))

def load_items_opened(or_: Result<&1,&1, U32 & String, File>) -> IO(List<&2, Item>):
  match or_:
    case Fail{e}: IO.pure(List<&2, Item>, default_items())
    case Done{f}:
      do IO<List<&2, Item>>:
        fr : File & Result<&1,&1, U32 & String, String> <- File.read(f, 65536)
        load_items_read(fr)

def load_items_file(+path: String) -> IO(List<&2, Item>):
  do IO<List<&2, Item>>:
    or_ : Result<&1,&1, U32 & String, File> <- File.open(path, "r")
    load_items_opened(or_)

def load_items() -> IO(List<&2, Item>):
  load_items_file("items.txt")

# ---------- item write-back ----------
# Atomic: serialize to items.txt.tmp, then rename(2) over items.txt, so a
# crash can never leave a half-written items.txt. Both the native effect
# and the JS stub (fs.renameSync) rename atomically.
# (No `import Base` here: this file is concatenated AFTER font.bend.)

def filerename_raw(from: String, to: String) -> IO(Result<&1,&1, U32 & String, Unit>):
  import "./effs/file_rename.c"
  import "./effs/file_rename.js"

# fsync(2) a path — the durability gate in the write-back path (2026-09-21).
# After closing items.txt.tmp and BEFORE the rename: if fsync fails the
# caller does NOT rename, so a crash+reboot can never surface a half-synced
# items.txt. Durability is no longer process-death-only.
def filesync_raw(path: String) -> IO(Result<&1,&1, U32 & String, Unit>):
  import "./effs/file_sync.c"
  import "./effs/file_sync.js"

def save_items_renamed(rr: Result<&1,&1, U32 & String, Unit>) -> IO(Bool):
  match rr:
    case Fail{e}: IO.pure(Bool, False{})
    case Done{_}: IO.pure(Bool, True{})

# After a successful fsync: rename the synced tmp over items.txt.
# (Defined before save_items_wrote_res: defs precede use.)
def save_items_synced(sr: Result<&1,&1, U32 & String, Unit>) -> IO(Bool):
  match sr:
    case Fail{e}: IO.pure(Bool, False{})
    case Done{_}:
      do IO<Bool>:
        rr : Result<&1,&1, U32 & String, Unit> <- filerename_raw("items.txt.tmp", "items.txt")
        save_items_renamed(rr)

# Serialize one item as `theme|escaped-title\n`, then the whole list.
def item_is_plain(+note: String, +sat: Nat, +url: String) -> Bool:
  Bool.and(String.eq(note, ""), Bool.and(Nat.is_eq(sat, 0n), String.eq(url, "")))

def serialize_one_go(+ths: String, +title: String, plain: Bool, +note: String, +sat: Nat, +url: String) -> String:
  match plain:
    case True{}:
      String.append(String.append(ths, "|"), String.append(str_escape(title), nl_str()))
    case False{}:
      String.append("v2|", String.append(ths, String.append("|",
        String.append(v2_esc(title), String.append("|",
        String.append(v2_esc(note), String.append("|",
        String.append(Nat.show(sat), String.append("|",
        String.append(v2_esc(url), nl_str()))))))))))

def serialize_one(+it: Item) -> String:
  match it:
    case It{title, theme, note, sat, url}:
      serialize_one_go(U32.show(theme), title, item_is_plain(note, sat, url), note, sat, url)

# Legacy shape iff no saved metadata: plain items serialize to the exact
# historical "d|title" bytes, so files that never held a saved article are
# byte-identical after a save round-trip.

def serialize_items(+items: List<&2, Item>) -> String:
  match items:
    case Nil{}: ""
    case it <> rest:
      String.append(serialize_one(it), serialize_items(rest))

# After the tmp file is closed: fsync it, then rename over items.txt iff
# the write AND the fsync succeeded. On fsync failure we return False and
# do NOT rename (durability first: the old items.txt stays intact).
# (Defined before save_items_wrote: defs precede use.)
def save_items_wrote_res(f: File, +ok: Bool) -> IO(Bool):
  match ok:
    case True{}:
      do IO<Bool>:
        _u : Unit <- File.close(f)
        sr : Result<&1,&1, U32 & String, Unit> <- filesync_raw("items.txt.tmp")
        save_items_synced(sr)
    case False{}:
      do IO<Bool>:
        _u : Unit <- File.close(f)
        IO.pure(Bool, False{})

def save_items_wrote(wr: File & Result<&1,&1, U32 & String, Unit>) -> IO(Bool):
  (f2, rres) = wr
  match rres:
    case Fail{e}: save_items_wrote_res(f2, False{})
    case Done{_}: save_items_wrote_res(f2, True{})

def save_items_opened(or_: Result<&1,&1, U32 & String, File>, +items: List<&2, Item>) -> IO(Bool):
  match or_:
    case Fail{e}: IO.pure(Bool, False{})
    case Done{f}:
      do IO<Bool>:
        wr : File & Result<&1,&1, U32 & String, Unit> <- File.write(f, serialize_items(items))
        save_items_wrote(wr)

# ---------- profile-aware persistence ----------
# save_items_file generalizes the write-back path to an arbitrary item path
# with the SAME protocol: serialize to <path>.tmp, fsync the tmp, rename
# over <path>. save_items stays a thin wrapper over the default path so
# existing callers (writeback_main, tick save) keep working.

def save_items_synced_file(sr: Result<&1,&1, U32 & String, Unit>, +path: String, +tmp: String) -> IO(Bool):
  match sr:
    case Fail{e}: IO.pure(Bool, False{})
    case Done{_}:
      do IO<Bool>:
        rr : Result<&1,&1, U32 & String, Unit> <- filerename_raw(tmp, path)
        save_items_renamed(rr)

def save_items_wrote_res_file(f: File, +ok: Bool, +path: String, +tmp: String) -> IO(Bool):
  match ok:
    case True{}:
      do IO<Bool>:
        _u : Unit <- File.close(f)
        sr : Result<&1,&1, U32 & String, Unit> <- filesync_raw(tmp)
        save_items_synced_file(sr, path, tmp)
    case False{}:
      do IO<Bool>:
        _u : Unit <- File.close(f)
        IO.pure(Bool, False{})

def save_items_wrote_file(wr: File & Result<&1,&1, U32 & String, Unit>, +path: String, +tmp: String) -> IO(Bool):
  (f2, rres) = wr
  match rres:
    case Fail{e}: save_items_wrote_res_file(f2, False{}, path, tmp)
    case Done{_}: save_items_wrote_res_file(f2, True{}, path, tmp)

def save_items_opened_file(or_: Result<&1,&1, U32 & String, File>, +items: List<&2, Item>, +path: String, +tmp: String) -> IO(Bool):
  match or_:
    case Fail{e}: IO.pure(Bool, False{})
    case Done{f}:
      do IO<Bool>:
        wr : File & Result<&1,&1, U32 & String, Unit> <- File.write(f, serialize_items(items))
        save_items_wrote_file(wr, path, tmp)

def save_items_file(+items: List<&2, Item>, +path: String) -> IO(Bool):
  do IO<Bool>:
    or_ : Result<&1,&1, U32 & String, File> <- File.open(String.append(path, ".tmp"), "w")
    save_items_opened_file(or_, items, path, String.append(path, ".tmp"))

def save_items(+items: List<&2, Item>) -> IO(Bool):
  save_items_file(items, "items.txt")

# ---------- session restore (Wave 1, NEXT_WAVE2) ----------
# UI state persistence: focused tile, terminal scrollback offset, search
# panel, sidebar/article/tab selection, profile, gmail/ai open flags.
# Same durability protocol as items: session.txt.tmp + fsync + rename(2),
# so a crash can never leave a half-written session.txt. No secrets here:
# the file holds UI state only (search text, selection indexes, profile
# name); tokens/keys never enter SessSt.
#
# Format (line-based, key=value):
#   sess1
#   focus=2
#   sbo=0
#   ...
# String values use v2_esc (newline/backslash/pipe escaping, same as
# items v2 lines). The parser is TOTAL: missing/corrupt/truncated/garbage
# input (incl. NUL bytes, over-long lines, unknown fields, duplicate keys,
# wrong types) yields sess_default(); it can never crash the app.

type SessSt is Data:
  Sess{focus: U32, sbo: U32, search_open: Bool, search_q: String, search_sel: U32, sel: U32, page: U32, rart: U32, rscroll: U32, tab_idx: U32, profile: String, gmail_open: Bool, ai_open: Bool}

def sess_default() -> SessSt:
  Sess{0, 0, False{}, "", 0, 0, 0, 0, 0, 0, "default", False{}, False{}}

def sess_focus_of(+s: SessSt) -> U32:
  match s:
    case Sess{focus, _, _, _, _, _, _, _, _, _, _, _, _}: focus

def sess_sbo_of(+s: SessSt) -> U32:
  match s:
    case Sess{_, sbo, _, _, _, _, _, _, _, _, _, _, _}: sbo

def sess_search_open_of(+s: SessSt) -> Bool:
  match s:
    case Sess{_, _, open, _, _, _, _, _, _, _, _, _, _}: open

def sess_search_q_of(+s: SessSt) -> String:
  match s:
    case Sess{_, _, _, q, _, _, _, _, _, _, _, _, _}: q

def sess_search_sel_of(+s: SessSt) -> U32:
  match s:
    case Sess{_, _, _, _, sel, _, _, _, _, _, _, _, _}: sel

def sess_sel_of(+s: SessSt) -> U32:
  match s:
    case Sess{_, _, _, _, _, sel, _, _, _, _, _, _, _}: sel

def sess_page_of(+s: SessSt) -> U32:
  match s:
    case Sess{_, _, _, _, _, _, page, _, _, _, _, _, _}: page

def sess_rart_of(+s: SessSt) -> U32:
  match s:
    case Sess{_, _, _, _, _, _, _, rart, _, _, _, _, _}: rart

def sess_rscroll_of(+s: SessSt) -> U32:
  match s:
    case Sess{_, _, _, _, _, _, _, _, rscroll, _, _, _, _}: rscroll

def sess_tab_idx_of(+s: SessSt) -> U32:
  match s:
    case Sess{_, _, _, _, _, _, _, _, _, tab_idx, _, _, _}: tab_idx

def sess_profile_of(+s: SessSt) -> String:
  match s:
    case Sess{_, _, _, _, _, _, _, _, _, _, profile, _, _}: profile

def sess_gmail_open_of(+s: SessSt) -> Bool:
  match s:
    case Sess{_, _, _, _, _, _, _, _, _, _, _, gmail_open, _}: gmail_open

def sess_ai_open_of(+s: SessSt) -> Bool:
  match s:
    case Sess{_, _, _, _, _, _, _, _, _, _, _, _, ai_open}: ai_open

# ---------- session serialization (pure) ----------

def sess_b01(+b: Bool) -> String:
  match b:
    case True{}: "1"
    case False{}: "0"

def sess_kv_line(+k: String, +v: String) -> String:
  String.append(k, String.append(v, "\n"))

def sess_serialize(+s: SessSt) -> String:
  match s:
    case Sess{focus, sbo, search_open, search_q, search_sel, sel, page, rart, rscroll, tab_idx, profile, gmail_open, ai_open}:
      String.append("sess1\n",
      String.append(sess_kv_line("focus=", U32.show(focus)),
      String.append(sess_kv_line("sbo=", U32.show(sbo)),
      String.append(sess_kv_line("search_open=", sess_b01(search_open)),
      String.append(sess_kv_line("search_q=", v2_esc(search_q)),
      String.append(sess_kv_line("search_sel=", U32.show(search_sel)),
      String.append(sess_kv_line("sel=", U32.show(sel)),
      String.append(sess_kv_line("page=", U32.show(page)),
      String.append(sess_kv_line("rart=", U32.show(rart)),
      String.append(sess_kv_line("rscroll=", U32.show(rscroll)),
      String.append(sess_kv_line("tab_idx=", U32.show(tab_idx)),
      String.append(sess_kv_line("profile=", v2_esc(profile)),
      String.append(sess_kv_line("gmail_open=", sess_b01(gmail_open)),
      sess_kv_line("ai_open=", sess_b01(ai_open)))))))))))))))

# ---------- session parsing (pure, total) ----------

# Strict total decimal parse: any non-digit char poisons the whole value
# to 0 (never a partial prefix — hostile "12abc" must not read as 12).
# Saturates at 4294967295 instead of wrapping.
# Two passes, both directly recursive (no mutual recursion allowed):
# first validate every char, then fold. A single digit-char can never be
# matched directly (match cannot scrutinize computed values), hence the
# Bool-returning sess_is_digit used under Bool.and.
def sess_is_digit(+c: U32) -> Bool:
  Bool.and(Bool.not(U32.is_lt(c, 48)), U32.is_le(c, 57))

def sess_all_digits(+s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{Chr{c}, t}: Bool.and(sess_is_digit(c), sess_all_digits(t))

def sess_u32_step_eq5(+le5: Bool, +d: U32) -> U32:
  match le5:
    case True{}: U32.add(4294967290, d)
    case False{}: 4294967295

def sess_u32_step_eq(+is729: Bool, +d: U32) -> U32:
  match is729:
    case False{}: 4294967295
    case True{}: sess_u32_step_eq5(U32.is_le(d, 5), d)

def sess_u32_step_go(+lt: Bool, +acc: U32, +d: U32) -> U32:
  match lt:
    case True{}: U32.add(U32.mul(acc, 10), d)
    case False{}: sess_u32_step_eq(U32.is_eq(acc, 429496729), d)

def sess_u32_step(+acc: U32, +d: U32) -> U32:
  sess_u32_step_go(U32.is_lt(acc, 429496729), acc, d)

def sess_u32_go(+s: String, +acc: U32) -> U32:
  match s:
    case SNil{}: acc
    case SCon{Chr{c}, t}: sess_u32_go(t, sess_u32_step(acc, U32.sub(c, 48)))

def sess_u32_valid(+ok: Bool, +s: String) -> U32:
  match ok:
    case True{}: sess_u32_go(s, 0)
    case False{}: 0

def sess_u32(+s: String) -> U32:
  sess_u32_valid(sess_all_digits(s), s)

def sess_b01_parse(+s: String) -> Bool:
  String.eq(s, "1")

# Drop every CR (never legit in our format) so CRLF-edited files still
# parse. Directly recursive loop; the classifier is a non-recursive leaf
# (Bend forbids mutual recursion between user defs).
def sess_no_cr_acc(+is_cr: Bool, +acc: String, +c: U32) -> String:
  match is_cr:
    case True{}: acc
    case False{}: String.append(acc, Char.show(Chr{c}))

def sess_no_cr_go(s: String, +acc: String) -> String:
  match s:
    case SNil{}: acc
    case SCon{Chr{+c}, t}: sess_no_cr_go(t, sess_no_cr_acc(U32.is_eq(c, 13), acc, c))

def sess_no_cr(+s: String) -> String:
  sess_no_cr_go(s, "")

# Split on the FIRST '=' only: values may legitimately contain '=' (they
# are v2_esc-escaped, which leaves '=' alone). Threading (key, val, done):
# once done flips at the first '=', key freezes and every later char
# (including further '=') accumulates into val.
def sess_split_done(+done: Bool, +c: U32) -> Bool:
  Bool.or(done, U32.is_eq(c, 61))

def sess_split_key_eq(+is_eq: Bool, +key: String, +c: U32) -> String:
  match is_eq:
    case True{}: key
    case False{}: String.append(key, Char.show(Chr{c}))

def sess_split_key(+done: Bool, +key: String, +c: U32) -> String:
  match done:
    case True{}: key
    case False{}: sess_split_key_eq(U32.is_eq(c, 61), key, c)

def sess_split_val(+done: Bool, +val: String, +c: U32) -> String:
  match done:
    case True{}: String.append(val, Char.show(Chr{c}))
    case False{}: val

def sess_split_go(+s: String, +key: String, +val: String, +done: Bool) -> (String & String):
  match s:
    case SNil{}: (key, val)
    case SCon{Chr{+c}, t}: sess_split_go(t, sess_split_key(done, key, c), sess_split_val(done, val, c), sess_split_done(done, c))

def sess_split_line(+line: String) -> (String & String):
  sess_split_go(sess_no_cr(line), "", "", False{})

# String values: v2_unesc, then sanitize — drop control chars except TAB
# and LF (a literal NUL or other control byte from a hostile file must
# never reach the renderer), then cap the length so a hostile 1MB line
# cannot bloat restored state.
def sess_san_keep_lt(+lt: Bool, +c: U32) -> Bool:
  match lt:
    case False{}: True{}
    case True{}: Bool.or(U32.is_eq(c, 10), U32.is_eq(c, 9))

def sess_san_keep(+c: U32) -> Bool:
  sess_san_keep_lt(U32.is_lt(c, 32), c)

def sess_san_next(+keep: Bool, +acc: String, +c: U32) -> String:
  match keep:
    case True{}: String.append(acc, Char.show(Chr{c}))
    case False{}: acc

def sess_san_go(+s: String, +acc: String, +n: Nat) -> String:
  match s:
    case SNil{}: acc
    case SCon{Chr{+c}, t}:
      match n:
        case 0n: acc
        case 1n+m: sess_san_go(t, sess_san_next(sess_san_keep(c), acc, c), m)

def sess_san(+s: String, +cap: Nat) -> String:
  sess_san_go(s, "", cap)

def sess_str_parse(+s: String, +cap: Nat) -> String:
  sess_san(v2_unesc(s), cap)

# Field clamps: keep every restored value inside the range the renderers
# already assume at runtime (sel 0-4 are the real themes; focus 0-4 are
# the real tiles).
def sess_clamp_4_le(+le: Bool, +v: U32) -> U32:
  match le:
    case True{}: v
    case False{}: 0

def sess_clamp_4(+v: U32) -> U32:
  sess_clamp_4_le(U32.is_le(v, 4), v)

def sess_clamp_focus(+v: U32) -> U32:
  sess_clamp_4(v)

def sess_clamp_sel(+v: U32) -> U32:
  sess_clamp_4(v)

def sess_set_focus(+s: SessSt, +v: U32) -> SessSt:
  match s:
    case Sess{_, sbo, so, sq, ssel, sel, page, rart, rscroll, tab_idx, profile, go, ao}:
      Sess{sess_clamp_focus(v), sbo, so, sq, ssel, sel, page, rart, rscroll, tab_idx, profile, go, ao}

def sess_set_sbo(+s: SessSt, +v: U32) -> SessSt:
  match s:
    case Sess{focus, _, so, sq, ssel, sel, page, rart, rscroll, tab_idx, profile, go, ao}:
      Sess{focus, v, so, sq, ssel, sel, page, rart, rscroll, tab_idx, profile, go, ao}

def sess_set_search_open(+s: SessSt, +v: String) -> SessSt:
  match s:
    case Sess{focus, sbo, _, sq, ssel, sel, page, rart, rscroll, tab_idx, profile, go, ao}:
      Sess{focus, sbo, sess_b01_parse(v), sq, ssel, sel, page, rart, rscroll, tab_idx, profile, go, ao}

def sess_set_search_q(+s: SessSt, +v: String) -> SessSt:
  match s:
    case Sess{focus, sbo, so, _, ssel, sel, page, rart, rscroll, tab_idx, profile, go, ao}:
      Sess{focus, sbo, so, sess_str_parse(v, 256n), ssel, sel, page, rart, rscroll, tab_idx, profile, go, ao}

def sess_set_search_sel(+s: SessSt, +v: U32) -> SessSt:
  match s:
    case Sess{focus, sbo, so, sq, _, sel, page, rart, rscroll, tab_idx, profile, go, ao}:
      Sess{focus, sbo, so, sq, v, sel, page, rart, rscroll, tab_idx, profile, go, ao}

def sess_set_sel(+s: SessSt, +v: U32) -> SessSt:
  match s:
    case Sess{focus, sbo, so, sq, ssel, _, page, rart, rscroll, tab_idx, profile, go, ao}:
      Sess{focus, sbo, so, sq, ssel, sess_clamp_sel(v), page, rart, rscroll, tab_idx, profile, go, ao}

def sess_set_page(+s: SessSt, +v: U32) -> SessSt:
  match s:
    case Sess{focus, sbo, so, sq, ssel, sel, _, rart, rscroll, tab_idx, profile, go, ao}:
      Sess{focus, sbo, so, sq, ssel, sel, v, rart, rscroll, tab_idx, profile, go, ao}

def sess_set_rart(+s: SessSt, +v: U32) -> SessSt:
  match s:
    case Sess{focus, sbo, so, sq, ssel, sel, page, _, rscroll, tab_idx, profile, go, ao}:
      Sess{focus, sbo, so, sq, ssel, sel, page, v, rscroll, tab_idx, profile, go, ao}

def sess_set_rscroll(+s: SessSt, +v: U32) -> SessSt:
  match s:
    case Sess{focus, sbo, so, sq, ssel, sel, page, rart, _, tab_idx, profile, go, ao}:
      Sess{focus, sbo, so, sq, ssel, sel, page, rart, v, tab_idx, profile, go, ao}

def sess_set_tab_idx(+s: SessSt, +v: U32) -> SessSt:
  match s:
    case Sess{focus, sbo, so, sq, ssel, sel, page, rart, rscroll, _, profile, go, ao}:
      Sess{focus, sbo, so, sq, ssel, sel, page, rart, rscroll, v, profile, go, ao}

# Only the three known profiles survive a restore; anything else falls
# back to "default" (a hostile or hand-edited profile= value must not
# select an unexpected items file).
def sess_prof_validate_personal(+is_personal: Bool) -> String:
  match is_personal:
    case True{}: "personal"
    case False{}: "default"

def sess_prof_validate_go2(+is_work: Bool, +is_personal: Bool) -> String:
  match is_work:
    case True{}: "work"
    case False{}: sess_prof_validate_personal(is_personal)

def sess_prof_validate_go(+is_default: Bool, +p: String) -> String:
  match is_default:
    case True{}: "default"
    case False{}: sess_prof_validate_go2(String.eq(p, "work"), String.eq(p, "personal"))

def sess_validate_profile(+p: String) -> String:
  sess_prof_validate_go(String.eq(p, "default"), p)

def sess_set_profile(+s: SessSt, +v: String) -> SessSt:
  match s:
    case Sess{focus, sbo, so, sq, ssel, sel, page, rart, rscroll, tab_idx, _, go, ao}:
      Sess{focus, sbo, so, sq, ssel, sel, page, rart, rscroll, tab_idx, sess_validate_profile(sess_str_parse(v, 64n)), go, ao}

def sess_set_gmail_open(+s: SessSt, +v: String) -> SessSt:
  match s:
    case Sess{focus, sbo, so, sq, ssel, sel, page, rart, rscroll, tab_idx, profile, _, ao}:
      Sess{focus, sbo, so, sq, ssel, sel, page, rart, rscroll, tab_idx, profile, sess_b01_parse(v), ao}

def sess_set_ai_open(+s: SessSt, +v: String) -> SessSt:
  match s:
    case Sess{focus, sbo, so, sq, ssel, sel, page, rart, rscroll, tab_idx, profile, go, _}:
      Sess{focus, sbo, so, sq, ssel, sel, page, rart, rscroll, tab_idx, profile, go, sess_b01_parse(v)}

# Key dispatch: known keys map to 1-13, anything else to 0 (ignored).
# Duplicate keys: last wins (fold order). One def per String.eq level:
# match cannot scrutinize the computed Bool directly.
def sess_key_ai(+is_ai: Bool, +k: String) -> U32:
  match is_ai:
    case True{}: 13
    case False{}: 0

def sess_key_gmail(+is_gmail: Bool, +k: String) -> U32:
  match is_gmail:
    case True{}: 12
    case False{}: sess_key_ai(String.eq(k, "ai_open"), k)

def sess_key_profile(+is_profile: Bool, +k: String) -> U32:
  match is_profile:
    case True{}: 11
    case False{}: sess_key_gmail(String.eq(k, "gmail_open"), k)

def sess_key_tab_idx(+is_tab: Bool, +k: String) -> U32:
  match is_tab:
    case True{}: 10
    case False{}: sess_key_profile(String.eq(k, "profile"), k)

def sess_key_rscroll(+is_rs: Bool, +k: String) -> U32:
  match is_rs:
    case True{}: 9
    case False{}: sess_key_tab_idx(String.eq(k, "tab_idx"), k)

def sess_key_rart(+is_rart: Bool, +k: String) -> U32:
  match is_rart:
    case True{}: 8
    case False{}: sess_key_rscroll(String.eq(k, "rscroll"), k)

def sess_key_page(+is_page: Bool, +k: String) -> U32:
  match is_page:
    case True{}: 7
    case False{}: sess_key_rart(String.eq(k, "rart"), k)

def sess_key_sel(+is_sel: Bool, +k: String) -> U32:
  match is_sel:
    case True{}: 6
    case False{}: sess_key_page(String.eq(k, "page"), k)

def sess_key_search_sel(+is_ss: Bool, +k: String) -> U32:
  match is_ss:
    case True{}: 5
    case False{}: sess_key_sel(String.eq(k, "sel"), k)

def sess_key_search_q(+is_sq: Bool, +k: String) -> U32:
  match is_sq:
    case True{}: 4
    case False{}: sess_key_search_sel(String.eq(k, "search_sel"), k)

def sess_key_search_open(+is_so: Bool, +k: String) -> U32:
  match is_so:
    case True{}: 3
    case False{}: sess_key_search_q(String.eq(k, "search_q"), k)

def sess_key_sbo(+is_sbo: Bool, +k: String) -> U32:
  match is_sbo:
    case True{}: 2
    case False{}: sess_key_search_open(String.eq(k, "search_open"), k)

def sess_key_focus(+is_focus: Bool, +k: String) -> U32:
  match is_focus:
    case True{}: 1
    case False{}: sess_key_sbo(String.eq(k, "sbo"), k)

def sess_key_code(+k: String) -> U32:
  sess_key_focus(String.eq(k, "focus"), k)

def sess_apply_code(+code: U32, +s: SessSt, +v: String) -> SessSt:
  match code:
    case 1: sess_set_focus(s, sess_u32(v))
    case 2: sess_set_sbo(s, sess_u32(v))
    case 3: sess_set_search_open(s, v)
    case 4: sess_set_search_q(s, v)
    case 5: sess_set_search_sel(s, sess_u32(v))
    case 6: sess_set_sel(s, sess_u32(v))
    case 7: sess_set_page(s, sess_u32(v))
    case 8: sess_set_rart(s, sess_u32(v))
    case 9: sess_set_rscroll(s, sess_u32(v))
    case 10: sess_set_tab_idx(s, sess_u32(v))
    case 11: sess_set_profile(s, v)
    case 12: sess_set_gmail_open(s, v)
    case 13: sess_set_ai_open(s, v)
    case _: s

def sess_apply_kv(+s: SessSt, kv: (String & String)) -> SessSt:
  match kv:
    case (k, v): sess_apply_code(sess_key_code(k), s, v)

def sess_parse_lines(+lines: List<&2, String>, +s: SessSt) -> SessSt:
  match lines:
    case Nil{}: s
    case l <> rest: sess_parse_lines(rest, sess_apply_kv(s, sess_split_line(l)))

def sess_parse_magic(+ok: Bool, +rest: List<&2, String>) -> SessSt:
  match ok:
    case True{}: sess_parse_lines(rest, sess_default())
    case False{}: sess_default()

def sess_parse_head(+lines: List<&2, String>) -> SessSt:
  match lines:
    case Nil{}: sess_default()
    case magic <> rest: sess_parse_magic(String.eq(sess_no_cr(magic), "sess1"), rest)

def sess_parse(+text: String) -> SessSt:
  sess_parse_head(String.lines(text))

# ---------- session write-back (IO, same protocol as items) ----------

def save_session_synced_file(sr: Result<&1,&1, U32 & String, Unit>, +path: String, +tmp: String) -> IO(Bool):
  match sr:
    case Fail{e}: IO.pure(Bool, False{})
    case Done{_}:
      do IO<Bool>:
        rr : Result<&1,&1, U32 & String, Unit> <- filerename_raw(tmp, path)
        save_items_renamed(rr)

def save_session_wrote_res_file(f: File, +ok: Bool, +path: String, +tmp: String) -> IO(Bool):
  match ok:
    case True{}:
      do IO<Bool>:
        _u : Unit <- File.close(f)
        sr : Result<&1,&1, U32 & String, Unit> <- filesync_raw(tmp)
        save_session_synced_file(sr, path, tmp)
    case False{}:
      do IO<Bool>:
        _u : Unit <- File.close(f)
        IO.pure(Bool, False{})

def save_session_wrote_file(wr: File & Result<&1,&1, U32 & String, Unit>, +sess: SessSt, +path: String, +tmp: String) -> IO(Bool):
  (f2, rres) = wr
  match rres:
    case Fail{e}: save_session_wrote_res_file(f2, False{}, path, tmp)
    case Done{_}: save_session_wrote_res_file(f2, True{}, path, tmp)

def save_session_opened_file(or_: Result<&1,&1, U32 & String, File>, +sess: SessSt, +path: String, +tmp: String) -> IO(Bool):
  match or_:
    case Fail{e}: IO.pure(Bool, False{})
    case Done{f}:
      do IO<Bool>:
        wr : File & Result<&1,&1, U32 & String, Unit> <- File.write(f, sess_serialize(sess))
        save_session_wrote_file(wr, sess, path, tmp)

def save_session_file(+sess: SessSt, +path: String) -> IO(Bool):
  do IO<Bool>:
    or_ : Result<&1,&1, U32 & String, File> <- File.open(String.append(path, ".tmp"), "w")
    save_session_opened_file(or_, sess, path, String.append(path, ".tmp"))

def save_session(+sess: SessSt) -> IO(Bool):
  save_session_file(sess, "session.txt")

# ---------- session load (IO) ----------

def load_session_read(fr: File & Result<&1,&1, U32 & String, String>) -> IO(SessSt):
  (f2, rres) = fr
  match rres:
    case Fail{e}:
      do IO<SessSt>:
        _u : Unit <- File.close(f2)
        IO.pure(SessSt, sess_default())
    case Done{text}:
      do IO<SessSt>:
        _u : Unit <- File.close(f2)
        IO.pure(SessSt, sess_parse(text))

def load_session_opened(or_: Result<&1,&1, U32 & String, File>) -> IO(SessSt):
  match or_:
    case Fail{e}: IO.pure(SessSt, sess_default())
    case Done{f}:
      do IO<SessSt>:
        fr : File & Result<&1,&1, U32 & String, String> <- File.read(f, 65536)
        load_session_read(fr)

def load_session_file(+path: String) -> IO(SessSt):
  do IO<SessSt>:
    or_ : Result<&1,&1, U32 & String, File> <- File.open(path, "r")
    load_session_opened(or_)

def load_session() -> IO(SessSt):
  load_session_file("session.txt")

# ---------- view state, paging, reader navigation ----------
# Article HTML source (moved before ViewSt: viewst_new precomputes the
# wrapped lines, so reader_html_for must be defined first).
def reader_art_html(+a: U32) -> String:
  match a:
    case 0: "<h1>Shell-OS</h1><p>A pure Bend desktop shell. Reader, terminal, and tiles render from one program.</p><p>Themes group items automatically. Press 1-4 to filter, q to quit.</p>"
    case 1: "<h1>Pure Bend</h1><p>Every pixel of this shell is computed in Bend: the font rasterizer, the tile layout, the reader text extraction, and the terminal emulator.</p><p>Only files, sockets, the window, and the PTY are foreign effects.</p><p>The renderer builds a full 1024 by 1024 frame in 193 milliseconds natively. That is twenty one times faster than the same program running on Bun.</p><p>Text goes through a pure pipeline. HTML is tokenized, tags are stripped, the text is extracted and word wrapped, then each glyph is blitted from an 8 by 8 bitmap font.</p><p>The terminal is a pure state machine. It parses ANSI escape sequences, keeps a scrollback buffer, and renders its grid with the same blitter as everything else on screen.</p><p>Effects are named and minimal. A file read loads the item list at startup. The PTY effect spawns a shell. The window effect presents each frame. Everything else is pure Bend.</p><p>This article is long enough to scroll. Press Down to move through it and Up to come back. The scroll position resets when you switch articles.</p>"
    case 2: "<h1>Reader manual</h1><p>Press r to focus the reader. Up and Down scroll. n and p switch articles. Esc unfocuses.</p><p>Articles are parsed from HTML by the pure reader: tags stripped, text wrapped to the tile.</p>"
    case _: "<h1>Shell-OS</h1><p>Empty.</p>"

# Article 3 is the live feed (item #7): an empty feed shows the press-f
# placeholder; a fetched body runs through the same tokenize -> extract_text
# -> word_wrap pipeline as the demo articles. Articles 0-2 are untouched.
def reader_html_for_live(+feed: String) -> String:
  match feed:
    case SNil{}: "<p>Press f to fetch the live feed.</p>"
    case SCon{_, _}: feed

def reader_html_for(+rart: U32, +feed: String) -> String:
  match rart:
    case 3: reader_html_for_live(feed)
    case _: reader_art_html(rart)

# ViewSt packs the ephemeral view state (grid page, reader focus/article/
# scroll) so the app tick chain threads one value instead of four params.
# rlines caches the word-wrapped reader lines for the CURRENT (rart, feed).
# The reader pipeline (tokenize -> extract -> wrap) is O(n) per run but still
# costs ~15ms at 65KB; without the cache, every n/p key, every scroll step,
# and every frame repaint re-ran it (the 70s stall on the live feed). The
# cache is recomputed EAGERLY at the only two points where (rart, feed) can
# change (article switch, feed fetch); all other transitions thread it
# through, so it is always valid and render/scroll never re-run the pipeline.
type ViewSt is Data:
  VSt{page: U32, rfocus: Bool, rart: U32, rscroll: U32, rlines: List<&2, String>}

def reader_lines(+rart: U32, +feed: String) -> List<&2, String>:
  word_wrap(extract_text(tokenize(reader_html_for(rart, feed))), 30n)

def viewst_new(+feed: String) -> ViewSt:
  VSt{0, False{}, 0, 0, reader_lines(0, feed)}

def viewst_page(+vs: ViewSt) -> U32:
  match vs:
    case VSt{page, _, _, _, _}: page

def viewst_rfocus(+vs: ViewSt) -> Bool:
  match vs:
    case VSt{_, rfocus, _, _, _}: rfocus

# Grid pages: 3 rows x 2 cols = 6 items per page. The reader/terminal tiles
# sit at a FIXED y (512) below the 3-row grid, so they can never overflow
# the 1024px frame no matter how many items exist.
def page_count(+n: U32) -> U32:
  match n:
    case 0: 0
    case _: U32.div(U32.add(n, 5), 6)

def page_clamp_pick(+le: Bool, +page: U32, +max: U32) -> U32:
  match le:
    case True{}: page
    case False{}: max

def page_clamp_go(+page: U32, +max: U32) -> U32:
  page_clamp_pick(U32.is_le(page, max), page, max)

def page_clamp(+page: U32, +count: U32) -> U32:
  match count:
    case 0: 0
    case _: page_clamp_go(page, U32.sub(count, 1))

def drop_items(+xs: List<&2, Item>, +n: U32) -> List<&2, Item>:
  match xs, n:
    case _, 0: xs
    case Nil{}, _: Nil{}
    case _ <> t, m: drop_items(t, U32.sub(m, 1))

def take_items(+xs: List<&2, Item>, +n: U32) -> List<&2, Item>:
  match xs, n:
    case _, 0: Nil{}
    case Nil{}, _: Nil{}
    case h <> t, m: Con{h, take_items(t, U32.sub(m, 1))}

def page_dec_pick(+is_zero: Bool, +page: U32) -> U32:
  match is_zero:
    case True{}: 0
    case False{}: U32.sub(page, 1)

def page_dec(+page: U32) -> U32:
  page_dec_pick(U32.is_eq(page, 0), page)

def viewst_page_dec(+vs: ViewSt) -> ViewSt:
  match vs:
    case VSt{page, rfocus, rart, rscroll, rlines}:
      VSt{page_dec(page), rfocus, rart, rscroll, rlines}

def page_inc_pick(+le: Bool, +page: U32) -> U32:
  match le:
    case True{}: U32.add(page, 1)
    case False{}: page

def page_inc_go(+page: U32, +count: U32) -> U32:
  match count:
    case 0: page
    case _: page_inc_pick(U32.is_le(U32.add(page, 1), U32.sub(count, 1)), page)

def viewst_page_reset(+vs: ViewSt) -> ViewSt:
  match vs:
    case VSt{_, rfocus, rart, rscroll, rlines}: VSt{0, rfocus, rart, rscroll, rlines}

def viewst_focus_reader(+vs: ViewSt) -> ViewSt:
  match vs:
    case VSt{page, _, rart, rscroll, rlines}: VSt{page, True{}, rart, rscroll, rlines}

def viewst_unfocus_reader(+vs: ViewSt) -> ViewSt:
  match vs:
    case VSt{page, _, rart, rscroll, rlines}: VSt{page, False{}, rart, rscroll, rlines}

def viewst_eq_go3(+aeq: Bool, +seq: Bool) -> Bool:
  match aeq:
    case False{}: False{}
    case True{}: seq

def viewst_eq_go2(+f1: Bool, +f2: Bool, +aeq: Bool, +seq: Bool) -> Bool:
  match f1, f2:
    case True{}, True{}: viewst_eq_go3(aeq, seq)
    case False{}, False{}: viewst_eq_go3(aeq, seq)
    case _, _: False{}

def viewst_eq_go(+peq: Bool, +f1: Bool, +f2: Bool, +aeq: Bool, +seq: Bool) -> Bool:
  match peq:
    case False{}: False{}
    case True{}: viewst_eq_go2(f1, f2, aeq, seq)

def viewst_eq(+a: ViewSt, +b: ViewSt) -> Bool:
  match a, b:
    case VSt{p1, f1, a1, s1, _}, VSt{p2, f2, a2, s2, _}:
      viewst_eq_go(U32.is_eq(p1, p2), f1, f2, U32.is_eq(a1, a2), U32.is_eq(s1, s2))

# ---------- reader articles ----------
# Three sample articles; n/p switch, Up/Down scroll, Esc unfocuses.

def reader_n_arts() -> U32: 4

def reader_art_title(+a: U32) -> String:
  match a:
    case 0: "Shell-OS"
    case 1: "Pure Bend"
    case 2: "Reader manual"
    case 3: "Live feed"
    case _: "Shell-OS"

# Source URL captured when an article is saved (reader_art_url is used by the
# note editor; article 3 is the live feed whose URL is not a real article).
def reader_art_url(+a: U32) -> String:
  match a:
    case 0: "shell-os://articles/shell-os"
    case 1: "shell-os://articles/pure-bend"
    case 2: "shell-os://articles/reader-manual"
    case 3: "shell-os://articles/live-feed"
    case _: "shell-os://articles/shell-os"

# (reader_art_html / reader_html_for_live / reader_html_for are defined
# above, before the ViewSt section, so viewst_new can precompute lines.)

# list_len_str (U32) is defined in term.bend, before this file.
def drop_str(+xs: List<&2, String>, +n: U32) -> List<&2, String>:
  match xs, n:
    case _, 0: xs
    case Nil{}, _: Nil{}
    case _ <> t, m: drop_str(t, U32.sub(m, 1))

# Viewport shows 34 lines; max scroll keeps the last line reachable.
# scroll_max_lines reads the CACHED wrapped lines (O(lines)); the old
# scroll_max(rart, feed) re-ran the full reader pipeline per keypress.
def scroll_max_pick(+le: Bool, +n: U32) -> U32:
  match le:
    case True{}: 0
    case False{}: U32.sub(n, 34)

def scroll_max_lines(+rlines: List<&2, String>) -> U32:
  +n = list_len_str(rlines)
  scroll_max_pick(U32.is_le(n, 34), n)

def scroll_down_pick(+le: Bool, +cur: U32) -> U32:
  match le:
    case True{}: U32.add(cur, 1)
    case False{}: cur

def scroll_down_go(+cur: U32, +max: U32) -> U32:
  scroll_down_pick(U32.is_le(U32.add(cur, 1), max), cur)

def scroll_up_pick(+is_zero: Bool, +cur: U32) -> U32:
  match is_zero:
    case True{}: 0
    case False{}: U32.sub(cur, 1)

def scroll_up_go(+cur: U32) -> U32:
  scroll_up_pick(U32.is_eq(cur, 0), cur)

def scroll_go(+cur: U32, +up: Bool, +max: U32) -> U32:
  match up:
    case True{}: scroll_up_go(cur)
    case False{}: scroll_down_go(cur, max)

def viewst_scroll(+vs: ViewSt, +up: Bool) -> ViewSt:
  match vs:
    case VSt{page, rfocus, rart, rscroll, rlines}:
      VSt{page, rfocus, rart, scroll_go(rscroll, up, scroll_max_lines(rlines)), rlines}

def rart_next_pick(+le: Bool, +a: U32) -> U32:
  match le:
    case True{}: U32.add(a, 1)
    case False{}: a

def rart_next(+a: U32) -> U32:
  rart_next_pick(U32.is_le(U32.add(a, 1), U32.sub(reader_n_arts(), 1)), a)

def viewst_rart_next(+vs: ViewSt, +feed: String) -> ViewSt:
  match vs:
    case VSt{page, rfocus, rart, _, _}:
      +a2 = rart_next(rart)
      VSt{page, rfocus, a2, 0, reader_lines(a2, feed)}

def rart_prev_pick(+is_zero: Bool, +a: U32) -> U32:
  match is_zero:
    case True{}: 0
    case False{}: U32.sub(a, 1)

def rart_prev(+a: U32) -> U32:
  rart_prev_pick(U32.is_eq(a, 0), a)

def viewst_rart_prev(+vs: ViewSt, +feed: String) -> ViewSt:
  match vs:
    case VSt{page, rfocus, rart, _, _}:
      +a2 = rart_prev(rart)
      VSt{page, rfocus, a2, 0, reader_lines(a2, feed)}

# Feed fetch completed: if the body changed, the cached lines for article 3
# (live feed) are stale; recompute eagerly so the cache stays always-valid.
# (Split across two defs: Bend forbids matching a grandparent binder, so the
# vs destructure and the Bool branch live in separate defs.)
def viewst_feed_refresh3(+page: U32, +rfocus: Bool, +rart: U32, +rscroll: U32, +rlines: List<&2, String>, +feed2: String, same: Bool) -> ViewSt:
  match same:
    case True{}: VSt{page, rfocus, rart, rscroll, rlines}
    case False{}: VSt{page, rfocus, rart, rscroll, reader_lines(rart, feed2)}

def viewst_feed_refresh_go(+vs: ViewSt, +feed2: String, same: Bool) -> ViewSt:
  match vs:
    case VSt{page, rfocus, rart, rscroll, rlines}:
      viewst_feed_refresh3(page, rfocus, rart, rscroll, rlines, feed2, same)

def viewst_feed_refresh(+vs: ViewSt, +feed: String, +feed2: String) -> ViewSt:
  viewst_feed_refresh_go(vs, feed2, String.eq(feed, feed2))

# ---------- dynamic item tiles ----------

# sel 0 = all; sel 1-4 = theme filter; sel 5 = saved filter (theme 4).
# (Key '5' selects sel 5; see app.bend key_code_action.)
def item_shown(+theme: U32, +sel: U32) -> Bool:
  match sel:
    case 0: True{}
    case 5: U32.is_eq(theme, 4)
    case _: U32.is_eq(theme, sel)

def item_theme(+it: Item) -> U32:
  match it:
    case It{_, theme, _, _, _}: theme

def item_title(+it: Item) -> String:
  match it:
    case It{title, _, _, _, _}: title

def item_note(+it: Item) -> String:
  match it:
    case It{_, _, note, _, _}: note

def item_saved_at(+it: Item) -> Nat:
  match it:
    case It{_, _, _, sat, _}: sat

def item_url(+it: Item) -> String:
  match it:
    case It{_, _, _, _, url}: url

def filter_one_go(+shown: Bool, +it: Item) -> List<&2, Item>:
  match shown:
    case True{}: Con{it, Nil{}}
    case False{}: Nil{}

def filter_one(+it: Item, +sel: U32) -> List<&2, Item>:
  filter_one_go(item_shown(item_theme(it), sel), it)

def filter_items(+items: List<&2, Item>, +sel: U32) -> List<&2, Item>:
  match items:
    case Nil{}: Nil{}
    case it <> rest:
      append_item(filter_one(it, sel), filter_items(rest, sel))

def list_len_item(+xs: List<&2, Item>) -> U32:
  match xs:
    case Nil{}: 0
    case _ <> t: U32.add(1, list_len_item(t))

# Page-up clamps against the live filtered count (defined after
# filter_items/list_len_item: defs precede use).
def viewst_page_inc(+vs: ViewSt, +items: List<&2, Item>, +sel: U32) -> ViewSt:
  match vs:
    case VSt{page, rfocus, rart, rscroll, rlines}:
      VSt{page_inc_go(page, page_count(list_len_item(filter_items(items, sel)))), rfocus, rart, rscroll, rlines}

# Theme subtitle in dim color below the tile title.
def theme_name(+t: U32) -> String:
  match t:
    case 1: "home design"
    case 2: "gaming"
    case 3: "Nov trip"
    case 4: "saved"
    case _: "all"

def draw_theme_sub(+d: Nat, img: Image, +x: U32, +y: U32, +theme: U32, +th: Theme) -> Image:
  match th:
    case T{_, _, _, _, dim}:
      draw_text(theme_name(theme), d, img, U32.add(x, 8), U32.add(y, 24), dim)

# Saved articles render distinctly: a "SAVED" tag in the tile's accent
# color, bottom-right.
def draw_saved_tag_go(+d: Nat, img: Image, +x: U32, +y: U32, saved: Bool, +th: Theme) -> Image:
  match saved:
    case False{}: img
    case True{}:
      match th:
        case T{_, _, accent, _, _}:
          draw_text("SAVED", d, img, U32.add(x, 224), U32.add(y, 100), accent)

def draw_saved_tag(+d: Nat, img: Image, +x: U32, +y: U32, +theme: U32, +th: Theme) -> Image:
  draw_saved_tag_go(d, img, x, y, U32.is_eq(theme, 4), th)

# Grid: 2 columns, tiles 280x120, 16px gaps, origin (416, 104).
# (items first: Bend termination needs the shrinking arg first.)
def draw_item_tiles(+items: List<&2, Item>, +d: Nat, img: Image, +th: Theme, +idx: U32) -> Image:
  match items:
    case Nil{}: img
    case It{title, theme, _, _, _} <> rest:
      +x = U32.add(416, U32.mul(U32.mod(idx, 2), 296))
      +y = U32.add(104, U32.mul(U32.div(idx, 2), 136))
      +img2 = ui_tile(d, img, rect(x, y, 280, 120), title, th)
      +img3 = draw_theme_sub(d, img2, x, y, theme, th)
      +img4 = draw_saved_tag(d, img3, x, y, theme, th)
      draw_item_tiles(rest, d, img4, th, U32.add(idx, 1))

# Render shell for a given theme selection (0=all, 1=home design, 2=gaming, 3=Nov trip).
def is_sel0(+s: U32) -> Bool:
  match s:
    case 0: True{}
    case _: False{}

def is_sel1(+s: U32) -> Bool:
  match s:
    case 1: True{}
    case _: False{}

def is_sel2(+s: U32) -> Bool:
  match s:
    case 2: True{}
    case _: False{}

def is_sel3(+s: U32) -> Bool:
  match s:
    case 3: True{}
    case _: False{}

def is_sel5(+s: U32) -> Bool:
  match s:
    case 5: True{}
    case _: False{}

# --- Live tiles: reader article view + terminal viewport ---

# Draw up to n lines from a List<String> at (x, y), 12px pitch.
def draw_lines(+d: Nat, lines: List<&2, String>, img: Image, +x: U32, +y: U32, +n: U32, +color: U32) -> Image:
  match lines, n:
    case _, 0: img
    case Nil{}, _: img
    case l <> rest, m:
      draw_lines(d, rest, draw_text(l, d, img, x, y, color), x, U32.add(y, 14), U32.sub(m, 1), color)

# Clip-aware variant for the reader tile (Wave 4): article lines are
# unbounded user data. In the full-frame path rightward overflow was
# already erased by the later-drawn terminal panel, so clipping changes no
# visible pixel there; it makes the reader tile's paint confined to its
# rect, which dirty-region redraws require.
def draw_lines_clipped(+d: Nat, lines: List<&2, String>, img: Image, +x: U32, +y: U32, +n: U32, +color: U32, +kx0: U32, +ky0: U32, +kx1: U32, +ky1: U32) -> Image:
  match lines, n:
    case _, 0: img
    case Nil{}, _: img
    case l <> rest, m:
      draw_lines_clipped(d, rest, draw_text_clipped(l, d, img, x, y, color, kx0, ky0, kx1, ky1), x, U32.add(y, 14), U32.sub(m, 1), color, kx0, ky0, kx1, ky1)

def reader_sample_html() -> String:
  "<h1>Shell-OS</h1><p>A pure Bend desktop shell. Reader, terminal, and tiles render from one program.</p><p>Themes group items automatically. Press 1-4 to filter, q to quit.</p>"

def reader_title_base(+rart: U32) -> String:
  String.append("Reader ", String.append(U32.show(U32.add(rart, 1)), String.append("/", U32.show(reader_n_arts()))))

def reader_title(+rfocus: Bool, +rart: U32) -> String:
  match rfocus:
    case True{}: String.append(reader_title_base(rart), " [reading]")
    case False{}: reader_title_base(rart)

def shell_reader_tile(+d: Nat, img: Image, +r: Rect, +th: Theme, +vs: ViewSt) -> Image:
  match r, th, vs:
    case R{x, y, w, h}, T{_, _, _, _, dim}, VSt{_, rfocus, rart, rscroll, rlines}:
      +img2 = ui_tile(d, img, r, reader_title(rfocus, rart), th)
      draw_lines_clipped(d, drop_str(rlines, rscroll), img2, U32.add(x, 8), U32.add(y, 30), 34, dim, x, y, U32.add(x, w), U32.add(y, h))

def shell_term_demo() -> Term:
  +t0 = term_new()
  +t1 = term_line("$ bend --version", t0)
  +t2 = term_line("Bend 2.0.18", t1)
  +t3 = term_line("$ echo pure", t2)
  term_line("pure", t3)

def term_title_focus(+base: String, +tfocus: Bool) -> String:
  match tfocus:
    case True{}: String.append(base, " [typing]")
    case False{}: base

# Tab-aware terminal title, e.g. "Terminal [2/3]" or "Terminal [2/3] [typing]".
def term_title(+tfocus: Bool, +tab_idx: U32, +tab_count: U32) -> String:
  term_title_focus(String.append("Terminal [", String.append(U32.show(U32.add(tab_idx, 1)), String.append("/", String.append(U32.show(tab_count), "]")))), tfocus)

# Tab strip, e.g. " 1 *2  3" (active tab marked with *). Built by counting
# down n (U32 subtraction saturates) to avoid matching on a computed Bool.
def tab_strip_cell2(+is_active: Bool, +i: U32) -> String:
  match is_active:
    case True{}: String.append("*", U32.show(U32.add(i, 1)))
    case False{}: String.append(" ", U32.show(U32.add(i, 1)))

def tab_strip_cell(+i: U32, +active: U32) -> String:
  tab_strip_cell2(U32.is_eq(i, active), i)

def tab_strip_go(+n: Nat, +i: U32, +active: U32, +acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+m: tab_strip_go(m, U32.add(i, 1), active, String.append(acc, tab_strip_cell(i, active)))

def tab_strip(+active: U32, +count: U32) -> String:
  tab_strip_go(U32.to_nat(count), 0, active, "")

# Terminal title, with a [sb] marker while the scrollback viewer is
# engaged (offset > 0) so the user can see they are viewing history.
def term_title_sb(+base: String, +off: U32) -> String:
  match off:
    case 0: base
    case _: String.append(base, " [sb]")

def shell_term_tile(+d: Nat, img: Image, +r: Rect, +th: Theme, +t: Term, +tfocus: Bool, +tab_idx: U32, +tab_count: U32) -> Image:
  match r, th:
    case R{x, y, _, _}, T{_, _, _, text, _}:
      +img2 = ui_tile(d, img, r, term_title_sb(term_title(tfocus, tab_idx, tab_count), term_view_off(t)), th)
      +img3 = draw_text(tab_strip(tab_idx, tab_count), d, img2, U32.add(x, 8), U32.add(y, 32), text)
      term_render_vp(d, t, img3, U32.add(x, 8), U32.add(y, 54), 30n, 30n)

# Page indicator under the top bar, above the grid.
def page_label_text(+pg: U32, +count: U32) -> String:
  match count:
    case 0: "No items"
    case _: String.append("Page ", String.append(U32.show(U32.add(pg, 1)), String.append("/", U32.show(count))))

def draw_page_label(+d: Nat, img: Image, +th: Theme, +pg: U32, +count: U32) -> Image:
  match th:
    case T{_, _, _, text, _}:
      draw_text(page_label_text(pg, count), d, img, 416, 76, text)

# Reader and terminal tiles sit at a FIXED y=512 below the 3-row item grid:
# 512+496=1008 < 1024, so they can never be pushed off-screen.

# ---------- dirty-region rendering (Wave 4) ----------
#
# The frame is built from five paint-disjoint regions, drawn in this fixed
# order. shell_render (the full-frame path, kept as the fallback) runs every
# region; shell_render_dirty re-runs only the regions named in `mask` onto a
# cached frame. Correctness rests on two properties, both verified by the
# Xvfb pixel-equivalence tests:
#   1. Every region's paint is confined to its rect: all paints are absolute
#      overwrites (img.bend), ui_label clips text to its rect, and reader
#      lines are clipped to the reader tile. No region can paint into
#      another region's rect.
#   2. Every region redraw is self-clearing: it begins with a fill covering
#      its whole rect (panel/topbar fills, or the explicit items clear), so
#      no stale pixel from previous content can survive a redraw.
# Together these make a dirty redraw pixel-identical to the full-frame
# slice for the same state. Regions whose content did not change keep the
# cached frame's pixels untouched (structural sharing: only the redrawn
# region's quadtree nodes are rebuilt).

def dirty_top() -> U32: 1
def dirty_side() -> U32: 2
def dirty_items() -> U32: 4
def dirty_reader() -> U32: 8
def dirty_term() -> U32: 16
def dirty_all() -> U32: 31

def dirty_has(+mask: U32, +bit: U32) -> Bool:
  U32.is_ne(U32.and(mask, bit), 0)

# OR `bit` into the mask when `cond` holds.
def dirty_bit(+m: U32, +bit: U32, +cond: Bool) -> U32:
  match cond:
    case True{}: U32.or(m, bit)
    case False{}: m

# Top bar: full-width fill (self-clearing) + title text.
def shell_region_top(+d: Nat, img: Image, +th: Theme, +profile: String) -> Image:
  +img1 = fill_rect(d, img, 0, 0, 1024, 48, rgb(24, 28, 36))
  draw_text(String.append("Shell-OS :: ", profile), d, img1, 16, 16, rgb(230, 230, 230))

# Sidebars: both panel fills are self-clearing; labels clip to their panel.
def shell_region_side(+d: Nat, img: Image, +th: Theme, +sel_idx: U32, +items: List<&2, Item>, +hover: U32, +profile: String) -> Image:
  +img3 = ui_panel(d, img, rect(0, 48, 200, 976), th)
  +img4 = ui_label(d, img3, rect(0, 48, 200, 40), "Profile", th)
  +img5 = ui_label(d, img4, rect(0, 88, 200, 40), profile, th)
  +n_all = list_len_item(items)
  +n_home = list_len_item(filter_items(items, 1))
  +n_game = list_len_item(filter_items(items, 2))
  +n_trip = list_len_item(filter_items(items, 3))
  +n_saved = list_len_item(filter_items(items, 5))
  +img6 = ui_label(d, img5, rect(0, 140, 200, 40), String.append("Items: ", U32.show(n_all)), th)
  +img7 = ui_label(d, img6, rect(0, 180, 200, 40), String.append("home: ", U32.show(n_home)), th)
  +img8 = ui_label(d, img7, rect(0, 220, 200, 40), String.append("gaming: ", U32.show(n_game)), th)
  +img9 = ui_label(d, img8, rect(0, 260, 200, 40), String.append("trip: ", U32.show(n_trip)), th)
  +img9b = ui_label(d, img9, rect(0, 300, 200, 40), String.append("saved: ", U32.show(n_saved)), th)
  +img10 = ui_panel(d, img9b, rect(200, 48, 200, 976), th)
  +img11 = ui_label(d, img10, rect(200, 48, 200, 40), "Themes", th)
  +img12 = ui_button(d, img11, rect(208, 96, 184, 32), "all", th, is_sel0(sel_idx), ui_hovered(hover, 1))
  +img13 = ui_button(d, img12, rect(208, 132, 184, 32), "home design", th, is_sel1(sel_idx), ui_hovered(hover, 2))
  +img14 = ui_button(d, img13, rect(208, 168, 184, 32), "gaming", th, is_sel2(sel_idx), ui_hovered(hover, 3))
  +img15 = ui_button(d, img14, rect(208, 204, 184, 32), "Nov trip", th, is_sel3(sel_idx), ui_hovered(hover, 4))
  ui_button(d, img15, rect(208, 240, 184, 32), "saved", th, is_sel5(sel_idx), ui_hovered(hover, 5))

# Item grid + page label. The page label is bare text on the background, so
# the dirty variant clears the region rect first; tile panels are
# self-clearing and tile titles clip to their tile (ui_label).
def shell_region_items(+d: Nat, img: Image, +th: Theme, +sel_idx: U32, +items: List<&2, Item>, +vs: ViewSt) -> Image:
  +shown = filter_items(items, sel_idx)
  +count = page_count(list_len_item(shown))
  +pg = page_clamp(viewst_page(vs), count)
  +paged = take_items(drop_items(shown, U32.mul(pg, 6)), 6)
  +img2 = draw_item_tiles(paged, d, img, th, 0)
  draw_page_label(d, img2, th, pg, count)

# Items region rect: x 416..1024, y 48..496 (page label + 3 tile rows plus the
# right-edge strip to the canvas edge, which the full render covers only via
# its base fill; the strip must be re-cleared here for all-dirty parity).
def shell_dirty_items(+d: Nat, img: Image, +th: Theme, +sel_idx: U32, +items: List<&2, Item>, +vs: ViewSt) -> Image:
  shell_region_items(d, fill_rect(d, img, 416, 48, 608, 448, rgb(16, 18, 24)), th, sel_idx, items, vs)

# Side region rect: x 0..416, y 48..1024 (both sidebar panels plus the
# 16px strip between the themes panel and the item grid, base-fill-only
# in the full render).
def shell_dirty_side(+d: Nat, img: Image, +th: Theme, +sel_idx: U32, +items: List<&2, Item>, +hover: U32, +profile: String) -> Image:
  shell_region_side(d, fill_rect(d, img, 0, 48, 416, 976, rgb(16, 18, 24)), th, sel_idx, items, hover, profile)

def shell_region_reader(+d: Nat, img: Image, +th: Theme, +vs: ViewSt) -> Image:
  shell_reader_tile(d, img, rect(416, 512, 280, 496), th, vs)

# Terminal tile: ui_tile's panel fill is self-clearing; the tab strip and
# viewport grid are bounded by construction.
def shell_region_term(+d: Nat, img: Image, +th: Theme, +t: Term, +tfocus: Bool, +tab_idx: U32, +tab_count: U32) -> Image:
  shell_term_tile(d, img, rect(712, 512, 280, 496), th, t, tfocus, tab_idx, tab_count)

def shell_render(+d: Nat, +sel_idx: U32, +items: List<&2, Item>, +t: Term, +tfocus: Bool, +vs: ViewSt, +hover: U32, +tab_idx: U32, +tab_count: U32, +profile: String) -> Image:
  +th = theme_dark()
  +img = solid_tree(d, rgb(16, 18, 24))
  +i1 = shell_region_top(d, img, th, profile)
  +i2 = shell_region_side(d, i1, th, sel_idx, items, hover, profile)
  +i3 = shell_region_items(d, i2, th, sel_idx, items, vs)
  +i4 = shell_region_reader(d, i3, th, vs)
  shell_region_term(d, i4, th, t, tfocus, tab_idx, tab_count)

# Reader region rect: x 416..712, y 496..1024 (reader tile plus gutters to
# the items region above, the terminal tile, and the canvas bottom).
def shell_dirty_reader(+d: Nat, img: Image, +th: Theme, +vs: ViewSt) -> Image:
  shell_region_reader(d, fill_rect(d, img, 416, 496, 296, 528, rgb(16, 18, 24)), th, vs)

# Terminal region rect: x 696..1024, y 496..1024 (terminal tile plus gutters
# to the reader tile, the items region above, and the canvas edges).
def shell_dirty_term(+d: Nat, img: Image, +th: Theme, +t: Term, +tfocus: Bool, +tab_idx: U32, +tab_count: U32) -> Image:
  shell_region_term(d, fill_rect(d, img, 696, 496, 328, 528, rgb(16, 18, 24)), th, t, tfocus, tab_idx, tab_count)

# Conditional region application, in draw order (layering preserved).
def dirty_top_go(+go: Bool, +d: Nat, img: Image, +th: Theme, +profile: String) -> Image:
  match go:
    case True{}: shell_region_top(d, img, th, profile)
    case False{}: img

def dirty_side_go(+go: Bool, +d: Nat, img: Image, +th: Theme, +sel_idx: U32, +items: List<&2, Item>, +hover: U32, +profile: String) -> Image:
  match go:
    case True{}: shell_dirty_side(d, img, th, sel_idx, items, hover, profile)
    case False{}: img

def dirty_items_go(+go: Bool, +d: Nat, img: Image, +th: Theme, +sel_idx: U32, +items: List<&2, Item>, +vs: ViewSt) -> Image:
  match go:
    case True{}: shell_dirty_items(d, img, th, sel_idx, items, vs)
    case False{}: img

def dirty_reader_go(+go: Bool, +d: Nat, img: Image, +th: Theme, +vs: ViewSt) -> Image:
  match go:
    case True{}: shell_dirty_reader(d, img, th, vs)
    case False{}: img

def dirty_term_go(+go: Bool, +d: Nat, img: Image, +th: Theme, +t: Term, +tfocus: Bool, +tab_idx: U32, +tab_count: U32) -> Image:
  match go:
    case True{}: shell_dirty_term(d, img, th, t, tfocus, tab_idx, tab_count)
    case False{}: img

# Re-rasterize only the masked regions onto a cached frame, in draw order.
# Pixel-identical to the corresponding full-frame slices for the same state.
def shell_render_dirty(+d: Nat, frame: Image, +mask: U32, +th: Theme, +sel_idx: U32, +items: List<&2, Item>, +t: Term, +tfocus: Bool, +vs: ViewSt, +hover: U32, +tab_idx: U32, +tab_count: U32, +profile: String) -> Image:
  +i1 = dirty_top_go(dirty_has(mask, dirty_top()), d, frame, th, profile)
  +i2 = dirty_side_go(dirty_has(mask, dirty_side()), d, i1, th, sel_idx, items, hover, profile)
  +i3 = dirty_items_go(dirty_has(mask, dirty_items()), d, i2, th, sel_idx, items, vs)
  +i4 = dirty_reader_go(dirty_has(mask, dirty_reader()), d, i3, th, vs)
  dirty_term_go(dirty_has(mask, dirty_term()), d, i4, th, t, tfocus, tab_idx, tab_count)
