# app.bend — interactive Shell-OS on Base App/Window.
# Requires font, img, ui, shell, pty concatenated BEFORE this file.
# (Our Image IS Base's Image — Pix/Qua — so the renderer plugs into
# Window.frame with zero conversion.)
#
# Interaction model: the state caches its rendered frame, so `view` is O(1)
# and App.run's per-frame view call costs nothing. `tick` rebuilds the frame
# only when something visible actually changes.
#
# Controls: click a theme button, press 1-4, Esc/q or window-close to quit.
# Press t to focus the terminal (keys go to the shell), Esc to unfocus.
# Press a to append an item (saved to items.txt).
#
# Affinity note (hard-won): in do-blocks, a pure `x : T = ...` bind consumes
# its inputs affinely, so two consecutive pure binds can't reuse one value;
# move any multi-use math into a pure helper def where `+` params are freely
# reusable. `+` on a `<-` bind does NOT make it reusable in later
# pure binds. Pure pair-destructuring `(a, b) = x` is ILLEGAL inside
# do-blocks; use a helper def that matches on the pair outside the block.
# A match cannot scrutinize a computed value, a local binder, or a second
# param after matching the first: give each its own def.

# Terminal tabs (#5). One Tab per shell: its pty handle (or NoPty when the
# spawn failed) plus its terminal emulator state. The tab list always holds
# >= 1 tab; closing the last tab is a no-op (see shell_tick_closetab_go).
# Profiles agent: per-tab working directory / env would ride in this type.
# Reader agent: per-tab reader state would ride here too.
type Tab is Data:
  TTab{pty: MaybePty, term: Term}

# AccSt: accumulator state for the four accretive features.
#   search_q/sel/open  universal-search overlay
#   gmail_st           Gmail read-only tile (MOff when hidden)
#   ai_st              AI theme grouping (AOff when hidden)
#   note               saved-article note editor; NCommit is transient (the IO
#                      preamble commits it and resets to NOff in the same tick)
#   save_req           AI apply requested (consumed by the IO preamble)
#   accd               "acc changed": set by EVERY acc mutation; tick_rebuild
#                      ORs it into the rebuild decision and clears it, so
#                      panels always repaint (the main need heuristic cannot
#                      see acc changes)
#   search_go          pending search jump (consumed by acc_apply_go)
type NoteSt is Data:
  NOff{}
  NEdit{title: String, url: String, text: String}
  NCommit{title: String, url: String, text: String}

# Command palette state (Wave 3). Declared before AccSt because AccSt embeds it.
type PalSt is Data:
  Pal{q: String, open: Bool, sel: U32, fire: U32}

type PalAct is Data:
  PAct{key: U32, label: String, desc: String}

type HelpSt is Data:
  HOff{}
  HOn{ctx: U32}

type AccSt is Data:
  Acc{search_q: String, search_open: Bool, search_sel: U32, gmail_st: MailSt, ai_st: AISt, note: NoteSt, save_req: Bool, accd: Bool, search_go: Maybe<&2, SearchHit>, pal: PalSt, help: HelpSt}

type ShellSt is Data:
  SSt{sel: U32, d: Nat, items: List<&2, Item>, frame: Image, tabs: List<&2, Tab>, tab_idx: U32, tfocus: Bool, vs: ViewSt, entry: String, entry_mode: U32, mx: U32, my: U32, hover: U32, profile: String, feed: String, acc: AccSt}

# SSt is 15 fields. Wave-2 (#5 terminal tabs) replaced the single
# `pty: MaybePty, term: Term` with `tabs: List<&2, Tab>, tab_idx: U32`:
# every shell lives in a Tab; tab_idx selects the active one.
# Wave-2 (#3 real profiles) added `profile: String`: the active profile
# name ("default" | "work" | "personal"); each profile owns its item file
# (see profile_file in shell.bend). Press P to cycle.
# Wave-2 note (reader agent): PRESERVE the mx/my/hover fields, the
# tabs/tab_idx fields, AND the profile field.
# mx, my = last mouse position in window pixels (from Move events).
# hover  = hovered theme-button target: 0=none, 1=all, 2=home, 3=gaming, 4=trip.
# Only hover CHANGES trigger a frame rebuild (see tick_need); raw mouse
# position never does, so mouse-move floods can't stutter the app.

def term_dead() -> Term:
  term_line("PTY unavailable: shell spawn failed.", term_new())

def tab_pty(+tab: Tab) -> MaybePty:
  match tab:
    case TTab{pty, _}: pty

def tab_term(+tab: Tab) -> Term:
  match tab:
    case TTab{_, term}: term

def tabs_count(+tabs: List<&2, Tab>) -> U32:
  match tabs:
    case Nil{}: 0
    case _ <> rest: U32.add(1, tabs_count(rest))

# Out-of-range index: dead placeholder tab (defensive; the tick chain keeps
# tab_idx clamped, so this never renders).
def tabs_get(+tabs: List<&2, Tab>, +idx: U32) -> Tab:
  match tabs:
    case Nil{}: TTab{NoPty{}, term_dead()}
    case t <> rest:
      match idx:
        case 0: t
        case _: tabs_get(rest, U32.sub(idx, 1))

def tabs_set(+tabs: List<&2, Tab>, +idx: U32, +tab: Tab) -> List<&2, Tab>:
  match tabs:
    case Nil{}: Nil{}
    case t <> rest:
      match idx:
        case 0: Con{tab, rest}
        case _: Con{t, tabs_set(rest, U32.sub(idx, 1), tab)}

def tabs_append(+tabs: List<&2, Tab>, +tab: Tab) -> List<&2, Tab>:
  match tabs:
    case Nil{}: Con{tab, Nil{}}
    case t <> rest: Con{t, tabs_append(rest, tab)}

def tabs_remove_at(+tabs: List<&2, Tab>, +idx: U32) -> List<&2, Tab>:
  match tabs:
    case Nil{}: Nil{}
    case t <> rest:
      match idx:
        case 0: rest
        case _: Con{t, tabs_remove_at(rest, U32.sub(idx, 1))}

# Wrap-around tab cycling: next past the last wraps to 0, prev before the
# first wraps to the last. Empty list -> 0 (defensive).
def tab_next_pick(+nxt: U32, +lt: Bool) -> U32:
  match lt:
    case True{}: nxt
    case False{}: 0

def tab_next_go(+nxt: U32, +count: U32) -> U32:
  tab_next_pick(nxt, U32.is_lt(nxt, count))

def tab_next_idx(+idx: U32, +count: U32) -> U32:
  match count:
    case 0: 0
    case _: tab_next_go(U32.add(idx, 1), count)

def tab_prev_pick(+is_zero: Bool, +idx: U32, +count: U32) -> U32:
  match is_zero:
    case True{}: U32.sub(count, 1)
    case False{}: U32.sub(idx, 1)

def tab_prev_idx(+idx: U32, +count: U32) -> U32:
  match count:
    case 0: 0
    case _: tab_prev_pick(U32.is_eq(idx, 0), idx, count)

def tab_idx_clamp_pick(+lt: Bool, +idx: U32, +count: U32) -> U32:
  match lt:
    case True{}: idx
    case False{}: U32.sub(count, 1)

def tab_idx_clamp(+idx: U32, +count: U32) -> U32:
  match count:
    case 0: 0
    case _: tab_idx_clamp_pick(U32.is_lt(idx, count), idx, count)

# Draw the entry bar overlay when in entry mode (entry_mode != 0)
# entry_mode: 1-4=add (theme=mode-1), 5=edit
def entry_mode_label(entry_mode: U32) -> String:
  match entry_mode:
    case 0: ""
    case 1: "ADD [0]"
    case 2: "ADD [1]"
    case 3: "ADD [2]"
    case 4: "ADD [3]"
    case 6: "NOTE"
    case _: "EDIT"

# Label color: orange for ADD modes, teal for EDIT.
def entry_label_color(entry_mode: U32) -> U32:
  match entry_mode:
    case 5: rgb(120, 220, 200)
    case _: rgb(255, 200, 100)

# Block cursor: filled 8x20 rect at the end of the typed text (entries are
# input-capped at 64 chars, so the cursor always lands inside the bar).
def draw_entry_cursor(+d: Nat, img: Image, +entry: String) -> Image:
  +cx = U32.add(160, U32.mul(8, U32.from_nat(String.length(entry))))
  fill_rect(d, img, cx, 986, 8, 20, rgb(230, 230, 230))

# Empty entry shows a dimmed placeholder; non-empty shows text + block cursor.
def draw_entry_text_go(+d: Nat, img: Image, +entry: String, is_empty: Bool) -> Image:
  match is_empty:
    case True{}:
      draw_text("type a title...", d, img, 160, 988, rgb(110, 114, 128))
    case False{}:
      +t1 = draw_text(entry, d, img, 160, 988, rgb(230, 230, 230))
      draw_entry_cursor(d, t1, entry)

def draw_entry_text(+d: Nat, img: Image, +entry: String) -> Image:
  draw_entry_text_go(d, img, entry, U32.is_eq(U32.from_nat(String.length(entry)), 0))

def draw_entry_bar_go(+d: Nat, img: Image, +entry: String, +entry_mode: U32, is_zero: Bool) -> Image:
  match is_zero:
    case True{}: img
    case False{}:
      +bar = fill_rect(d, img, 0, 976, 1024, 48, rgb(32, 36, 48))
      +bar1 = draw_text(entry_mode_label(entry_mode), d, bar, 16, 988, entry_label_color(entry_mode))
      draw_entry_text(d, bar1, entry)

def draw_entry_bar(+d: Nat, img: Image, +entry: String, +entry_mode: U32) -> Image:
  draw_entry_bar_go(d, img, entry, entry_mode, U32.is_eq(entry_mode, 0))

# accretive overlay rendering. All panels are opaque ui_panel rects drawn
# over the finished frame; only the full-rebuild path (shell_state) calls
# these, and tick_rebuild clears accd there, so a reused frame always
# already shows the current panel state.
def acc_termlines(+open: Bool, +tabs: List<&2, Tab>, +tab_idx: U32) -> List<&2, String>:
  match open:
    case False{}: Nil{}
    case True{}: term_all_lines(tab_term(tabs_get(tabs, tab_idx)))

# ---------- command palette (Wave 3) ----------
# Keyboard-invoked fuzzy action list. Invocation key: ';' (59) — verified
# unbound in every key table (key_code_action, tab_key_pending,
# prof_key_pending, fetch_key_pending, acc_closed_key2, all panel
# handlers); W8 reserves '?' (63), W5 will take 'c'.
# A new palette MODE alongside the universal-search overlay: PalSt rides
# inside AccSt as one field; modal tag 5 outranks search(1) > note(2) >
# gmail(3) > ai(4) > closed(0). Selecting an action dispatches its KEY
# through the key pipeline with the palette dismissed, so the effect is
# EXACTLY the key's effect (same handlers, same guards — no duplicated
# logic). Keys the accretive layer doesn't consume are re-injected as one
# synthetic Key event (Pal.fire) for the EvSt/Tab/Prof/fetch fold in the
# same tick, spliced in AFTER acc_strip — but dropped again when any panel
# is open post-dispatch (a real keypress then would be stripped too).
# Context: the palette opens over closed state and over the gmail panel
# only — never over search/note/ai text fields (so ';' stays typeable
# there), never in entry mode, never with the terminal focused, and never
# inside gmail's query box. The action list is gmail-aware: with gmail
# open, `/`/`n`/`p` carry their gmail meanings and "cycle profile" is
# hidden (gmail consumes `p`); with gmail closed the gmail page actions
# are hidden (they'd be no-ops — same guards as the key path).
# Brief correction: `+`/`-` are new/close TAB (tab_key_pending), not zoom.

def pal_cons(+key: U32, +label: String, +desc: String, tail: List<&2, PalAct>) -> List<&2, PalAct>:
  Con{PAct{key, label, desc}, tail}

# Shared tail: entries honest in the CLOSED context (ctx 0) only. The gmail
# contexts (1/2/3) get short honest lists instead — most closed-context keys
# are stripped no-ops with gmail open, so listing them would lie.
# (`;` has no entry: you're already in the palette; `;`/Esc closes it.
# Esc/Quit live in the ctx heads: in ctx 0 Esc would QUIT (nothing to
# dismiss), and in gmail ctx `q` is a stripped no-op.)
def pal_actions_tail() -> List<&2, PalAct>:
  pal_cons(115, "Save note", "s - save a note for the current article (needs reader focus)",
  pal_cons(103, "Gmail panel", "g - toggle the Gmail panel",
  pal_cons(105, "AI assistant", "i - toggle the AI assistant",
  pal_cons(116, "Focus terminal", "t - focus the terminal (keystrokes go there)",
  pal_cons(114, "Focus reader", "r - focus the reader on the current article",
  pal_cons(123, "Previous tab", "{ - focus the previous terminal tab",
  pal_cons(125, "Next tab", "} - focus the next terminal tab",
  pal_cons(43, "New tab", "+ - open a new terminal tab",
  pal_cons(45, "Close tab", "- - close the current terminal tab",
  pal_cons(102, "Fetch live feed", "f - reload the live RSS feed",
  pal_cons(104, "HTTPS fetch", "h - fetch the current article over verified HTTPS",
  pal_cons(97, "Add item", "a - add the current feed item to a theme",
  pal_cons(101, "Edit item", "e - edit the selected item's title",
  pal_cons(100, "Delete item", "d - delete the selected item",
  pal_cons(49, "Filter: theme 1", "1 - show only theme-1 items",
  pal_cons(50, "Filter: theme 2", "2 - show only theme-2 items",
  pal_cons(51, "Filter: theme 3", "3 - show only theme-3 items",
  pal_cons(52, "Filter: theme 4", "4 - show only theme-4 items",
  pal_cons(53, "Filter: theme 5", "5 - show only theme-5 items",
  pal_cons(44, "Page up", ", - previous item page",
  pal_cons(46, "Page down", ". - next item page",
  Nil{})))))))))))))))))))))

# Context head: `/`, `n`, `p` mean different things by context; Esc/Quit are
# placed honestly per context (see pal_actions_tail comment).
# ctx: 0 = closed (full list), 1 = gmail list (MList — page nav applies),
# 2 = gmail slashable other (query applies, page nav would be a no-op),
# 3 = gmail non-slashable (MLoading/MFetchMsg/MUnknown/MQry — `/` hidden).
def pal_actions_head(+ctx: U32, tail: List<&2, PalAct>) -> List<&2, PalAct>:
  match ctx:
    case 1:
      pal_cons(47, "Gmail: query", "/ - search message subjects and senders",
      pal_cons(110, "Gmail: next page", "n - next page of messages",
      pal_cons(112, "Gmail: previous page", "p - previous page of messages",
      pal_cons(27, "Dismiss panel", "Esc - close the Gmail panel",
      Nil{}))))
    case 2:
      pal_cons(47, "Gmail: query", "/ - search message subjects and senders",
      pal_cons(27, "Dismiss panel", "Esc - close the Gmail panel",
      Nil{}))
    case 3:
      pal_cons(27, "Dismiss panel", "Esc - close the Gmail panel",
      Nil{})
    case _:
      pal_cons(47, "Universal search", "/ - filter-as-you-type over items, articles, terminal",
      pal_cons(110, "Next article", "n - next article (reader focused)",
      pal_cons(112, "Cycle profile", "p - switch profile (terminal and reader unfocused)",
      pal_cons(113, "Quit", "q - quit Shell-OS",
      tail))))

def pal_actions(+ctx: U32) -> List<&2, PalAct>:
  pal_actions_head(ctx, pal_actions_tail())

# Case-insensitive subsequence ("fuzzy") match, one self-recursive def
# (Bend forbids mutual recursion).
def pal_qlower_go(+q: String, acc: List<&2, U32>) -> List<&2, U32>:
  match q:
    case SNil{}: List.reverse(&2, U32, acc)
    case SCon{Chr{c}, r}: pal_qlower_go(r, Con{str_lower_c(c), acc})

# Non-recursive leaf: do the current heads match? (precomputed
# classification — Bend forbids match-on-computed-Bool and mutual
# recursion, so the recursive def below threads the next step's
# classification as a plain param.)
def pal_heads_eq(+qs: List<&2, U32>, +t: String) -> Bool:
  match qs:
    case Nil{}: True{}
    case Con{qc, _}:
      match t:
        case SNil{}: False{}
        case SCon{Chr{tc}, _}: U32.is_eq(qc, str_lower_c(tc))

def pal_subseq_go(+qs: List<&2, U32>, +t: String, +heads_eq: Bool) -> Bool:
  match qs:
    case Nil{}: True{}
    case Con{qc, qr}:
      match t:
        case SNil{}: False{}
        case SCon{Chr{tc}, tr}:
          match heads_eq:
            case True{}: pal_subseq_go(qr, tr, pal_heads_eq(qr, tr))
            case False{}: pal_subseq_go(Con{qc, qr}, tr, pal_heads_eq(Con{qc, qr}, tr))

def pal_subseq(+qs: List<&2, U32>, +t: String) -> Bool:
  pal_subseq_go(qs, t, pal_heads_eq(qs, t))

def pal_match_text(+act: PalAct, +q: String) -> Bool:
  match act:
    case PAct{_, label, desc}:
      pal_subseq(pal_qlower_go(q, Nil{}), String.append(label, String.append(" ", desc)))

def pal_filter_pick(+hit: Bool, +a: PalAct, acc: List<&2, PalAct>) -> List<&2, PalAct>:
  match hit:
    case True{}: Con{a, acc}
    case False{}: acc

def pal_filter_go(+acts: List<&2, PalAct>, +q: String, acc: List<&2, PalAct>) -> List<&2, PalAct>:
  match acts:
    case Nil{}: List.reverse(&2, PalAct, acc)
    case a <> rest: pal_filter_go(rest, q, pal_filter_pick(pal_match_text(a, q), a, acc))

def pal_filter(+q: String, +acts: List<&2, PalAct>) -> List<&2, PalAct>:
  pal_filter_go(acts, q, Nil{})

def pal_count_go(+acts: List<&2, PalAct>, +n: U32) -> U32:
  match acts:
    case Nil{}: n
    case _ <> rest: pal_count_go(rest, U32.add(n, 1))

def pal_count(+acts: List<&2, PalAct>) -> U32:
  pal_count_go(acts, 0)

# Index walk (same shape as font_nth in font.bend).
def pal_at_go(+acts: List<&2, PalAct>, +idx: U32) -> Maybe<&2, PalAct>:
  match acts, idx:
    case Nil{}, _: None{}
    case a <> _, 0: Some{a}
    case _ <> rest, i: pal_at_go(rest, U32.sub(i, 1))

def pal_at(+acts: List<&2, PalAct>, +idx: U32) -> Maybe<&2, PalAct>:
  pal_at_go(acts, idx)

# ---------- palette state helpers ----------

def acc_pal_of(+acc: AccSt) -> PalSt:
  match acc:
    case Acc{_, _, _, _, _, _, _, _, _, pal, help}: pal

def acc_pal_is_open(+pal: PalSt) -> Bool:
  match pal:
    case Pal{_, open, _, _}: open

def acc_pal_q(+pal: PalSt) -> String:
  match pal:
    case Pal{q, _, _, _}: q

def acc_pal_sel(+pal: PalSt) -> U32:
  match pal:
    case Pal{_, _, sel, _}: sel

def acc_pal_fire_of(+acc: AccSt) -> U32:
  match acc:
    case Acc{_, _, _, _, _, _, _, _, _, pal, help}:
      match pal:
        case Pal{_, _, _, fire}: fire

def acc_set_pal(+acc: AccSt, +pal: PalSt) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, note, save_req, accd, search_go, _, help}:
      Acc{q, open, sel, gmail, ai, note, save_req, True{}, search_go, pal, help}

def acc_pal_open(+acc: AccSt) -> AccSt:
  acc_set_pal(acc, Pal{"", True{}, 0, 0})

def acc_pal_close(+acc: AccSt) -> AccSt:
  acc_set_pal(acc, Pal{"", False{}, 0, 0})

def acc_pal_set_fire(+acc: AccSt, +fire: U32) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, note, save_req, accd, search_go, Pal{pq, _, _, _}, help}:
      Acc{q, open, sel, gmail, ai, note, save_req, True{}, search_go, Pal{pq, False{}, 0, fire}, help}

def acc_pal_fire_cleared(+acc: AccSt) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, note, save_req, accd, search_go, Pal{pq, popen, psel, _}, help}:
      Acc{q, open, sel, gmail, ai, note, save_req, accd, search_go, Pal{pq, popen, psel, 0}, help}

# ---------- help overlay state helpers ----------
# The `?` shortcut overlay. HelpSt is HOff{} (closed) or HOn{ctx} where ctx
# is the context captured at open time (0=normal, 1=search, 2=note/saved,
# 3=gmail, 4=ai, 5=palette, 6=entry, 7=reader, 8=terminal). The ctx is stored
# (not derived at render) so the overlay shows the opening context even as
# the underlying state sits frozen underneath.

def acc_help_of(+acc: AccSt) -> HelpSt:
  match acc:
    case Acc{_, _, _, _, _, _, _, _, _, _, help}: help

def acc_help_is_open_go(+help: HelpSt) -> Bool:
  match help:
    case HOff{}: False{}
    case HOn{_}: True{}

def acc_help_is_open(+acc: AccSt) -> Bool:
  acc_help_is_open_go(acc_help_of(acc))

def acc_help_ctx_go(+help: HelpSt) -> U32:
  match help:
    case HOff{}: 0
    case HOn{ctx}: ctx

def acc_help_ctx(+acc: AccSt) -> U32:
  acc_help_ctx_go(acc_help_of(acc))

def acc_set_help(+acc: AccSt, +help: HelpSt) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, note, save_req, accd, search_go, pal, _}:
      Acc{q, open, sel, gmail, ai, note, save_req, accd, search_go, pal, help}

def acc_help_open(+acc: AccSt, +ctx: U32) -> AccSt:
  acc_set_help(acc, HOn{ctx})

def acc_help_close(+acc: AccSt) -> AccSt:
  acc_set_help(acc, HOff{})

# Tag-6 key handler: while help is open, Esc closes; every other key is
# swallowed (consumed=True) so nothing leaks to the underlying panel or EvSt.
# `?` itself is intercepted in acc_scan_key (toggle) and never reaches here.
def acc_help_key(+acc: AccSt, +c: U32) -> (AccSt & Bool):
  match c:
    case 27: (acc_help_close(acc), True{})
    case _: (acc, True{})

# Synthetic-key injection for the EvSt fold (called AFTER acc_strip in
# tick_fold_acc_applied): a real keypress with panels open post-dispatch
# would be stripped, so the synthetic one is dropped too.
def acc_fire_evs_pick(+is_zero: Bool, +fire: U32, +panels_open: Bool, evs: List<Event>) -> List<Event>:
  match is_zero:
    case True{}: evs
    case False{}:
      match panels_open:
        case True{}: evs
        case False{}: Con{Key{fire, True{}}, evs}

def acc_fire_evs_go(+fire: U32, +panels_open: Bool, evs: List<Event>) -> List<Event>:
  acc_fire_evs_pick(U32.is_eq(fire, 0), fire, panels_open, evs)

# Local any-panel-open predicate (acc_any_open and the *_open_q helpers it
# uses are defined later in the file; Bend requires defs precede use).
# 3-way palette context from the gmail field (MailInner comes from
# gmail.bend, bundled before app.bend).
# `/` opens the query box from list-level states only (never from transient
# MUnknown/MLoading/MFetchMsg, and never from MQry itself — inside the box
# `/` is a literal character). Defined up here: pal_ctx_gmail needs it for
# the palette's context heads (ctx 3 = non-slashable, `/` hidden).
def acc_gmail_slashable(+inner: MailInner) -> Bool:
  match inner:
    case MList{_, _, _, _, _, _, _, _, _}: True{}
    case MReading{_, _, _, _, _, _, _, _, _, _, _}: True{}
    case MNotCfg{}: True{}
    case MCfgErr{_}: True{}
    case MBadPerm{}: True{}
    case MAuthErr{}: True{}
    case MNetErr{_}: True{}
    case _: False{}

def pal_ctx_inner(+slashable: Bool) -> U32:
  match slashable:
    case True{}: 2
    case False{}: 3

def pal_ctx_gmail(+gmail: MailSt) -> U32:
  match gmail:
    case MOff{}: 0
    case MOn{MList{_, _, _, _, _, _, _, _, _}}: 1
    case MOn{inner}: pal_ctx_inner(acc_gmail_slashable(inner))

def pal_ctx_of(+acc: AccSt) -> U32:
  match acc:
    case Acc{_, _, _, gmail, _, _, _, _, _, _, help}: pal_ctx_gmail(gmail)

def pal_gmail_open_q(+m: MailSt) -> Bool:
  match m:
    case MOn{_}: True{}
    case _: False{}

def pal_ai_open_q(+a: AISt) -> Bool:
  match a:
    case AOn{_}: True{}
    case _: False{}

def pal_note_open_q(+n: NoteSt) -> Bool:
  match n:
    case NOff{}: False{}
    case _: True{}

def pal_any_open(+acc: AccSt) -> Bool:
  match acc:
    case Acc{_, open, _, gmail, ai, note, _, _, _, _, help}:
      Bool.or(open, Bool.or(pal_gmail_open_q(gmail), Bool.or(pal_ai_open_q(ai), pal_note_open_q(note))))

def acc_fire_evs(+acc3: AccSt, evs: List<Event>) -> List<Event>:
  acc_fire_evs_go(acc_pal_fire_of(acc3), pal_any_open(acc3), evs)

# ---------- palette rendering (topmost overlay) ----------

def pal_key_name_go(+code: U32) -> String:
  match code:
    case 27: "Esc"
    case 43: "+"
    case 44: ","
    case 45: "-"
    case 46: "."
    case 47: "/"
    case 59: ";"
    case 123: "{"
    case 125: "}"
    case c: Char.show(Chr{c})

def pal_row_mark(+is_cur: Bool) -> String:
  match is_cur:
    case True{}: "> "
    case False{}: "  "

def pal_row_color(+is_cur: Bool, +accent: U32, +text: U32) -> U32:
  match is_cur:
    case True{}: accent
    case False{}: text

def pal_row_text(+act: PalAct, +is_cur: Bool) -> String:
  match act:
    case PAct{key, label, desc}:
      str_trunc(String.append(pal_row_mark(is_cur), String.append(pal_key_name_go(key), String.append("  ", String.append(label, String.append(" - ", desc))))), 64n)

def pal_overlay_row_draw(img: Image, +act: PalAct, +d: Nat, +th: Theme, +sel: U32, +absidx: U32, +visrow: U32) -> Image:
  match th:
    case T{_, _, accent, text, _}:
      draw_text(pal_row_text(act, U32.is_eq(sel, absidx)), d, img, 224, U32.add(288, U32.mul(visrow, 32)), pal_row_color(U32.is_eq(sel, absidx), accent, text))

# Selection-relative windowing: the overlay shows 12 rows; when sel roams
# past row 11 the window pages so the cursor stays visible. start is the
# 12-row page containing sel. Rows draw at visual positions 0..11 but the
# `> ` mark uses the absolute index, so it lands on the selected action.
def pal_win_start(+sel: U32) -> U32:
  U32.sub(sel, U32.mod(sel, 12))

def pal_win_pick(+in_win: Bool, +a: PalAct, acc: List<&2, PalAct>) -> List<&2, PalAct>:
  match in_win:
    case True{}: Con{a, acc}
    case False{}: acc

def pal_win_go(+acts: List<&2, PalAct>, +idx: U32, +start: U32, +end: U32, acc: List<&2, PalAct>) -> List<&2, PalAct>:
  match acts:
    case Nil{}: List.reverse(&2, PalAct, acc)
    case a <> t: pal_win_go(t, U32.add(idx, 1), start, end, pal_win_pick(Bool.and(U32.is_le(start, idx), U32.is_lt(idx, end)), a, acc))

def pal_window(+acts: List<&2, PalAct>, +sel: U32) -> List<&2, PalAct>:
  +start = pal_win_start(sel)
  pal_win_go(acts, 0, start, U32.add(start, 12), Nil{})

def pal_overlay_rows_go(+acts: List<&2, PalAct>, +d: Nat, img: Image, +th: Theme, +sel: U32, +absidx: U32, +visrow: U32) -> Image:
  match acts:
    case Nil{}: img
    case a <> t:
      pal_overlay_rows_go(t, d, pal_overlay_row_draw(img, a, d, th, sel, absidx, visrow), th, sel, U32.add(absidx, 1), U32.add(visrow, 1))

def pal_overlay_rows(+d: Nat, img: Image, +th: Theme, +acts: List<&2, PalAct>, +sel: U32) -> Image:
  +start = pal_win_start(sel)
  pal_overlay_rows_go(pal_window(acts, sel), d, img, th, sel, start, 0)

def pal_header_str(+n: U32, +q: String) -> String:
  String.append("COMMAND PALETTE - ", String.append(U32.show(n), String.append(" actions  [;] close  > ", q)))

def draw_pal_overlay_open(+d: Nat, img: Image, +th: Theme, +q: String, +sel: U32, +acts: List<&2, PalAct>) -> Image:
  match th:
    case T{_, _, _, text, _}:
      +p = ui_panel(d, img, rect(192, 224, 640, 480), th)
      +p2 = draw_text(pal_header_str(pal_count(pal_filter(q, acts)), q), d, p, 224, 248, text)
      pal_overlay_rows(d, p2, th, pal_filter(q, acts), sel)

def draw_pal_overlay(+d: Nat, img: Image, +th: Theme, +pal: PalSt, +ctx: U32) -> Image:
  match pal:
    case Pal{q, open, sel, _}:
      match open:
        case False{}: img
        case True{}: draw_pal_overlay_open(d, img, th, q, sel, pal_actions(ctx))


# ---------- `?` overlay: data-driven binding table (Wave 5) ----------
# REGISTRATION: This table is the SINGLE source of truth for the `?` overlay.
# To add a binding: append an HB{ctx, key, desc} entry below.
# To remove a binding: delete its entry.
# Every live key handler must have an entry here, or be named in
# help_excluded() with a reason. Every entry here must correspond to a live
# handler (proven by the hostile interpreter tests and Xvfb gates).
# Contexts: 0=normal 1=search 2=note/saved 3=gmail 4=ai 5=palette
#           6=entry 7=reader 8=terminal
type HelpBind is Data:
  HB{ctx: U32, key: String, desc: String}

def help_bindings() -> List<&2, HelpBind>:
  Con{HB{0, "Esc / q", "Quit"},
  Con{HB{0, "1", "Filter: all"},
  Con{HB{0, "2", "Filter: home"},
  Con{HB{0, "3", "Filter: design"},
  Con{HB{0, "4", "Filter: gaming"},
  Con{HB{0, "5", "Filter: saved"},
  Con{HB{0, "a", "Add item"},
  Con{HB{0, "e", "Edit title"},
  Con{HB{0, "d", "Delete item"},
  Con{HB{0, ", / [", "Previous page"},
  Con{HB{0, ". / ]", "Next page"},
  Con{HB{0, "r", "Focus reader"},
  Con{HB{0, "{ / }", "Prev / next tab"},
  Con{HB{0, "+ / -", "New / close tab"},
  Con{HB{0, "p", "Cycle profile"},
  Con{HB{0, "f", "Fetch feed"},
  Con{HB{0, "h", "Fetch HTTPS feed"},
  Con{HB{0, "/", "Search"},
  Con{HB{0, "g", "Gmail"},
  Con{HB{0, "i", "AI grouping"},
  Con{HB{0, "?", "This help"},
  Con{HB{1, "Esc", "Close search"},
  Con{HB{1, "Enter", "Open selected hit"},
  Con{HB{1, "Up / Down", "Move selection"},
  Con{HB{1, "Backspace", "Delete char"},
  Con{HB{1, "a-z", "Type query"},
  Con{HB{1, "?", "This help"},
  Con{HB{2, "Esc", "Cancel"},
  Con{HB{2, "Enter", "Save note"},
  Con{HB{2, "Backspace", "Delete char"},
  Con{HB{2, "a-z", "Type note"},
  Con{HB{2, "?", "This help"},
  Con{HB{3, "Esc", "Close"},
  Con{HB{3, "Up / Down", "Move selection (list)"},
  Con{HB{3, "Enter", "Open message (list)"},
  Con{HB{3, "n / p", "Next / prev page (list)"},
  Con{HB{3, "/", "Search query (list/reading)"},
  Con{HB{3, "m", "Retry (error)"},
  Con{HB{3, "?", "This help"},
  Con{HB{4, "Esc", "Close"},
  Con{HB{4, "Enter", "Start grouping / Apply"},
  Con{HB{4, "?", "This help"},
  Con{HB{5, "Esc / ;", "Close palette"},
  Con{HB{5, "Enter", "Run action"},
  Con{HB{5, "Up / Down", "Move selection"},
  Con{HB{5, "Backspace", "Delete char"},
  Con{HB{5, "a-z", "Filter actions"},
  Con{HB{5, "?", "This help"},
  Con{HB{6, "Esc", "Cancel"},
  Con{HB{6, "Enter", "Commit"},
  Con{HB{6, "Backspace", "Delete char"},
  Con{HB{6, "0-3", "Theme (add mode)"},
  Con{HB{6, "a-z", "Type text"},
  Con{HB{6, "?", "This help"},
  Con{HB{7, "Esc", "Unfocus reader"},
  Con{HB{7, "t", "Focus terminal"},
  Con{HB{7, "Up / Down", "Scroll"},
  Con{HB{7, "n / p", "Next / prev article"},
  Con{HB{7, "s", "Save note"},
  Con{HB{7, "?", "This help"},
  Con{HB{8, "Esc", "Unfocus terminal"},
  Con{HB{8, "PgUp / PgDn", "Scrollback"},
  Con{HB{8, "other keys", "Sent to shell"},
  Con{HB{8, "?", "This help"},
  Nil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}

# Explicitly excluded from the table (not user-facing bindings):
# - Mouse clicks/hover (pointer-only, no key equivalent).
# - The synthetic `fire` key injection (internal, not a physical key).
# - Key-release events (only key-press is actionable).
def help_excluded() -> String:
  "mouse, synthetic-fire, key-release, semicolon-palette (Wave 3 native bug: `;` handler exists but does not open palette in native binary; excluded from display until fixed)"

def help_ctx_name(+ctx: U32) -> String:
  match ctx:
    case 0: "NORMAL"
    case 1: "SEARCH"
    case 2: "NOTE"
    case 3: "GMAIL"
    case 4: "AI"
    case 5: "PALETTE"
    case 6: "ENTRY"
    case 7: "READER"
    case 8: "TERMINAL"
    case _: "NORMAL"

def help_cons_if(+hit: Bool, +b: HelpBind, acc: List<&2, HelpBind>) -> List<&2, HelpBind>:
  match hit:
    case True{}: Con{b, acc}
    case False{}: acc

def help_binds_for_go(+binds: List<&2, HelpBind>, +ctx: U32, acc: List<&2, HelpBind>) -> List<&2, HelpBind>:
  match binds:
    case Nil{}: List.reverse(&2, HelpBind, acc)
    case HB{c, key, desc} <> rest: help_binds_for_go(rest, ctx, help_cons_if(U32.is_eq(c, ctx), HB{c, key, desc}, acc))

def help_binds_for(+ctx: U32) -> List<&2, HelpBind>:
  help_binds_for_go(help_bindings(), ctx, Nil{})

def help_header_str(+ctx: U32, +n: U32) -> String:
  String.append("SHORTCUTS - ", String.append(help_ctx_name(ctx), String.append("  (", String.append(U32.show(n), " keys)  [?] / [Esc] close"))))

def help_row_str(+key: String, +desc: String) -> String:
  String.append("  ", String.append(key, String.append("  -  ", desc)))

def help_rows_go(+binds: List<&2, HelpBind>, +d: Nat, img: Image, +th: Theme, +y: U32) -> Image:
  match binds:
    case Nil{}: img
    case HB{_, key, desc} <> rest:
      match th:
        case T{_, _, _, text, _}:
          help_rows_go(rest, d, draw_text(help_row_str(key, desc), d, img, 224, y, text), th, U32.add(y, 22))

def help_rows(+d: Nat, img: Image, +th: Theme, +binds: List<&2, HelpBind>) -> Image:
  help_rows_go(binds, d, img, th, 280)

def help_count_go(+binds: List<&2, HelpBind>, +n: U32) -> U32:
  match binds:
    case Nil{}: n
    case _ <> rest: help_count_go(rest, U32.add(n, 1))

def help_count(+binds: List<&2, HelpBind>) -> U32:
  help_count_go(binds, 0)


def draw_help_overlay(+d: Nat, img: Image, +th: Theme, +ctx: U32) -> Image:
  match th:
    case T{_, _, _, text, _}:
      +p = ui_panel(d, img, rect(192, 224, 640, 480), th)
      +p2 = draw_text(help_header_str(ctx, help_count(help_binds_for(ctx))), d, p, 224, 248, text)
      help_rows(d, p2, th, help_binds_for(ctx))

def acc_render_search_open(+d: Nat, img: Image, +th: Theme, +q: String, +sel: U32, +items: List<&2, Item>, +feed: String, +tabs: List<&2, Tab>, +tab_idx: U32) -> Image:
  +termlines = acc_termlines(True{}, tabs, tab_idx)
  draw_search_overlay(d, img, th, search_all(q, items, feed, termlines), sel, q, items, termlines)

def acc_render_search(+d: Nat, img: Image, +th: Theme, +q: String, +open: Bool, +sel: U32, +items: List<&2, Item>, +feed: String, +tabs: List<&2, Tab>, +tab_idx: U32) -> Image:
  match open:
    case False{}: img
    case True{}: acc_render_search_open(d, img, th, q, sel, items, feed, tabs, tab_idx)

def acc_render_note_open(+d: Nat, img: Image, +th: Theme, +title: String) -> Image:
  match th:
    case T{_, _, _, _, dim}:
      +p1 = ui_panel(d, img, R{212, 320, 600, 200}, th)
      +p2 = draw_text("SAVE ARTICLE", d, p1, 232, 340, dim)
      +p3 = draw_text(str_trunc(title, 58n), d, p2, 232, 364, dim)
      draw_text("note (Enter: save, Esc: cancel)", d, p3, 232, 388, dim)

def acc_render_note(+d: Nat, img: Image, +th: Theme, +note: NoteSt) -> Image:
  match note:
    case NEdit{title, _, _}: acc_render_note_open(d, img, th, title)
    case NCommit{title, _, _}: acc_render_note_open(d, img, th, title)
    case NOff{}: img

def acc_render_gmail_on(+d: Nat, img: Image, +th: Theme, +inner: MailInner) -> Image:
  match th:
    case T{_, _, _, _, dim}:
      +p1 = ui_panel(d, img, R{232, 200, 560, 520}, th)
      +p2 = draw_text("MAIL", d, p1, 252, 220, dim)
      draw_lines(d, mail_lines(inner), p2, 252, 244, 32, dim)

def acc_render_gmail(+d: Nat, img: Image, +th: Theme, +m: MailSt) -> Image:
  match m:
    case MOff{}: img
    case MOn{inner}: acc_render_gmail_on(d, img, th, inner)

def acc_render_ai_inner(+d: Nat, img: Image, +th: Theme, +inner: AIInner, +items: List<&2, Item>) -> Image:
  match inner:
    case AINone{}: img
    # AIUnknown: config not yet checked (the IO preamble resolves it next
    # tick). Render nothing — never flash the boot overlay. (Wave 1 fix:
    # pressing `i` with no ai.conf rendered one frame of "checking config…"
    # before settling to absent-UI.)
    case AIUnknown{}: img
    case _: ai_overlay(d, img, th, inner, items)

def acc_render_ai(+d: Nat, img: Image, +th: Theme, +a: AISt, +items: List<&2, Item>) -> Image:
  match a:
    case AOff{}: img
    case AOn{inner}: acc_render_ai_inner(d, img, th, inner, items)

def acc_render_help_go(+help: HelpSt, +d: Nat, img: Image, +theme: Theme) -> Image:
  match help:
    case HOff{}: img
    case HOn{ctx}: draw_help_overlay(d, img, theme, ctx)

def acc_render_help(+d: Nat, img: Image, +theme: Theme, +help: HelpSt) -> Image:
  acc_render_help_go(help, d, img, theme)


def acc_render(+d: Nat, +frame: Image, +theme: Theme, +acc: AccSt, +items: List<&2, Item>, +tabs: List<&2, Tab>, +tab_idx: U32, +feed: String) -> Image:
  match acc:
    case Acc{q, open, sel, gmail, ai, note, _, _, _, pal, help}:
      +f1 = acc_render_search(d, frame, theme, q, open, sel, items, feed, tabs, tab_idx)
      +f2 = acc_render_gmail(d, f1, theme, gmail)
      +f3 = acc_render_ai(d, f2, theme, ai, items)
      +f4 = acc_render_note(d, f3, theme, note)
      +f5 = draw_pal_overlay(d, f4, theme, pal, pal_ctx_gmail(gmail))
      acc_render_help(d, f5, theme, help)

# The note editor reuses the bottom entry bar (mode 6 = NOTE label) to show
# the text being typed; the main entry/entry_mode are untouched.
def acc_note_bar_text(+acc: AccSt, +entry: String) -> String:
  match acc:
    case Acc{_, _, _, _, _, NEdit{_, _, text}, _, _, _, _, help}: text
    case _: entry

def acc_note_bar_mode(+acc: AccSt, +entry_mode: U32) -> U32:
  match acc:
    case Acc{_, _, _, _, _, NEdit{_, _, _}, _, _, _, _, help}: 6
    case _: entry_mode

# accd flag: set by every acc mutation, ORed into the rebuild decision in
# tick_rebuild_go, cleared when the frame is rebuilt. This is what makes
# panel interactions repaint: tick_need (pinned 9-arg signature) cannot see
# acc changes.
def acc_is_touched(+acc: AccSt) -> Bool:
  match acc:
    case Acc{_, _, _, _, _, _, _, accd, _, _, help}: accd

def acc_untouch(+acc: AccSt) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, note, save_req, _, search_go, pal, help}:
      Acc{q, open, sel, gmail, ai, note, save_req, False{}, search_go, pal, help}

def shell_state(+d: Nat, +sel: U32, +items: List<&2, Item>, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus: Bool, +vs: ViewSt, +entry: String, +entry_mode: U32, +mx: U32, +my: U32, +hover: U32, +profile: String, +feed: String, +acc: AccSt) -> ShellSt:
  +base = shell_render(d, sel, items, tab_term(tabs_get(tabs, tab_idx)), tfocus, vs, hover, tab_idx, tabs_count(tabs), profile)
  +framed = draw_entry_bar(d, base, acc_note_bar_text(acc, entry), acc_note_bar_mode(acc, entry_mode))
  +accfr = acc_render(d, framed, theme_dark(), acc, items, tabs, tab_idx, feed)
  SSt{sel, d, items, accfr, tabs, tab_idx, tfocus, vs, entry, entry_mode, mx, my, hover, profile, feed, acc}

def sel_of(+s: ShellSt) -> U32:
  match s:
    case SSt{sel, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: sel

# view: hand the state back beside its cached frame (state is affine).
def shell_view(s: ShellSt) -> Pair(ShellSt, Image):
  match s:
    case SSt{sel, d, items, frame, tabs, tab_idx, tfocus, vs, entry, entry_mode, mx, my, hover, profile, feed, acc}:
      +fr = frame
      (SSt{sel, d, items, fr, tabs, tab_idx, tfocus, vs, entry, entry_mode, mx, my, hover, profile, feed, acc}, fr)

# ---------- event classification ----------
# Action codes: 0 = ignore, 1 = quit, 10+n = select theme n, 20 = add item,
# 21 = page prev, 22 = page next, 23 = focus reader, 24 = focus terminal.
# 23/24 are shared by keyboard ('r'/'t') and mouse clicks on the live tiles.

def in_rect(+x: U32, +y: U32, +rx: U32, +ry: U32, +rw: U32, +rh: U32) -> Bool:
  Bool.and(Bool.and(U32.is_le(rx, x), U32.is_lt(x, U32.add(rx, rw))),
           Bool.and(U32.is_le(ry, y), U32.is_lt(y, U32.add(ry, rh))))

# Live tiles (must match shell.bend shell_region_items/shell_region_reader/
# shell_region_term tile rects):
# reader x 416..696, y 512..1008; terminal x 712..992, y 512..1008.
# Clicking a tile focuses it, mirroring keyboard 'r'/'t' exactly
# (reader: tfocus unchanged; terminal: tfocus=True, reader unfocused).
def click_go6(+x: U32, +y: U32, b: Bool) -> U32:
  match b:
    case True{}: 14
    case False{}: 0

def click_go5(+x: U32, +y: U32, b: Bool) -> U32:
  match b:
    case True{}: 24
    case False{}: click_go6(x, y, in_rect(x, y, 208, 240, 184, 32))

def click_go4(+x: U32, +y: U32, b: Bool) -> U32:
  match b:
    case True{}: 23
    case False{}: click_go5(x, y, in_rect(x, y, 712, 512, 280, 496))

# Theme buttons (must match shell.bend): x 208..392, y 96/132/168/204 h 32.
def click_go3(+x: U32, +y: U32, b: Bool) -> U32:
  match b:
    case True{}: 13
    case False{}: click_go4(x, y, in_rect(x, y, 416, 512, 280, 496))

def click_go2(+x: U32, +y: U32, b: Bool) -> U32:
  match b:
    case True{}: 12
    case False{}: click_go3(x, y, in_rect(x, y, 208, 204, 184, 32))

def click_go1(+x: U32, +y: U32, b: Bool) -> U32:
  match b:
    case True{}: 11
    case False{}: click_go2(x, y, in_rect(x, y, 208, 168, 184, 32))

def click_go(+x: U32, +y: U32, b: Bool) -> U32:
  match b:
    case True{}: 10
    case False{}: click_go1(x, y, in_rect(x, y, 208, 132, 184, 32))

def click_action(+x: U32, +y: U32) -> U32:
  click_go(x, y, in_rect(x, y, 208, 96, 184, 32))

# Mouse/hover state, threaded alongside EvSt through the event fold.
# Deliberately a SEPARATE type from EvSt: the ~40 CRUD/entry helpers that
# build EvS literals never touch mouse state, so they (and test_crud2.bend)
# compile unchanged. Wave-2 note: mx/my are window px; hover is the target
# id above. PRESERVE this type.
type MouseSt is Data:
  MSt{mx: U32, my: U32, hover: U32}

# Hover target from mouse position. Theme-button rects MUST match click_action
# above; hover is theme-button-only (live-tile clicks have no hover target).
# 0=none, 1=all, 2=home, 3=gaming, 4=trip, 5=saved. Only target changes rebuild.
def hover_go5(+x: U32, +y: U32, b: Bool) -> U32:
  match b:
    case True{}: 5
    case False{}: 0

def hover_go4(+x: U32, +y: U32, b: Bool) -> U32:
  match b:
    case True{}: 4
    case False{}: hover_go5(x, y, in_rect(x, y, 208, 240, 184, 32))

def hover_go3(+x: U32, +y: U32, b: Bool) -> U32:
  match b:
    case True{}: 3
    case False{}: hover_go4(x, y, in_rect(x, y, 208, 204, 184, 32))

def hover_go2(+x: U32, +y: U32, b: Bool) -> U32:
  match b:
    case True{}: 2
    case False{}: hover_go3(x, y, in_rect(x, y, 208, 168, 184, 32))

def hover_go1(+x: U32, +y: U32, b: Bool) -> U32:
  match b:
    case True{}: 1
    case False{}: hover_go2(x, y, in_rect(x, y, 208, 132, 184, 32))

def hover_at(+x: U32, +y: U32) -> U32:
  hover_go1(x, y, in_rect(x, y, 208, 96, 184, 32))

def tick_ev_move(+x: U32, +y: U32) -> MouseSt:
  MSt{x, y, hover_at(x, y)}

def mouse_btn(x: U32, y: U32, button: U32) -> U32:
  match button:
    case 0: click_action(x, y)
    case _: 0

def mouse_action(x: U32, y: U32, button: U32, down: Bool) -> U32:
  match down:
    case False{}: 0
    case True{}: mouse_btn(x, y, button)

def key_code_action(code: U32) -> U32:
  match code:
    case 27: 1    # Esc
    case 113: 1   # q
    case 49: 10   # 1
    case 50: 11   # 2
    case 51: 12   # 3
    case 52: 13   # 4
    case 53: 14   # 5 — saved filter
    case 97: 20   # a — add item + save
    case 44: 21   # , — page prev
    case 46: 22   # . — page next
    case 91: 21   # [ — page prev
    case 93: 22   # ] — page next
    case 114: 23  # r — focus reader
    case _: 0

# Tab keys (normal mode, terminal UNFOCUSED and reader unfocused only — see
# tick_ev_keydown): '{' prev tab, '}' next tab, '+' new tab, '-' close tab.
# Deliberately NOT in key_code_action: the EvSt fold must keep treating them
# as ignored (action 0) so test_crud2.bend's pinned key paths are untouched;
# the TabSt half of the fold intercepts them separately in the same pass.
# All four codes are unbound today (verified against key_code_action above).
def tab_key_pending(+code: U32) -> U32:
  match code:
    case 123: 4  # {
    case 125: 3  # }
    case 43: 1   # +
    case 45: 2   # -
    case _: 0

def key_action(code: U32, down: Bool) -> U32:
  match down:
    case False{}: 0
    case True{}: key_code_action(code)

# Wheel/trackpad scroll (Bend 2.0.32 Event): wheel up (dy < 0) pages back,
# wheel down (dy > 0) pages forward — same actions as ,/. and [/].
# Look is first-person-camera motion (only under Window.grab): no action.
def scroll_action_go(+up: Bool, +down: Bool) -> U32:
  match up:
    case True{}: 21
    case False{}: Bool.pick(U32, down, 22, 0)

def scroll_action(+dy: F32) -> U32:
  scroll_action_go(F32.is_lt(dy, 0.0), F32.is_lt(0.0, dy))

def event_action(e: Event) -> U32:
  match e:
    case Close{}: 1
    case Key{code, down}: key_action(code, down)
    case Mouse{x, y, button, down}: mouse_action(x, y, button, down)
    case Move{x, y}: 0
    case Look{dx, dy}: 0
    case Scroll{x, y, dx, dy}: scroll_action(dy)

# ---------- state transitions ----------

# Event-processing state. Packed in a Data type so tick_ev_go can be
# self-recursive without mutual recursion (Bend forbids user-code cycles).
# (Uses StrList because List<String> has kind Type, not Data.)
type TtyWList is Data:
  TtyWNil{}
  TtyWCons{head: String, tail: TtyWList}

type EvSt is Data:
  EvS{sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, entry: String, entry_mode: U32}

def evst_new(+sel: U32, +items: List<&2, Item>, +tfocus: Bool, +vs: ViewSt, +entry: String, +entry_mode: U32) -> EvSt:
  EvS{sel, items, tfocus, False{}, False{}, TtyWNil{}, vs, entry, entry_mode}

# Tab-request sidecar, folded alongside EvSt/MouseSt through the event fold
# (same pattern as MouseSt: test_crud2.bend builds EvS literals directly, so
# EvSt's 9 fields are frozen and tick_ev_go/tick_need keep their signatures).
# tab_idx seeds from SSt each tick; pending is set by the four tab keys and
# executed in the IO pass — Pty.spawn/Pty.close are effects, so the pure fold
# can only REQUEST them:
#   0 = none, 1 = new tab, 2 = close tab, 3 = next tab, 4 = prev tab.
# PRESERVE for profiles/reader agents: the fold sets pending (see
# tick_ev_keydown), the IO pass consumes and clears it structurally (see
# shell_tick_pend); it never survives a tick.
type TabSt is Data:
  TSt{tab_idx: U32, pending: U32}

# Profile-switch sidecar, folded alongside EvSt/MouseSt/TabSt (same pattern as
# TabSt: EvSt's 9 fields stay frozen so test_crud2.bend compiles unchanged).
# cur = the profile the tick started with (seeded from SSt); pending = the
# profile to switch to, or "" when no switch was requested. The fold can only
# REQUEST the switch: the IO pass saves the old profile's items, loads the
# new profile's file, and rebuilds SSt (see tick_tab_save_pend).
# PRESERVE for the reader agent: the fold sets pending (see tick_ev_keydown),
# the IO pass consumes it; it never survives a tick.
type ProfSt is Data:
  PSt{cur: String, pending: String}

# Fetch sidecar (item #7: reader live content). pending=True fires one fetch
# of the live feed in the IO pass; hpending=True selects the HTTPS target
# (live internet feed via the verified-TLS bridge) instead of the plain-HTTP
# local demo target. feed carries the current body so the fold can compute
# the live article's scroll bound without touching EvSt.
type FetchSt is Data:
  FchSt{pending: Bool, hpending: Bool, feed: String}

# Scrollback-view request sidecar (full defs below, next to the key path).
#   up   = lines to scroll back (PgUp adds 24 per press, accumulates)
#   down = lines to scroll toward live (PgDn adds 24 per press, accumulates)
#   live = True: any other focused key (incl. Esc) — return to live; wins
type SbSt is Data:
  SbS{up: U32, down: U32, live: Bool}

# All six fold states in one Data so the single-pass recursion needs no
# pair-destructuring of computed values (Bend forbids it) and no mutual
# recursion (also forbidden): tick_ev_go2 threads one FSt, and each arm
# rebuilds it via NON-recursive helpers (fold_move_fst / tick_ev_single).
# sb is the scrollback-view request sidecar (see the SbSt block above).
type FoldSt is Data:
  FSt{ev: EvSt, mouse: MouseSt, tab: TabSt, prof: ProfSt, fetch: FetchSt, sb: SbSt}

# Pass 1 (pure): fold events into an EvSt. tick_ev_go recurses on the event
# list; tick_ev_single and all helpers below are NON-recursive.









def term_input_str(code: U32) -> String:
  match code:
    case 13: Char.show(Chr{10})   # Enter -> LF
    case c: Char.show(Chr{c})

def bool_not(+b: Bool) -> Bool:
  match b:
    case True{}: False{}
    case False{}: True{}

def bool_eq(+a: Bool, +b: Bool) -> Bool:
  match a, b:
    case True{}, True{}: True{}
    case False{}, False{}: True{}
    case _, _: False{}

def act_sel_sub(+a: U32, +is14: Bool) -> U32:
  match is14:
    case True{}: 5
    case False{}: U32.sub(a, 10)

def act_sel_pick(+lt: Bool, +a: U32) -> U32:
  match lt:
    case True{}: 0
    case False{}: act_sel_sub(a, U32.is_eq(a, 14))

def act_sel(+a: U32) -> U32:
  act_sel_pick(U32.is_lt(a, 10), a)

def tick_ev_act(act: U32, +sel: U32, +items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt) -> EvSt:
  match act:
    case 0: EvS{sel, items, tfocus, dirty, quit, writes, vs, "", 0}
    case 1: EvS{sel, items, tfocus, dirty, True{}, writes, vs, "", 0}
    case 20: EvS{sel, items, tfocus, dirty, quit, writes, vs, "", 1}
    case 21: EvS{sel, items, tfocus, dirty, quit, writes, viewst_page_dec(vs), "", 0}
    case 22: EvS{sel, items, tfocus, dirty, quit, writes, viewst_page_inc(vs, items, sel), "", 0}
    case 23: EvS{sel, items, tfocus, dirty, quit, writes, viewst_focus_reader(vs), "", 0}
    case 24: EvS{sel, items, True{}, dirty, quit, writes, viewst_unfocus_reader(vs), "", 0}
    case a: EvS{act_sel(a), items, tfocus, dirty, quit, writes, viewst_page_reset(vs), "", 0}
def tick_ev_fkey_down(code: U32, sel: U32, items: List<&2, Item>, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt) -> EvSt:
  match code:
    case 27: EvS{sel, items, False{}, dirty, quit, writes, viewst_unfocus_reader(vs), "", 0}
    case c: EvS{sel, items, True{}, dirty, quit, TtyWCons{term_input_str(c), writes}, vs, "", 0}
def tick_ev_fkey(code: U32, down: Bool, sel: U32, items: List<&2, Item>, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt) -> EvSt:
  match down:
    case False{}: EvS{sel, items, True{}, dirty, quit, writes, vs, "", 0}
    case True{}: tick_ev_fkey_down(code, sel, items, dirty, quit, writes, vs)
def tick_ev_s_focused(e: Event, sel: U32, items: List<&2, Item>, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt) -> EvSt:
  match e:
    case Key{code, down}: tick_ev_fkey(code, down, sel, items, dirty, quit, writes, vs)
    case _: tick_ev_act(event_action(e), sel, items, True{}, dirty, quit, writes, vs)

# Reader-focused keys: Up/Down scroll, n/p switch article, t jumps to the
# terminal, Esc unfocuses. Anything else falls through to the normal action
# table (1-4 filter, a adds, ,/. turn pages) with reader focus kept.
# NOTE: Base Window delivers arrows as 63232/63233 (WebKit-style, see
# bend2/effs/window_frame.c), NOT the X11 keysyms 65362/65364.
def tick_ev_rkey(+code: U32, sel: U32, items: List<&2, Item>, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt, +feed: String) -> EvSt:
  match code:
    case 27: EvS{sel, items, False{}, dirty, quit, writes, viewst_unfocus_reader(vs), "", 0}
    case 116: EvS{sel, items, True{}, dirty, quit, writes, viewst_unfocus_reader(vs), "", 0}
    case 63232: EvS{sel, items, False{}, dirty, quit, writes, viewst_scroll(vs, True{}), "", 0}
    case 63233: EvS{sel, items, False{}, dirty, quit, writes, viewst_scroll(vs, False{}), "", 0}
    case 110: EvS{sel, items, False{}, dirty, quit, writes, viewst_rart_next(vs, feed), "", 0}
    case 112: EvS{sel, items, False{}, dirty, quit, writes, viewst_rart_prev(vs, feed), "", 0}
    case _: tick_ev_act(key_action(code, True{}), sel, items, False{}, dirty, quit, writes, vs)
def tick_ev_ukey_down(+code: U32, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt) -> EvSt:
  match code:
    case 116: EvS{sel, items, True{}, dirty, quit, writes, vs, "", 0}
    case _: tick_ev_act(key_action(code, True{}), sel, items, tfocus, dirty, quit, writes, vs)
def tick_ev_ukey_rfocused(+rf: Bool, +code: U32, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt, +feed: String) -> EvSt:
  match rf:
    case True{}: tick_ev_rkey(code, sel, items, dirty, quit, writes, vs, feed)
    case False{}: tick_ev_ukey_down(code, sel, items, tfocus, dirty, quit, writes, vs)
def tick_ev_ukey(+code: U32, +down: Bool, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt, +feed: String) -> EvSt:
  match down:
    case False{}: tick_ev_act(key_action(code, down), sel, items, tfocus, dirty, quit, writes, vs)
    case True{}: tick_ev_ukey_rfocused(viewst_rfocus(vs), code, sel, items, tfocus, dirty, quit, writes, vs, feed)
def tick_ev_s_unfocused(e: Event, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt, +feed: String) -> EvSt:
  match e:
    case Key{code, down}: tick_ev_ukey(code, down, sel, items, tfocus, dirty, quit, writes, vs, feed)
    case _: tick_ev_act(event_action(e), sel, items, tfocus, dirty, quit, writes, vs)
# ---------- CRUD entry mode helpers ----------
# entry_mode: 0=normal, 1-4=add (theme = mode-1), 5=edit

def entry_append(entry: String, code: U32) -> String:
  String.append(entry, Char.show(Chr{code}))

# Non-recursive: append the char (if present) to acc
def entry_bs_append(acc: String, mc: Maybe<&2, Char>) -> String:
  match mc:
    case None{}: acc
    case Some{c}: String.append(acc, Char.show(c))

def entry_backspace_go(+s: String, remaining: Nat, +idx: Nat, acc: String) -> String:
  match remaining:
    case 0n: acc
    case 1n+r: entry_backspace_go(s, r, Nat.add(idx, 1n), entry_bs_append(acc, String.get(s, idx)))

def entry_backspace_len(entry: String, len: Nat) -> String:
  match len:
    case 0n: ""
    case 1n+rest: entry_backspace_go(entry, rest, 0n, "")

def entry_backspace(+entry: String) -> String:
  entry_backspace_len(entry, String.length(entry))

def items_get_title_go(items: List<&2, Item>, idx: U32) -> String:
  match items:
    case Nil{}: ""
    case Con{it, rest}:
      match it:
        case It{title, _, _, _, _}:
          match idx:
            case 0: title
            case _: items_get_title_go(rest, U32.sub(idx, 1))

def items_get_title(items: List<&2, Item>, idx: U32) -> String:
  items_get_title_go(items, idx)

def items_get_theme_go(items: List<&2, Item>, idx: U32) -> U32:
  match items:
    case Nil{}: 0
    case Con{it, rest}:
      match it:
        case It{_, theme, _, _, _}:
          match idx:
            case 0: theme
            case _: items_get_theme_go(rest, U32.sub(idx, 1))

def items_get_theme(items: List<&2, Item>, idx: U32) -> U32:
  items_get_theme_go(items, idx)

def items_remove_at_go(items: List<&2, Item>, idx: U32) -> List<&2, Item>:
  match items:
    case Nil{}: Nil{}
    case Con{it, rest}:
      match idx:
        case 0: rest
        case _: Con{it, items_remove_at_go(rest, U32.sub(idx, 1))}

def items_remove_at(items: List<&2, Item>, idx: U32) -> List<&2, Item>:
  items_remove_at_go(items, idx)

def items_replace_at_go(items: List<&2, Item>, idx: U32, new_it: Item) -> List<&2, Item>:
  match items:
    case Nil{}: Nil{}
    case Con{it, rest}:
      match idx:
        case 0: Con{new_it, rest}
        case _: Con{it, items_replace_at_go(rest, U32.sub(idx, 1), new_it)}

def items_replace_at(items: List<&2, Item>, idx: U32, new_it: Item) -> List<&2, Item>:
  items_replace_at_go(items, idx, new_it)

# Retitle the item at idx, preserving theme/note/saved_at/url
# (edit must not silently erase saved-article metadata).
def items_retitle_new(+it: Item, +title: String) -> Item:
  match it:
    case It{_, theme, note, saved_at, url}: It{title, theme, note, saved_at, url}

def items_retitle_at_go(+items: List<&2, Item>, idx: U32, +title: String) -> List<&2, Item>:
  match items:
    case Nil{}: Nil{}
    case Con{it, rest}:
      match idx:
        case 0: Con{items_retitle_new(it, title), rest}
        case _: Con{it, items_retitle_at_go(rest, U32.sub(idx, 1), title)}

def items_retitle_at(+items: List<&2, Item>, idx: U32, +title: String) -> List<&2, Item>:
  items_retitle_at_go(items, idx, title)

def items_count_go(items: List<&2, Item>, acc: U32) -> U32:
  match items:
    case Nil{}: acc
    case Con{_, rest}: items_count_go(rest, U32.add(acc, 1))

def items_count(items: List<&2, Item>) -> U32:
  items_count_go(items, 0)

# Clamp sel to valid range after deletion
def sel_clamp_lt(sel: U32, count: U32, lt: Bool) -> U32:
  match lt:
    case True{}: sel
    case False{}: U32.sub(count, 1)

def sel_clamp(+sel: U32, +count: U32) -> U32:
  match count:
    case 0: 0
    case _: sel_clamp_lt(sel, count, U32.is_lt(sel, count))

# Check if in entry mode (1-5)
def is_entry_mode(mode: U32) -> Bool:
  # mode 1-5 are entry modes; use match instead of computed Bool.and
  match mode:
    case 1: True{}
    case 2: True{}
    case 3: True{}
    case 4: True{}
    case 5: True{}
    case _: False{}

# Handle a key in entry mode. Returns new EvSt.
def tick_entry_theme(sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, entry: String, mode: U32, theme: U32) -> EvSt:
  # Only in add mode (1-4); in edit mode, ignore theme keys
  match mode:
    case 5: EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, mode}  # edit mode: ignore
    case _: EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, U32.add(1, theme)}

def tick_entry_printable_len(code: U32, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, entry: String, mode: U32, room: Nat) -> EvSt:
  # room = Nat.sub(64n, len): saturates, so 0 means len >= 64 (at cap or over)
  match room:
    case 0n: EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, mode}
    case _: EvS{sel, items, tfocus, dirty, quit, writes, vs, entry_append(entry, code), mode}

def tick_entry_printable_ok(code: U32, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, +entry: String, mode: U32, ok: Bool) -> EvSt:
  match ok:
    case True{}:
      # Limit entry to 64 chars to prevent unbounded growth
      tick_entry_printable_len(code, sel, items, tfocus, dirty, quit, writes, vs, entry, mode, Nat.sub(64n, String.length(entry)))
    case False{}: EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, mode}

def tick_entry_printable(+code: U32, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, entry: String, mode: U32) -> EvSt:
  tick_entry_printable_ok(code, sel, items, tfocus, dirty, quit, writes, vs, entry, mode, Bool.and(U32.is_le(32, code), U32.is_le(code, 126)))

def tick_entry_commit_go(+sel: U32, +items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, entry: String, mode: U32) -> EvSt:
  match mode:
    # Add mode 1-4: theme = mode-1
    case 1: EvS{sel, append_item(items, Con{item_plain(entry, 0), Nil{}}), tfocus, True{}, quit, writes, vs, "", 0}
    case 2: EvS{sel, append_item(items, Con{item_plain(entry, 1), Nil{}}), tfocus, True{}, quit, writes, vs, "", 0}
    case 3: EvS{sel, append_item(items, Con{item_plain(entry, 2), Nil{}}), tfocus, True{}, quit, writes, vs, "", 0}
    case 4: EvS{sel, append_item(items, Con{item_plain(entry, 3), Nil{}}), tfocus, True{}, quit, writes, vs, "", 0}
    # Edit mode 5: replace title only; note/saved_at/url are preserved.
    case 5: EvS{sel, items_retitle_at(items, sel, entry), tfocus, True{}, quit, writes, vs, "", 0}
    case _: EvS{sel, items, tfocus, dirty, quit, writes, vs, "", 0}

def tick_entry_commit_len(sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, entry: String, mode: U32, len: Nat) -> EvSt:
  # Don't commit empty titles
  match len:
    case 0n: EvS{sel, items, tfocus, dirty, quit, writes, vs, "", 0}
    case _: tick_entry_commit_go(sel, items, tfocus, dirty, quit, writes, vs, entry, mode)

def tick_entry_commit(sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, +entry: String, mode: U32) -> EvSt:
  tick_entry_commit_len(sel, items, tfocus, dirty, quit, writes, vs, entry, mode, String.length(entry))

# Digit keys 0-3: theme select in add mode, literal chars in edit mode.
def tick_entry_digit(code: U32, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, entry: String, mode: U32, theme: U32) -> EvSt:
  match mode:
    case 5: tick_entry_printable(code, sel, items, tfocus, dirty, quit, writes, vs, entry, mode)
    case _: tick_entry_theme(sel, items, tfocus, dirty, quit, writes, vs, entry, mode, theme)

def tick_entry_key(code: U32, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, entry: String, mode: U32) -> EvSt:
  match code:
    # Esc (27): cancel
    case 27: EvS{sel, items, tfocus, dirty, quit, writes, vs, "", 0}
    # Enter (13): commit
    case 13: tick_entry_commit(sel, items, tfocus, dirty, quit, writes, vs, entry, mode)
    # Backspace (8): delete last char
    case 8: EvS{sel, items, tfocus, dirty, quit, writes, vs, entry_backspace(entry), mode}
    # Theme 0-3 in add mode (48-51); literal digits in edit mode
    case 48: tick_entry_digit(code, sel, items, tfocus, dirty, quit, writes, vs, entry, mode, 0)
    case 49: tick_entry_digit(code, sel, items, tfocus, dirty, quit, writes, vs, entry, mode, 1)
    case 50: tick_entry_digit(code, sel, items, tfocus, dirty, quit, writes, vs, entry, mode, 2)
    case 51: tick_entry_digit(code, sel, items, tfocus, dirty, quit, writes, vs, entry, mode, 3)
    # Printable ASCII (32-126): append (max 64 chars)
    case _: tick_entry_printable(code, sel, items, tfocus, dirty, quit, writes, vs, entry, mode)

def tick_ev_delete_items(sel: U32, +new_items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt) -> EvSt:
  EvS{sel_clamp(sel, items_count(new_items)), new_items, tfocus, True{}, quit, writes, vs, "", 0}

def tick_ev_delete_go(+sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt) -> EvSt:
  tick_ev_delete_items(sel, items_remove_at(items, sel), tfocus, dirty, quit, writes, vs)

def tick_ev_delete_count(sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, count: U32) -> EvSt:
  match count:
    case 0: EvS{sel, items, tfocus, dirty, quit, writes, vs, "", 0}  # nothing to delete
    case _: tick_ev_delete_go(sel, items, tfocus, dirty, quit, writes, vs)

def tick_ev_delete(sel: U32, +items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt) -> EvSt:
  tick_ev_delete_count(sel, items, tfocus, dirty, quit, writes, vs, items_count(items))

# Truncate a preloaded edit title to the 64-char entry cap.
# k = min(64, len) via saturating subtraction: len - (len - 64).
# Rebuilds the first k chars; entry_bs_append skips a missing char harmlessly.
def entry_trunc64_go(+k: Nat, +s: String, +idx: Nat, acc: String) -> String:
  match k:
    case 0n: acc
    case 1n+m: entry_trunc64_go(m, s, Nat.add(idx, 1n), entry_bs_append(acc, String.get(s, idx)))

def entry_trunc64_len(+entry: String, +len: Nat) -> String:
  entry_trunc64_go(Nat.sub(len, Nat.sub(len, 64n)), entry, 0n, "")

def entry_trunc64(+entry: String) -> String:
  entry_trunc64_len(entry, String.length(entry))

def tick_ev_crud_key(code: U32, +sel: U32, +items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, feed: String) -> EvSt:
  match code:
    case 97: EvS{sel, items, tfocus, dirty, quit, writes, vs, "", 1}  # 'a': add mode, theme 0
    case 101: EvS{sel, items, tfocus, dirty, quit, writes, vs, entry_trunc64(items_get_title(items, sel)), 5}  # 'e': edit mode
    case 100: tick_ev_delete(sel, items, tfocus, dirty, quit, writes, vs)  # 'd': delete
    case _: tick_ev_s_unfocused(Key{code, True{}}, sel, items, tfocus, dirty, quit, writes, vs, feed)

def tick_ev_normal_key_rf(code: U32, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, rf: Bool, feed: String) -> EvSt:
  match rf:
    case True{}: tick_ev_s_unfocused(Key{code, True{}}, sel, items, tfocus, dirty, quit, writes, vs, feed)
    case False{}: tick_ev_crud_key(code, sel, items, tfocus, dirty, quit, writes, vs, feed)

def tick_ev_normal_key_unfocused(code: U32, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt, +feed: String) -> EvSt:
  tick_ev_normal_key_rf(code, sel, items, tfocus, dirty, quit, writes, vs, viewst_rfocus(vs), feed)

def tick_ev_normal_event(e: Event, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, feed: String) -> EvSt:
  match tfocus:
    case True{}: tick_ev_s_focused(e, sel, items, dirty, quit, writes, vs)
    case False{}: tick_ev_s_unfocused(e, sel, items, tfocus, dirty, quit, writes, vs, feed)

# ---------- terminal scrollback viewer: fold sidecar ----------
# SbSt accumulates one tick's scrollback-view requests from the
# terminal-focused key path (same sidecar pattern as TabSt/ProfSt/FetchSt;
# EvSt's 9 fields stay frozen so test_crud2.bend compiles unchanged):
#   up   = lines to scroll back (PgUp adds 24 per press, accumulates)
#   down = lines to scroll toward live (PgDn adds 24 per press, accumulates)
# (SbSt type is declared above, next to FoldSt.)
def sb_none() -> SbSt:
  SbS{0, 0, False{}}

def sb_up_add(+sb: SbSt, +n: U32) -> SbSt:
  match sb:
    case SbS{up, down, live}: SbS{U32.add(up, n), down, live}

def sb_down_add(+sb: SbSt, +n: U32) -> SbSt:
  match sb:
    case SbS{up, down, live}: SbS{up, U32.add(down, n), live}

def sb_go_live() -> SbSt:
  SbS{0, 0, True{}}

# True iff the tick issued any scroll request: forces a frame rebuild,
# because the Term value changes even though no new output arrived.
def sb_touched_go(+live: Bool, +up: U32, +down: U32) -> Bool:
  match live:
    case True{}: True{}
    case False{}: Bool.or(bool_not(U32.is_eq(up, 0)), bool_not(U32.is_eq(down, 0)))

def sb_touched(+sb: SbSt) -> Bool:
  match sb:
    case SbS{up, down, live}: sb_touched_go(live, up, down)

def sb_apply_sb(+sb: SbSt, +t: Term) -> Term:
  match sb:
    case SbS{up, down, live}: sb_apply(up, down, live, t)

# Scroll-aware focused-terminal key path. PgUp/PgDn scroll the view and
# must NOT reach the PTY (the old path would write Char.show(Chr{63276})
# garbage into the shell); every other key keeps the old behavior and
# resets the view to live.
def tick_ev_fkey_down_sb(code: U32, sel: U32, items: List<&2, Item>, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt, +sb: SbSt) -> (EvSt & SbSt):
  match code:
    case 63276: (EvS{sel, items, True{}, dirty, quit, writes, vs, "", 0}, sb_up_add(sb, 24))
    case 63277: (EvS{sel, items, True{}, dirty, quit, writes, vs, "", 0}, sb_down_add(sb, 24))
    case _: (tick_ev_fkey_down(code, sel, items, dirty, quit, writes, vs), sb_go_live())

def tick_ev_fkey_sb(code: U32, down: Bool, sel: U32, items: List<&2, Item>, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt, +sb: SbSt) -> (EvSt & SbSt):
  match down:
    case False{}: (tick_ev_fkey(code, down, sel, items, dirty, quit, writes, vs), sb)
    case True{}: tick_ev_fkey_down_sb(code, sel, items, dirty, quit, writes, vs, sb)

def tick_ev_s_focused_sb(e: Event, sel: U32, items: List<&2, Item>, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt, +sb: SbSt) -> (EvSt & SbSt):
  match e:
    case Key{code, down}: tick_ev_fkey_sb(code, down, sel, items, dirty, quit, writes, vs, sb)
    case _: (tick_ev_act(event_action(e), sel, items, True{}, dirty, quit, writes, vs), sb)

def tick_ev_normal_key_sb(code: U32, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, feed: String, +sb: SbSt) -> (EvSt & SbSt):
  match tfocus:
    case True{}: tick_ev_s_focused_sb(Key{code, True{}}, sel, items, dirty, quit, writes, vs, sb)
    case False{}: (tick_ev_normal_key_unfocused(code, sel, items, tfocus, dirty, quit, writes, vs, feed), sb)

# Pair a scrolled EvSt back into the 6-field fold state.
def fst_with_sb(evsb: EvSt & SbSt, ms: MouseSt, ts: TabSt, ps: ProfSt, fs: FetchSt) -> FoldSt:
  match evsb:
    case (ev, sb): FSt{ev, ms, ts, ps, fs, sb}

# Handle 'a' (97), 'e' (101), 'd' (100) in normal mode when not terminal-focused
# and reader not focused. Otherwise delegate to the standard handlers.

def tick_ev_normal_key(code: U32, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, feed: String) -> EvSt:
  match tfocus:
    case True{}: tick_ev_s_focused(Key{code, True{}}, sel, items, dirty, quit, writes, vs)
    case False{}: tick_ev_normal_key_unfocused(code, sel, items, tfocus, dirty, quit, writes, vs, feed)

# Key-up: respect terminal focus (a focused key-up is a no-op that keeps tfocus,
# not an unfocused-path event).
def tick_ev_normal_keyup(code: U32, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, feed: String) -> EvSt:
  match tfocus:
    case True{}: tick_ev_s_focused(Key{code, False{}}, sel, items, dirty, quit, writes, vs)
    case False{}: tick_ev_s_unfocused(Key{code, False{}}, sel, items, tfocus, dirty, quit, writes, vs, feed)

# PINNED 8-arg signature (test_crud2.bend calls this directly). Feed is
# irrelevant on the paths reachable here (keyup / non-key events never scroll
# the reader), so "" is passed through.
def tick_ev_single_normal(e: Event, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt) -> EvSt:
  match e:
    case Key{code, down}:
      match down:
        case True{}: tick_ev_normal_key(code, sel, items, tfocus, dirty, quit, writes, vs, "")
        case False{}: tick_ev_normal_keyup(code, sel, items, tfocus, dirty, quit, writes, vs, "")
    case _: tick_ev_normal_event(e, sel, items, tfocus, dirty, quit, writes, vs, "")

def tick_ev_single_entry(e: Event, sel: U32, items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, vs: ViewSt, entry: String, entry_mode: U32) -> EvSt:
  match e:
    case Key{code, down}:
      match down:
        case True{}: tick_entry_key(code, sel, items, tfocus, dirty, quit, writes, vs, entry, entry_mode)
        case False{}: EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, entry_mode}
    case _: EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, entry_mode}

# Normal mode: check for CRUD keys ('a'/'e'/'d') when unfocused, else delegate.

# Pass 1 (pure): fold events into a FoldSt{EvSt, MouseSt, TabSt}.
# tick_ev_go2 recurses on the event list; tick_ev_single and all helpers
# below are NON-recursive. The EvSt half folds exactly as before
# (tick_ev_single_normal / tick_ev_single_entry untouched); the TabSt half
# intercepts the four tab keys on key-DOWN in normal mode with the terminal
# unfocused and the reader unfocused.
# (Defs are ordered bottom-up: Bend requires each def to precede its uses.)

# Tab keys fire only with the terminal unfocused and the reader unfocused.
# (Entry mode never reaches here: tick_ev_single2 routes it to the entry
# path, where '{'/'}'/'+'/'-' stay printable entry text.)
def tab_key_allowed(+tfocus: Bool, +rfocus: Bool) -> Bool:
  match tfocus:
    case True{}: False{}
    case False{}:
      match rfocus:
        case True{}: False{}
        case False{}: True{}

# Profile key: 'p' (112). NOTE on the brief's "P (80)": the window effect
# (bend2/effs/window_frame.c: window_key) LOWERCASES A-Z before delivering
# key codes, so code 80 can never arrive from a real keyboard — Shift+P and
# plain p both deliver 112. 112 is unbound in key_code_action and in
# tick_ev_crud_key (verified by reading both), so the EvSt half ignores it
# and the ProfSt half intercepts it here, exactly like the four tab keys.
# Gate: normal mode, terminal unfocused, reader unfocused (same
# tab_key_allowed gate; entry mode routes to tick_ev_single_entry where p
# stays printable text, a focused terminal receives a literal "p", and a
# focused reader uses p for prev-article).
def prof_key_pending(+code: U32) -> Bool:
  match code:
    case 112: True{}
    case _: False{}

def prof_fire_go(+is_p: Bool, +cur: String, +old: String) -> ProfSt:
  match is_p:
    case True{}:
      # N p-presses in one batch compose to N sequential switches: advance
      # from the already-accumulated pending (old), not the tick-start cur.
      # pending is always a valid profile name (produced by profile_next),
      # so SNil means "no press yet this batch" -> step from cur. Note
      # profile_next("") is "default", hence the explicit empty check.
      # cur is unchanged by the fold, so the executor contract (save the
      # fold's items to cur's file, load pending's file) holds verbatim.
      match old:
        case SNil{}: PSt{cur, profile_next(cur)}
        case SCon{_, _}: PSt{cur, profile_next(old)}
    case False{}: PSt{cur, old}

def prof_fire_go2(+is_p: Bool, +allowed: Bool, +cur: String, +old: String) -> ProfSt:
  match allowed:
    case True{}: prof_fire_go(is_p, cur, old)
    case False{}: PSt{cur, old}

# 'f' (102) requests a live-feed fetch. 'h' (104) requests the same article
# via real verified HTTPS (news.ycombinator.com/rss through the TLS bridge).
# Gate: terminal unfocused (a focused terminal receives the literal key;
# entry mode never reaches this chain). Works in normal AND reader-focused
# modes (unlike tab/profile keys). The window effect lowercases A-Z, so only
# the lowercase codes matter.
def fetch_key_pending(+code: U32) -> Bool:
  match code:
    case 102: True{}
    case _: False{}

def hfetch_key_pending(+code: U32) -> Bool:
  match code:
    case 104: True{}
    case _: False{}

def fetch_fire_pick(+fire: Bool, +old: Bool) -> Bool:
  match fire:
    case True{}: True{}
    case False{}: old

def fetch_fire_go(+allowed: Bool, +is_f: Bool, +old: Bool) -> Bool:
  fetch_fire_pick(Bool.and(allowed, is_f), old)

def tick_ev_keydown_fire(+p: U32, +allowed: Bool, +old_pending: U32, +code: U32, sel: U32, +items: List<&2, Item>, +tfocus: Bool, +dirty: Bool, +quit: Bool, +writes: TtyWList, +vs: ViewSt, ms: MouseSt, +tab_idx: U32, +cur: String, +ppend: String, +fpend: Bool, +hpend: Bool, +feed: String, +sb: SbSt) -> FoldSt:
  match allowed:
    case True{}: fst_with_sb(tick_ev_normal_key_sb(code, sel, items, tfocus, dirty, quit, writes, vs, feed, sb), ms, TSt{tab_idx, p}, prof_fire_go(prof_key_pending(code), cur, ppend), FchSt{fetch_fire_go(bool_not(tfocus), fetch_key_pending(code), fpend), fetch_fire_go(bool_not(tfocus), hfetch_key_pending(code), hpend), feed})
    case False{}: fst_with_sb(tick_ev_normal_key_sb(code, sel, items, tfocus, dirty, quit, writes, vs, feed, sb), ms, TSt{tab_idx, old_pending}, PSt{cur, ppend}, FchSt{fpend, hpend, feed})

def tick_ev_keydown2(+pend: U32, +code: U32, sel: U32, +items: List<&2, Item>, +tfocus: Bool, +dirty: Bool, +quit: Bool, +writes: TtyWList, +vs: ViewSt, ms: MouseSt, +tab_idx: U32, +pending: U32, +cur: String, +ppend: String, +fpend: Bool, +hpend: Bool, +feed: String, +sb: SbSt) -> FoldSt:
  match pend:
    case 0: fst_with_sb(tick_ev_normal_key_sb(code, sel, items, tfocus, dirty, quit, writes, vs, feed, sb), ms, TSt{tab_idx, pending}, prof_fire_go2(prof_key_pending(code), tab_key_allowed(tfocus, viewst_rfocus(vs)), cur, ppend), FchSt{fetch_fire_go(bool_not(tfocus), fetch_key_pending(code), fpend), fetch_fire_go(bool_not(tfocus), hfetch_key_pending(code), hpend), feed})
    case p: tick_ev_keydown_fire(p, tab_key_allowed(tfocus, viewst_rfocus(vs)), pending, code, sel, items, tfocus, dirty, quit, writes, vs, ms, tab_idx, cur, ppend, fpend, hpend, feed, sb)

def tick_ev_keydown_ps(ps: ProfSt, fs: FetchSt, +code: U32, sel: U32, +items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt, ms: MouseSt, +tab_idx: U32, +pending: U32, +sb: SbSt) -> FoldSt:
  match ps:
    case PSt{cur, ppend}:
      match fs:
        case FchSt{fpend, hpend, feed}: tick_ev_keydown2(tab_key_pending(code), code, sel, items, tfocus, dirty, quit, writes, vs, ms, tab_idx, pending, cur, ppend, fpend, hpend, feed, sb)

def tick_ev_keydown(+code: U32, sel: U32, +items: List<&2, Item>, tfocus: Bool, dirty: Bool, quit: Bool, writes: TtyWList, +vs: ViewSt, ms: MouseSt, ts: TabSt, ps: ProfSt, fs: FetchSt, +sb: SbSt) -> FoldSt:
  match ts:
    case TSt{tab_idx, pending}:
      tick_ev_keydown_ps(ps, fs, code, sel, items, tfocus, dirty, quit, writes, vs, ms, tab_idx, pending, sb)

def tick_ev_single_normal2(+e: Event, sel: U32, +items: List<&2, Item>, +tfocus: Bool, +dirty: Bool, +quit: Bool, +writes: TtyWList, +vs: ViewSt, +ms: MouseSt, +ts: TabSt, +ps: ProfSt, +fs: FetchSt, +sb: SbSt) -> FoldSt:
  match e:
    case Key{code, down}:
      match down:
        case True{}: tick_ev_keydown(code, sel, items, tfocus, dirty, quit, writes, vs, ms, ts, ps, fs, sb)
        # Key-up and non-key events never touch the scrollback view (the
        # pinned tick_ev_single_normal path); the sidecar passes through.
        case False{}: FSt{tick_ev_single_normal(e, sel, items, tfocus, dirty, quit, writes, vs), ms, ts, ps, fs, sb}
    case _: FSt{tick_ev_single_normal(e, sel, items, tfocus, dirty, quit, writes, vs), ms, ts, ps, fs, sb}

def tick_ev_single2(+e: Event, ev: EvSt, +ms: MouseSt, +ts: TabSt, +ps: ProfSt, +fs: FetchSt, +sb: SbSt) -> FoldSt:
  match ev:
    case EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, entry_mode}:
      match entry_mode:
        case 0: tick_ev_single_normal2(e, sel, items, tfocus, dirty, quit, writes, vs, ms, ts, ps, fs, sb)
        case _: FSt{tick_ev_single_entry(e, sel, items, tfocus, dirty, quit, writes, vs, entry, entry_mode), ms, ts, ps, fs, sb}

def tick_ev_single(e: Event, fst: FoldSt) -> FoldSt:
  match fst:
    case FSt{ev, ms, ts, ps, fs, sb}: tick_ev_single2(e, ev, ms, ts, ps, fs, sb)

# Single-pass event fold over the FoldSt{EvSt, MouseSt, TabSt, ...} sextuple.
# Move events update ONLY the mouse state (last Move wins); every other event
# goes through tick_ev_single, which folds EvSt exactly as before and lets
# the TabSt half intercept the four tab keys. A mouse-move flood therefore
# costs ~2 calls per event and never touches EvSt.
# tick_ev_go2's old (EvSt, MouseSt) pair signature is gone; the CRUD-compat
# wrapper tick_ev_go below keeps the pinned 2-arg signature for
# test_crud2.bend.
# Move events rebuild the FoldSt with fresh mouse state (non-recursive
# helper so tick_ev_go2 stays simply recursive, not mutual).
def fold_move_fst(+x: U32, +y: U32, fst: FoldSt) -> FoldSt:
  match fst:
    case FSt{ev, ms, ts, ps, fs, sb}: FSt{ev, tick_ev_move(x, y), ts, ps, fs, sb}

def tick_ev_go2(evs: List<Event>, fst: FoldSt) -> FoldSt:
  match evs:
    case Nil{}: fst
    case e <> rest:
      match e:
        case Move{x, y}: tick_ev_go2(rest, fold_move_fst(x, y, fst))
        case _: tick_ev_go2(rest, tick_ev_single(e, fst))

def tick_ev_go_fst(fst: FoldSt) -> EvSt:
  match fst:
    case FSt{ev, _, _, _, _, _}: ev

# Compat wrapper: original (List<Event>, EvSt) -> EvSt signature, kept for
# test_crud2.bend. Move events are EvSt-neutral, so the fold result matches.
def tick_ev_go(evs: List<Event>, st: EvSt) -> EvSt:
  tick_ev_go_fst(tick_ev_go2(evs, FSt{st, MSt{0, 0, 0}, TSt{0, 0}, PSt{"default", ""}, FchSt{False{}, False{}, ""}, sb_none()}))

# ---------- live terminal ----------




# Send queued terminal input to the pty (concatenated into one write).
def concat_writes(writes: TtyWList) -> String:
  match writes:
    case TtyWNil{}: ""
    case TtyWCons{w, rest}: String.append(concat_writes(rest), w)

def do_writes_done(wr: Pty & Result<&1,&1, U32 & String, Unit>) -> IO(Pty):
  match wr:
    case (pty2, res): IO.pure(Pty, pty2)

def do_writes(writes: TtyWList, pty: Pty) -> IO(Pty):
  do IO<Pty>:
    wr : Pty & Result<&1,&1, U32 & String, Unit> <- Pty.write(pty, concat_writes(writes))
    do_writes_done(wr)


# Poll the pty (non-blocking); feed output into the terminal emulator.
# Returns (pty, term, changed).
def tick_poll_len(pty: Pty, term: Term, +out: String, n: Nat) -> IO(Pty & Term & Bool):
  match n:
    case 0n: IO.pure(Pty & Term & Bool, (pty, term, False{}))
    case 1n+m: IO.pure(Pty & Term & Bool, (pty, term_write(out, term), True{}))

def tick_poll_done(pty: Pty, term: Term, +out: String) -> IO(Pty & Term & Bool):
  tick_poll_len(pty, term, out, String.length(out))

def tick_poll_res(pty: Pty, term: Term, rres: Result<&1,&1, U32 & String, String>) -> IO(Pty & Term & Bool):
  match rres:
    case Fail{e}: IO.pure(Pty & Term & Bool, (pty, term, False{}))
    case Done{out}: tick_poll_done(pty, term, out)

def tick_poll_go(rr: Pty & Result<&1,&1, U32 & String, String>, term: Term) -> IO(Pty & Term & Bool):
  match rr:
    case (pty2, rres): tick_poll_res(pty2, term, rres)

def tick_poll(pty: Pty, term: Term) -> IO(Pty & Term & Bool):
  do IO<Pty & Term & Bool>:
    rr : Pty & Result<&1,&1, U32 & String, String> <- Pty.read(pty, 4096)
    tick_poll_go(rr, term)

def pty_close_maybe(pty_m: MaybePty) -> IO(Unit):
  match pty_m:
    case NoPty{}: IO.pure(Unit, Unit{})
    case YesPty{pty}: Pty.close(pty)

# ---------- session restore integration (Wave 1, NEXT_WAVE2) ----------
# Pure extraction of the persisted UI surface from tick state, change
# detection (one Bool threaded through the IO pass — no new SSt/AccSt
# fields), and boot-time restore. SessSt itself plus serialize/parse and
# the file protocol live in shell.bend.
# (acc_gmail_open_q / acc_ai_open_q / acc_gmail_inner / acc_ai_inner are
# hoisted here from the accretive-panels section: defs must precede use.)

def acc_gmail_open_q(+m: MailSt) -> Bool:
  match m:
    case MOff{}: False{}
    case _: True{}

def acc_ai_open_q(+a: AISt) -> Bool:
  match a:
    case AOff{}: False{}
    case _: True{}

def acc_gmail_inner(+acc: AccSt) -> MailSt:
  match acc:
    case Acc{_, _, _, gmail, _, _, _, _, _, _, help}: gmail

def acc_ai_inner(+acc: AccSt) -> AISt:
  match acc:
    case Acc{_, _, _, _, ai, _, _, _, _, _, help}: ai

def acc_search_is_open(+acc: AccSt) -> Bool:
  match acc:
    case Acc{_, open, _, _, _, _, _, _, _, _, help}: open

def acc_search_q(+acc: AccSt) -> String:
  match acc:
    case Acc{q, _, _, _, _, _, _, _, _, _, help}: q

def acc_search_sel(+acc: AccSt) -> U32:
  match acc:
    case Acc{_, _, sel, _, _, _, _, _, _, _, help}: sel

def viewst_rscroll_of(+vs: ViewSt) -> U32:
  match vs:
    case VSt{_, _, _, rscroll, _}: rscroll

def viewst_rart_of(+vs: ViewSt) -> U32:
  match vs:
    case VSt{_, _, rart, _, _}: rart

def prof_cur(+ps: ProfSt) -> String:
  match ps:
    case PSt{cur, _}: cur

# Focus encoding: 0 = sidebar, 1 = reader, 2 = terminal, 3 = gmail, 4 = ai.
# Priority matches key routing: a focused terminal wins over reader; gmail
# and ai are open-overlay tiles (open ~= focused when nothing else is).
def sess_focus_enc_a(+a: Bool) -> U32:
  match a:
    case True{}: 4
    case False{}: 0

def sess_focus_enc_g(+g: Bool, +acc: AccSt) -> U32:
  match g:
    case True{}: 3
    case False{}: sess_focus_enc_a(acc_ai_open_q(acc_ai_inner(acc)))

def sess_focus_enc_r(+rf: Bool, +acc: AccSt) -> U32:
  match rf:
    case True{}: 1
    case False{}: sess_focus_enc_g(acc_gmail_open_q(acc_gmail_inner(acc)), acc)

def sess_focus_enc(+tfocus: Bool, +vs: ViewSt, +acc: AccSt) -> U32:
  match tfocus:
    case True{}: 2
    case False{}: sess_focus_enc_r(viewst_rfocus(vs), acc)

def sess_of(+tfocus: Bool, +vs: ViewSt, +tabs: List<&2, Tab>, +tab_idx: U32, +sel: U32, +acc: AccSt, +profile: String) -> SessSt:
  Sess{sess_focus_enc(tfocus, vs, acc), term_view_off(tab_term(tabs_get(tabs, tab_idx))), acc_search_is_open(acc), acc_search_q(acc), acc_search_sel(acc), sel, viewst_page(vs), viewst_rart_of(vs), viewst_rscroll_of(vs), tab_idx, profile, acc_gmail_open_q(acc_gmail_inner(acc)), acc_ai_open_q(acc_ai_inner(acc))}

# True iff any persisted view field changed between the tick's old and new
# state (rlines is derived from rart/feed, so rart covers it).
def sess_bool_xor(+a: Bool, +b: Bool) -> Bool:
  match a, b:
    case True{}, True{}: False{}
    case False{}, False{}: False{}
    case _, _: True{}

def sess_vs_changed(+vs: ViewSt, +vs2: ViewSt) -> Bool:
  match vs:
    case VSt{page, rf, rart, rscroll, _}:
      match vs2:
        case VSt{page2, rf2, rart2, rscroll2, _}:
          Bool.or(bool_not(U32.is_eq(page, page2)),
          Bool.or(sess_bool_xor(rf, rf2),
          Bool.or(bool_not(U32.is_eq(rart, rart2)),
                  bool_not(U32.is_eq(rscroll, rscroll2)))))

# Session-relevant change this tick: sidebar selection, terminal focus,
# any view field, any accretive panel touch (search/gmail/ai/note —
# accd is exactly that signal), scrollback-view request, or tab switch.
def sess_save_of(+sel: U32, +sel2: U32, +tfocus: Bool, +tfocus2: Bool, +vs: ViewSt, +vs2: ViewSt, +tchanged: U32, +sb: SbSt, +acc: AccSt) -> Bool:
  Bool.or(sess_vs_changed(vs, vs2),
  Bool.or(bool_not(U32.is_eq(sel, sel2)),
  Bool.or(bool_not(bool_eq(tfocus, tfocus2)),
  Bool.or(acc_is_touched(acc),
  Bool.or(sb_touched(sb), bool_not(U32.is_eq(tchanged, 0)))))))

def tick_save_session_go(+save: Bool, +sess: SessSt) -> IO(Bool):
  match save:
    case False{}: IO.pure(Bool, False{})
    case True{}: save_session(sess)

# ---------- boot-time restore (pure) ----------

def sess_tfocus_restore(+s: SessSt) -> Bool:
  U32.is_eq(sess_focus_of(s), 2)

def sess_rfocus_restore(+s: SessSt) -> Bool:
  U32.is_eq(sess_focus_of(s), 1)

def sess_vs_restore(+s: SessSt, +feed0: String) -> ViewSt:
  VSt{sess_page_of(s), sess_rfocus_restore(s),
      u32_min(sess_rart_of(s), u32_sub_sat(reader_n_arts(), 1)),
      sess_rscroll_of(s), reader_lines(u32_min(sess_rart_of(s), u32_sub_sat(reader_n_arts(), 1)), feed0)}

def sess_gmail_restore(+open: Bool) -> MailSt:
  match open:
    case True{}: MOn{MUnknown{}}
    case False{}: MOff{}

def sess_ai_restore(+open: Bool) -> AISt:
  match open:
    case True{}: AOn{AIUnknown{}}
    case False{}: AOff{}

# Restored gmail/ai re-run the config check on the first IO pass
# (MUnknown/AIUnknown -> boot); no credentials ever live in SessSt.
def sess_acc_restore(+s: SessSt) -> AccSt:
  Acc{sess_search_q_of(s), sess_search_open_of(s), sess_search_sel_of(s), sess_gmail_restore(sess_gmail_open_of(s)), sess_ai_restore(sess_ai_open_of(s)), NOff{}, False{}, False{}, None{}, Pal{"", False{}, 0, 0}, HOff{}}

def tick_save_items(+items: List<&2, Item>, +dirty: Bool, +profile: String) -> IO(Bool):
  match dirty:
    case False{}: IO.pure(Bool, False{})
    case True{}: save_items_file(items, profile_file(profile))

# ---------- dirty-region mask (Wave 4) ----------
# Maps each per-tick state diff to the base regions it dirties. Anything
# unattributable forces dirty_all() -> the full-frame fallback:
#   - entry-mode change (the entry bar is a separate layer, redrawn anyway)
#   - acc touched (accretive panel mutation)
#   - any accretive overlay visible (base redraws would paint over it)
#   - profile switch (explicit flag from tick_tab_save_pend)
def dirty_ov_open(+acc: AccSt) -> Bool:
  match acc:
    case Acc{_, _, _, _, _, _, _, _, _, Pal{_, open, _, _}, help}:
      match help:
        case HOn{_}: True{}
        case HOff{}: Bool.or(pal_any_open(acc), open)

# The dirty path is usable only for masks 1..30 (a non-empty strict subset of
# region bits); an empty, invalid, or all-dirty mask takes the full-frame
# fallback. (Lives in app.bend: needs bool_not, defined above.)
def dirty_usable(+mask: U32) -> Bool:
  Bool.and(U32.is_ne(mask, 0), U32.is_lt(mask, dirty_all()))

# Field-level ViewSt diff -> dirty mask. Page affects the item grid; reader
# focus/article/scroll affect the reader tile. (rlines is derived from
# rart/feed and never compared by viewst_eq either.)
def viewst_dirty_mask(+m: U32, +a: ViewSt, +b: ViewSt) -> U32:
  match a, b:
    case VSt{p1, f1, a1, s1, _}, VSt{p2, f2, a2, s2, _}:
      dirty_bit(dirty_bit(m, dirty_items(), bool_not(U32.is_eq(p1, p2))),
                dirty_reader(), bool_not(Bool.and(Bool.and(bool_eq(f1, f2), U32.is_eq(a1, a2)), U32.is_eq(s1, s2))))

def tick_dirty_mask_go(+all: Bool, +sel: U32, +sel2: U32, +dirty: Bool, +tchanged: U32, +term_changed: Bool, +tfocus_changed: Bool, +vs: ViewSt, +vs2: ViewSt, +emode: U32, +emode2: U32, +hover: U32, +hover2: U32, +feed: String, +feed2: String) -> U32:
  match all:
    case True{}: dirty_all()
    case False{}:
      +c_chrome = Bool.or(dirty, bool_not(U32.is_eq(sel, sel2)))
      +m0 = dirty_bit(dirty_bit(0, dirty_side(), c_chrome), dirty_items(), c_chrome)
      +c_term = Bool.or(term_changed, Bool.or(tfocus_changed, U32.is_ne(tchanged, 0)))
      +m1 = dirty_bit(m0, dirty_term(), c_term)
      +m2 = viewst_dirty_mask(m1, vs, vs2)
      +m3 = dirty_bit(m2, dirty_side(), bool_not(U32.is_eq(hover, hover2)))
      +m4 = dirty_bit(m3, dirty_reader(), bool_not(String.eq(feed, feed2)))
      dirty_bit(m4, dirty_all(), bool_not(U32.is_eq(emode, emode2)))

def tick_dirty_mask(+sel: U32, +sel2: U32, +dirty: Bool, +tchanged: U32, +term_changed: Bool, +tfocus_changed: Bool, +vs: ViewSt, +vs2: ViewSt, +emode: U32, +emode2: U32, +hover: U32, +hover2: U32, +feed: String, +feed2: String, +acc: AccSt, +force_full: Bool) -> U32:
  tick_dirty_mask_go(Bool.or(force_full, Bool.or(acc_is_touched(acc), dirty_ov_open(acc))), sel, sel2, dirty, tchanged, term_changed, tfocus_changed, vs, vs2, emode, emode2, hover, hover2, feed, feed2)

# Dirty rebuild: re-rasterize only the masked regions onto the cached frame,
# then redraw the entry bar, preserving shell_state's base -> entry-bar
# layer order. acc_render is skipped: this path is taken only when no
# accretive overlay is visible and acc is untouched, in which case
# acc_render is the identity. acc_untouch keeps the stored state clean.
def shell_state_dirty(+d: Nat, +sel2: U32, +items2: List<&2, Item>, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus2: Bool, +vs2: ViewSt, +entry2: String, +entry_mode2: U32, +mx2: U32, +my2: U32, +hover2: U32, +profile: String, +feed2: String, +acc: AccSt, frame: Image, +mask: U32) -> ShellSt:
  +base = shell_render_dirty(d, frame, mask, theme_dark(), sel2, items2, tab_term(tabs_get(tabs, tab_idx)), tfocus2, vs2, hover2, tab_idx, tabs_count(tabs), profile)
  +framed = draw_entry_bar(d, base, acc_note_bar_text(acc, entry2), acc_note_bar_mode(acc, entry_mode2))
  SSt{sel2, d, items2, framed, tabs, tab_idx, tfocus2, vs2, entry2, entry_mode2, mx2, my2, hover2, profile, feed2, acc_untouch(acc)}

def tick_rebuild_go3(+usable: Bool, +mask: U32, +d: Nat, +sel2: U32, +items2: List<&2, Item>, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus2: Bool, +vs2: ViewSt, +entry2: String, +entry_mode2: U32, +mx2: U32, +my2: U32, +hover2: U32, +profile: String, +feed2: String, +acc: AccSt) -> Maybe<ShellSt>:
  match usable:
    # Dirty path: only the changed regions are re-rasterized.
    case True{}: Some{shell_state_dirty(d, sel2, items2, tabs, tab_idx, tfocus2, vs2, entry2, entry_mode2, mx2, my2, hover2, profile, feed2, acc, frame, mask)}
    # Full-frame fallback: overlay transitions, profile switch, resize,
    # empty/invalid mask, or anything the mask could not attribute.
    case False{}: Some{shell_state(d, sel2, items2, tabs, tab_idx, tfocus2, vs2, entry2, entry_mode2, mx2, my2, hover2, profile, feed2, acc_untouch(acc))}

def tick_rebuild_go2(+need2: Bool, +mask: U32, +d: Nat, +sel2: U32, +items2: List<&2, Item>, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus2: Bool, +vs2: ViewSt, +entry2: String, +entry_mode2: U32, +mx2: U32, +my2: U32, +hover2: U32, +profile: String, +feed2: String, +acc: AccSt) -> Maybe<ShellSt>:
  match need2:
    case True{}: tick_rebuild_go3(dirty_usable(mask), mask, d, sel2, items2, frame, tabs, tab_idx, tfocus2, vs2, entry2, entry_mode2, mx2, my2, hover2, profile, feed2, acc)
    case False{}:
      # Reuse frame but overlay entry bar if in entry mode (entry text may have changed)
      +framed = draw_entry_bar(d, frame, acc_note_bar_text(acc, entry2), acc_note_bar_mode(acc, entry_mode2))
      Some{SSt{sel2, d, items2, framed, tabs, tab_idx, tfocus2, vs2, entry2, entry_mode2, mx2, my2, hover2, profile, feed2, acc}}

def tick_rebuild_go(+d: Nat, +sel2: U32, +items2: List<&2, Item>, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus2: Bool, +vs2: ViewSt, +entry2: String, +entry_mode2: U32, +mx2: U32, +my2: U32, +hover2: U32, need: Bool, +mask: U32, +profile: String, +feed2: String, +acc: AccSt) -> Maybe<ShellSt>:
  # accd forces a rebuild whenever an accretive panel changed this tick;
  # the flag is cleared on rebuild so the stored state is clean.
  # (The mask already forces dirty_all() when accd is set, so the dirty
  # path is unreachable on this arm; the OR is kept for defense in depth.)
  tick_rebuild_go2(Bool.or(need, acc_is_touched(acc)), mask, d, sel2, items2, frame, tabs, tab_idx, tfocus2, vs2, entry2, entry_mode2, mx2, my2, hover2, profile, feed2, acc)

def tick_need(+sel: U32, +sel2: U32, +dirty: Bool, +term_changed: Bool, +tfocus_changed: Bool, +vs: ViewSt, +vs2: ViewSt, +emode: U32, +emode2: U32) -> Bool:
  Bool.or(Bool.or(term_changed, tfocus_changed),
    Bool.or(dirty, Bool.or(bool_not(U32.is_eq(sel, sel2)), Bool.or(bool_not(viewst_eq(vs, vs2)), bool_not(U32.is_eq(emode, emode2))))))

# Hover-change detection lives OUTSIDE tick_need (whose 9-arg signature is
# pinned by test_crud2.bend): a rebuild fires when the hover TARGET changes.
# Raw mouse-position change alone never rebuilds.
def tick_need_hover(+hover: U32, +hover2: U32, base: Bool) -> Bool:
  Bool.or(base, bool_not(U32.is_eq(hover, hover2)))

# Feed-change detection lives OUTSIDE tick_need too: a successful fetch
# changes feed2, which forces a frame rebuild so the live article appears.
def tick_need_feed(+feed: String, +feed2: String, base: Bool) -> Bool:
  Bool.or(base, bool_not(String.eq(feed, feed2)))

def tick_rebuild(+d: Nat, +sel: U32, +sel2: U32, +items2: List<&2, Item>, +dirty: Bool, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tchanged: U32, +tfocus2: Bool, +vs: ViewSt, +vs2: ViewSt, +term_changed: Bool, +tfocus_changed: Bool, +entry2: String, +entry_mode2: U32, +emode: U32, +hover: U32, +hover2: U32, +mx2: U32, +my2: U32, +profile: String, +feed: String, +feed2: String, +acc: AccSt, +force_full: Bool) -> Maybe<ShellSt>:
  +need = tick_need_feed(feed, feed2, tick_need_hover(hover, hover2, Bool.or(bool_not(U32.is_eq(tchanged, 0)), tick_need(sel, sel2, dirty, term_changed, tfocus_changed, vs, vs2, emode, entry_mode2))))
  +mask = tick_dirty_mask(sel, sel2, dirty, tchanged, term_changed, tfocus_changed, vs, vs2, emode, entry_mode2, hover, hover2, feed, feed2, acc, force_full)
  tick_rebuild_go(d, sel2, items2, frame, tabs, tab_idx, tfocus2, vs2, entry2, entry_mode2, mx2, my2, hover2, need, mask, profile, feed2, acc)

# ---------- terminal tabs: pending-action IO (#5) ----------
#
# The pure event fold only REQUESTS tab actions (TabSt.pending); the effects
# (Pty.spawn / Pty.close) happen here, in Pass 2. shell_tick_pend executes at
# most one pending action per tick and returns the post-action tab list in a
# POut{tabs, tab_idx, tchanged} (tchanged=1 iff the visible tab state changed,
# which forces a frame rebuild in tick_rebuild).
type POut is Data:
  POut{tabs: List<&2, Tab>, tab_idx: U32, tchanged: U32}

# Close every tab's pty (quit path). Single self-recursive def: the do-block
# lives inside the match arm so no helper (and no mutual recursion) is needed.
def tabs_close_all(+tabs: List<&2, Tab>) -> IO(Unit):
  match tabs:
    case Nil{}: IO.pure(Unit, Unit{})
    case t <> rest:
      match t:
        case TTab{mp, _}:
          do IO<Unit>:
            _u : Unit <- pty_close_maybe(mp)
            tabs_close_all(rest)

# --- pending = 1 (new tab): spawn a shell, append, select it.
def tabs_newtab_done2(+tabs: List<&2, Tab>, +new_idx: U32) -> POut:
  POut{tabs, new_idx, 1}

def tabs_newtab_done_fail(+tabs: List<&2, Tab>, +tab_idx: U32) -> POut:
  tabs_newtab_done2(tabs_append(tabs, TTab{NoPty{}, term_dead()}), tabs_count(tabs))

def tabs_newtab_done_ok(+tabs: List<&2, Tab>, +tab_idx: U32, pty: Pty) -> POut:
  tabs_newtab_done2(tabs_append(tabs, TTab{YesPty{pty}, term_new()}), tabs_count(tabs))

def shell_tick_newtab_done(+tabs: List<&2, Tab>, +tab_idx: U32, or_: Result<&1,&1, U32 & String, Pty>) -> IO(POut):
  match or_:
    case Fail{e}: IO.pure(POut, tabs_newtab_done_fail(tabs, tab_idx))
    case Done{pty}: IO.pure(POut, tabs_newtab_done_ok(tabs, tab_idx, pty))

def shell_tick_newtab(+tabs: List<&2, Tab>, +tab_idx: U32) -> IO(POut):
  do IO<POut>:
    or_ : Result<&1,&1, U32 & String, Pty> <- Pty.spawn()
    shell_tick_newtab_done(tabs, tab_idx, or_)

# --- pending = 2 (close tab): close the active pty, remove the tab, clamp.
# A single tab is a no-op (the shell always keeps >= 1 tab).
def tabs_close_done2(+rest: List<&2, Tab>, +tab_idx: U32) -> POut:
  POut{rest, tab_idx_clamp(tab_idx, tabs_count(rest)), 1}

def shell_tick_closetab_go(+tabs: List<&2, Tab>, +tab_idx: U32) -> IO(POut):
  do IO<POut>:
    _u : Unit <- pty_close_maybe(tab_pty(tabs_get(tabs, tab_idx)))
    IO.pure(POut, tabs_close_done2(tabs_remove_at(tabs, tab_idx), tab_idx))

def shell_tick_closetab_c(+count: U32, +tabs: List<&2, Tab>, +tab_idx: U32) -> IO(POut):
  match count:
    case 0: IO.pure(POut, POut{tabs, tab_idx, 0})
    case 1: IO.pure(POut, POut{tabs, tab_idx, 0})
    case _: shell_tick_closetab_go(tabs, tab_idx)

def shell_tick_closetab(+tabs: List<&2, Tab>, +tab_idx: U32) -> IO(POut):
  shell_tick_closetab_c(tabs_count(tabs), tabs, tab_idx)

# --- pending = 3/4 (next/prev tab): index only, no IO.
def tabs_next_done(+tabs: List<&2, Tab>, +tab_idx: U32) -> POut:
  POut{tabs, tab_next_idx(tab_idx, tabs_count(tabs)), 1}

def tabs_prev_done(+tabs: List<&2, Tab>, +tab_idx: U32) -> POut:
  POut{tabs, tab_prev_idx(tab_idx, tabs_count(tabs)), 1}

def shell_tick_pend(+pending: U32, +tabs: List<&2, Tab>, +tab_idx: U32) -> IO(POut):
  match pending:
    case 0: IO.pure(POut, POut{tabs, tab_idx, 0})
    case 1: shell_tick_newtab(tabs, tab_idx)
    case 2: shell_tick_closetab(tabs, tab_idx)
    case 3: IO.pure(POut, tabs_next_done(tabs, tab_idx))
    case _: IO.pure(POut, tabs_prev_done(tabs, tab_idx))

# ---------- Pass 2 (IO): pend -> writes -> poll -> save -> rebuild ----------
#
# Only the ACTIVE tab's pty gets writes + poll each tick. After the poll the
# updated (pty, term) is written back into the tab list with tabs_set, so
# background tabs keep their scrollback untouched.

# "" pending = none. SNil/SCon matching is how shell.bend matches Strings.
def prof_has_pending(+p: String) -> Bool:
  match p:
    case SNil{}: False{}
    case SCon{_, _}: True{}

# Profile-switch executor (runs in the IO pass, where File effects live).
# has=False: the ordinary path — dirty-save to the CURRENT profile's file.
# has=True: save the fold's items to the OLD profile's file (always, not
# just when dirty — simpler and safe), load the NEW profile's file, rebuild
# with a fresh view (sel=0, fresh ViewSt) and dirty=False. Tabs, terminal,
# hover, and mouse state are untouched.
def tick_tab_save_pend(+has: Bool, +pend: String, +cur: String, +tabs: List<&2, Tab>, +tab_idx: U32, +tchanged: U32, +sel: U32, +d: Nat, +sel2: U32, +items2: List<&2, Item>, frame: Image, +tfocus: Bool, +tfocus2: Bool, +vs: ViewSt, +vs2: ViewSt, +dirty: Bool, +term_changed: Bool, +entry2: String, +entry_mode2: U32, +emode: U32, +hover: U32, +hover2: U32, +mx2: U32, +my2: U32, +feed: String, +feed2: String, +acc: AccSt, +sess_save: Bool) -> IO(Maybe<ShellSt>):
  match has:
    case False{}:
      do IO<Maybe<ShellSt>>:
        _ok : Bool <- tick_save_items(items2, dirty, cur)
        _sv : Bool <- tick_save_session_go(sess_save, sess_of(tfocus2, vs2, tabs, tab_idx, sel2, acc, cur))
        IO.pure(Maybe<ShellSt>, tick_rebuild(d, sel, sel2, items2, dirty, frame, tabs, tab_idx, tchanged, tfocus2, vs, vs2, term_changed, bool_not(bool_eq(tfocus, tfocus2)), entry2, entry_mode2, emode, hover, hover2, mx2, my2, cur, feed, feed2, acc, False{}))
    case True{}:
      do IO<Maybe<ShellSt>>:
        _ok : Bool <- save_items_file(items2, profile_file(cur))
        items3 : List<&2, Item> <- load_items_file(profile_file(pend))
        _sv : Bool <- save_session(sess_of(tfocus2, viewst_new(feed2), tabs, tab_idx, 0, acc, pend))
        IO.pure(Maybe<ShellSt>, tick_rebuild(d, 0, 0, items3, False{}, frame, tabs, tab_idx, 1, tfocus2, vs, viewst_new(feed2), term_changed, bool_not(bool_eq(tfocus, tfocus2)), entry2, entry_mode2, emode, hover, hover2, mx2, my2, pend, feed, feed2, acc, True{}))

def tick_tab_save(+tabs: List<&2, Tab>, +tab_idx: U32, +tchanged: U32, +sel: U32, +d: Nat, +sel2: U32, +items2: List<&2, Item>, frame: Image, +tfocus: Bool, +tfocus2: Bool, +vs: ViewSt, +vs2: ViewSt, +dirty: Bool, +term_changed: Bool, +entry2: String, +entry_mode2: U32, +emode: U32, +hover: U32, +hover2: U32, +mx2: U32, +my2: U32, +ps: ProfSt, +feed: String, +feed2: String, +acc: AccSt, +sess_save: Bool) -> IO(Maybe<ShellSt>):
  match ps:
    case PSt{cur, ppend}: tick_tab_save_pend(prof_has_pending(ppend), ppend, cur, tabs, tab_idx, tchanged, sel, d, sel2, items2, frame, tfocus, tfocus2, vs, vs2, dirty, term_changed, entry2, entry_mode2, emode, hover, hover2, mx2, my2, feed, feed2, acc, sess_save)

def tick_tab_finish(+tabs: List<&2, Tab>, +tab_idx: U32, +sb: SbSt, +tchanged: U32, pty_m: MaybePty, +term2: Term, +term_changed: Bool, +sel: U32, +d: Nat, +sel2: U32, +items2: List<&2, Item>, frame: Image, +tfocus: Bool, +tfocus2: Bool, +vs: ViewSt, +vs2: ViewSt, +dirty: Bool, quit: Bool, +entry2: String, +entry_mode2: U32, +emode: U32, +hover: U32, +hover2: U32, +mx2: U32, +my2: U32, +ps: ProfSt, +feed: String, +feed2: String, +acc: AccSt) -> IO(Maybe<ShellSt>):
  match quit:
    case True{}:
      # Clean quit: persist the session BEFORE tearing down the tabs, so a
      # relaunch reopens exactly where the user left off. The atomic
      # tmp+fsync+rename protocol means even a kill -9 here cannot corrupt
      # session.txt (worst case: the previous good file survives).
      do IO<Maybe<ShellSt>>:
        _sv : Bool <- save_session(sess_of(tfocus2, vs2, tabs, tab_idx, sel2, acc, prof_cur(ps)))
        _u : Unit <- tabs_close_all(tabs)
        IO.pure(Maybe<ShellSt>, None{})
    case False{}:
      # The IO pass funnels every tick's Term here: apply the scrollback
      # request AFTER the PTY poll, so an explicit PgUp in the same tick as
      # fresh output applies from the new live position (output resets the
      # view to live inside term_write first). term_changed ORs in the
      # scroll-request flag so a pure scroll still rebuilds the frame.
      # sess_save: exactly the persisted UI surface changed this tick, so
      # the session file tracks it without a write on every tick.
      tick_tab_save(tabs_set(tabs, tab_idx, TTab{pty_m, sb_apply_sb(sb, term2)}), tab_idx, tchanged, sel, d, sel2, items2, frame, tfocus, tfocus2, vs, vs2, dirty, Bool.or(term_changed, sb_touched(sb)), entry2, entry_mode2, emode, hover, hover2, mx2, my2, ps, feed, feed2, acc, sess_save_of(sel, sel2, tfocus, tfocus2, vs, vs2, tchanged, sb, acc))

def tick_pty_tail_done(pr: Pty & Term & Bool, +tabs: List<&2, Tab>, +tab_idx: U32, +sb: SbSt, +tchanged: U32, +sel: U32, +d: Nat, +sel2: U32, +items2: List<&2, Item>, frame: Image, +tfocus: Bool, +tfocus2: Bool, +vs: ViewSt, +vs2: ViewSt, +dirty: Bool, quit: Bool, +entry2: String, +entry_mode2: U32, +emode: U32, +hover: U32, +hover2: U32, +mx2: U32, +my2: U32, +ps: ProfSt, +feed: String, +feed2: String, +acc: AccSt) -> IO(Maybe<ShellSt>):
  match pr:
    case (pty3, term2, term_changed): tick_tab_finish(tabs, tab_idx, sb, tchanged, YesPty{pty3}, term2, term_changed, sel, d, sel2, items2, frame, tfocus, tfocus2, vs, vs2, dirty, quit, entry2, entry_mode2, emode, hover, hover2, mx2, my2, ps, feed, feed2, acc)

def tick_pty_tail(writes: TtyWList, pty: Pty, +term: Term, +tabs: List<&2, Tab>, +tab_idx: U32, +sb: SbSt, +tchanged: U32, +sel: U32, +d: Nat, +sel2: U32, +items2: List<&2, Item>, frame: Image, +tfocus: Bool, +tfocus2: Bool, +vs: ViewSt, +vs2: ViewSt, +dirty: Bool, quit: Bool, +entry2: String, +entry_mode2: U32, +emode: U32, +hover: U32, +hover2: U32, +mx2: U32, +my2: U32, +ps: ProfSt, +feed: String, +feed2: String, +acc: AccSt) -> IO(Maybe<ShellSt>):
  do IO<Maybe<ShellSt>>:
    pty2 : Pty <- do_writes(writes, pty)
    pr : Pty & Term & Bool <- tick_poll(pty2, term)
    tick_pty_tail_done(pr, tabs, tab_idx, sb, tchanged, sel, d, sel2, items2, frame, tfocus, tfocus2, vs, vs2, dirty, quit, entry2, entry_mode2, emode, hover, hover2, mx2, my2, ps, feed, feed2, acc)

# One def per match scrutinee (binder-order rule): tick_tab_io matches the
# Tab, tick_tab_io2 matches its MaybePty.
def tick_tab_io2(mp: MaybePty, +term: Term, +tabs: List<&2, Tab>, +tab_idx: U32, +sb: SbSt, +tchanged: U32, +sel: U32, +d: Nat, frame: Image, +tfocus: Bool, +vs: ViewSt, +emode: U32, +hover: U32, +sel2: U32, +items2: List<&2, Item>, +tfocus2: Bool, +dirty: Bool, quit: Bool, writes: TtyWList, +vs2: ViewSt, +entry2: String, +entry_mode2: U32, +mx2: U32, +my2: U32, +hover2: U32, +ps: ProfSt, +feed: String, +feed2: String, +acc: AccSt) -> IO(Maybe<ShellSt>):
  match mp:
    case NoPty{}: tick_tab_finish(tabs, tab_idx, sb, tchanged, NoPty{}, term, False{}, sel, d, sel2, items2, frame, tfocus, tfocus2, vs, vs2, dirty, quit, entry2, entry_mode2, emode, hover, hover2, mx2, my2, ps, feed, feed2, acc)
    case YesPty{pty}: tick_pty_tail(writes, pty, term, tabs, tab_idx, sb, tchanged, sel, d, sel2, items2, frame, tfocus, tfocus2, vs, vs2, dirty, quit, entry2, entry_mode2, emode, hover, hover2, mx2, my2, ps, feed, feed2, acc)

def tick_tab_io(+tab: Tab, +tabs: List<&2, Tab>, +tab_idx: U32, +sb: SbSt, +tchanged: U32, +sel: U32, +d: Nat, frame: Image, +tfocus: Bool, +vs: ViewSt, +emode: U32, +hover: U32, +sel2: U32, +items2: List<&2, Item>, +tfocus2: Bool, +dirty: Bool, quit: Bool, writes: TtyWList, +vs2: ViewSt, +entry2: String, +entry_mode2: U32, +mx2: U32, +my2: U32, +hover2: U32, +ps: ProfSt, +feed: String, +feed2: String, +acc: AccSt) -> IO(Maybe<ShellSt>):
  match tab:
    case TTab{mp, term}: tick_tab_io2(mp, term, tabs, tab_idx, sb, tchanged, sel, d, frame, tfocus, vs, emode, hover, sel2, items2, tfocus2, dirty, quit, writes, vs2, entry2, entry_mode2, mx2, my2, hover2, ps, feed, feed2, acc)

def tick_tab_begin(+tabs: List<&2, Tab>, +tab_idx: U32, +sb: SbSt, +tchanged: U32, +sel: U32, +d: Nat, frame: Image, +tfocus: Bool, +vs: ViewSt, +emode: U32, +hover: U32, +sel2: U32, +items2: List<&2, Item>, +tfocus2: Bool, +dirty: Bool, quit: Bool, writes: TtyWList, +vs2: ViewSt, +entry2: String, +entry_mode2: U32, +mx2: U32, +my2: U32, +hover2: U32, +ps: ProfSt, +feed: String, +feed2: String, +acc: AccSt) -> IO(Maybe<ShellSt>):
  tick_tab_io(tabs_get(tabs, tab_idx), tabs, tab_idx, sb, tchanged, sel, d, frame, tfocus, vs, emode, hover, sel2, items2, tfocus2, dirty, quit, writes, vs2, entry2, entry_mode2, mx2, my2, hover2, ps, feed, feed2, acc)

def tick_after_pend(po: POut, +sb: SbSt, +sel: U32, +d: Nat, frame: Image, +tfocus: Bool, +vs: ViewSt, +emode: U32, +hover: U32, +sel2: U32, +items2: List<&2, Item>, +tfocus2: Bool, +dirty: Bool, quit: Bool, writes: TtyWList, +vs2: ViewSt, +entry2: String, +entry_mode2: U32, +mx2: U32, +my2: U32, +hover2: U32, +ps: ProfSt, +feed: String, +feed2: String, +acc: AccSt) -> IO(Maybe<ShellSt>):
  match po:
    case POut{tabs, tab_idx, tchanged}: tick_tab_begin(tabs, tab_idx, sb, tchanged, sel, d, frame, tfocus, vs, emode, hover, sel2, items2, tfocus2, dirty, quit, writes, viewst_feed_refresh(vs2, feed, feed2), entry2, entry_mode2, mx2, my2, hover2, ps, feed, feed2, acc)

# ---------- reader live-feed target: SHELL_OS_FEED (configurable) ----------
# FEED-TARGET-BEGIN
#
# The reader's "Live feed" article fetches "/feed" over plain HTTP. The
# socket target is configurable via the SHELL_OS_FEED environment variable:
#   SHELL_OS_FEED=host:port          (e.g. "127.0.0.1:18081")
#   SHELL_OS_FEED=tcp://host:port    (scheme form; same meaning)
# Unset, empty, or malformed -> default 127.0.0.1:18081, so the demo path
# stays network-independent and behaves exactly as before.
# (Choice note: Bend's Base already ships IO.get_env with working .c and
#  .js implementations, so no new FFI effect was needed. A feed.conf file
#  next to items.txt was considered; the env var won on simplicity — no
#  new file plumbing, and it is re-read on every fetch so a change takes
#  effect without restarting the app.)
#
# Defensive parse (pure Bend, total, never crashes):
#   - strip one optional lowercase "tcp://" prefix; trim ASCII ws (9/10/13/32)
#     at both ends
#   - host = up to the first ':'; must be non-empty, every char 33..126
#     (no space/control chars — the host lands in the HTTP Host: header
#     line unquoted, so this also rules out header-injection values)
#   - port = after the first ':'; all digits, value 1..65535 (overflow-safe)
# Any deviation -> (127.0.0.1, 18081).
# The configured value is used ONLY as the TCP connect target
# (Sock.connect(host, port)) — never a shell command, never a file path.
#
# Bend-shape notes: user code has no mutual recursion, so every loop is
# ONE self-recursive def; per-char classification is by literal match on
# the char code (a computed Bool cannot be a match scrutinee); Bool
# outcomes accumulate through leaf helpers (feed_and and friends).

def feed_def_host() -> String: "127.0.0.1"
def feed_def_port() -> U32: 18081

def feed_def() -> String & U32:
  (feed_def_host(), feed_def_port())

# Left trim: single self-recursive def, literal ws arms (9,10,13,32).
def feed_ltrim(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{c}, t}:
      match c:
        case 9: feed_ltrim(t)
        case 10: feed_ltrim(t)
        case 13: feed_ltrim(t)
        case 32: feed_ltrim(t)
        case _: String.append(Char.show(Chr{c}), t)

# Right trim: ws chars are held in `pend` and only committed to `kept`
# when a non-ws char follows (else they are trailing and dropped).
def feed_rtrim_go(s: String, kept: String, pend: String) -> String:
  match s:
    case SNil{}: kept
    case SCon{Chr{c}, t}:
      match c:
        case 9: feed_rtrim_go(t, kept, String.append(pend, Char.show(Chr{c})))
        case 10: feed_rtrim_go(t, kept, String.append(pend, Char.show(Chr{c})))
        case 13: feed_rtrim_go(t, kept, String.append(pend, Char.show(Chr{c})))
        case 32: feed_rtrim_go(t, kept, String.append(pend, Char.show(Chr{c})))
        case _: feed_rtrim_go(t, String.append(String.append(kept, pend), Char.show(Chr{c})), "")

def feed_rtrim(s: String) -> String:
  feed_rtrim_go(s, "", "")

def feed_trim(s: String) -> String:
  feed_rtrim(feed_ltrim(s))

# Optional lowercase "tcp://" prefix (116,99,112,58,47,47).
def feed_has_tcp_scheme(s: String) -> Bool:
  match s:
    case SCon{Chr{116}, SCon{Chr{99}, SCon{Chr{112}, SCon{Chr{58}, SCon{Chr{47}, SCon{Chr{47}, _}}}}}}: True{}
    case _: False{}

def feed_strip6(s: String) -> String:
  match s:
    case SCon{_, SCon{_, SCon{_, SCon{_, SCon{_, SCon{_, rest}}}}}}: rest
    case _: ""

def feed_strip_scheme2(+has: Bool, s: String) -> String:
  match has:
    case True{}: feed_strip6(s)
    case False{}: s

def feed_strip_scheme(+s: String) -> String:
  feed_strip_scheme2(feed_has_tcp_scheme(s), s)

# Split at the FIRST ':' -> (host, portstr). No colon -> (s, "").
def feed_split_go(s: String, host: String) -> String & String:
  match s:
    case SNil{}: (host, "")
    case SCon{Chr{c}, t}:
      match c:
        case 58: (host, t)
        case _: feed_split_go(t, String.append(host, Char.show(Chr{c})))

# Leaf Bool helpers (no recursion): defined before their users.
def feed_and(+a: Bool, +b: Bool) -> Bool:
  match a:
    case False{}: False{}
    case True{}: b

def feed_host_char_ok2(+lo: Bool, +hi: Bool) -> Bool:
  match lo:
    case False{}: False{}
    case True{}: hi

def feed_host_char_ok(+c: U32) -> Bool:
  feed_host_char_ok2(U32.is_le(33, c), U32.is_le(c, 126))

# Host valid: non-empty and every char printable non-space (33..126).
def feed_host_ok_go(s: String, ok: Bool) -> Bool:
  match s:
    case SNil{}: ok
    case SCon{Chr{c}, t}: feed_host_ok_go(t, feed_and(ok, feed_host_char_ok(c)))

def feed_host_valid2(+empty: Bool, +host: String) -> Bool:
  match empty:
    case True{}: False{}
    case False{}: feed_host_ok_go(host, True{})

def feed_host_valid(+host: String) -> Bool:
  feed_host_valid2(String.is_empty(host), host)

# Port: all digits, 1..65535. Single self-recursive def; each digit arm
# updates acc inline and folds the overflow check into `ok`.
# acc*10+d > 65535  <=>  acc > 6553, or (acc == 6553 and d > 5).
def feed_port_no_over2(+gt: Bool, +eq: Bool, +d: U32) -> Bool:
  match gt:
    case True{}: False{}
    case False{}:
      match eq:
        case False{}: True{}
        case True{}: U32.is_le(d, 5)

def feed_port_no_over(+acc: U32, +d: U32) -> Bool:
  feed_port_no_over2(U32.is_lt(6553, acc), U32.is_eq(acc, 6553), d)

def feed_port_end_ok(+seen: Bool, +ok: Bool, +p: U32) -> Bool:
  feed_and(feed_and(seen, ok), U32.is_lt(0, p))

def feed_port_go(s: String, +acc: U32, +seen: Bool, +ok: Bool) -> U32 & Bool:
  match s:
    case SNil{}: (acc, feed_port_end_ok(seen, ok, acc))
    case SCon{Chr{c}, t}:
      match c:
        case 48: feed_port_go(t, U32.mul(acc, 10), True{}, feed_and(ok, feed_port_no_over(acc, 0)))
        case 49: feed_port_go(t, U32.add(U32.mul(acc, 10), 1), True{}, feed_and(ok, feed_port_no_over(acc, 1)))
        case 50: feed_port_go(t, U32.add(U32.mul(acc, 10), 2), True{}, feed_and(ok, feed_port_no_over(acc, 2)))
        case 51: feed_port_go(t, U32.add(U32.mul(acc, 10), 3), True{}, feed_and(ok, feed_port_no_over(acc, 3)))
        case 52: feed_port_go(t, U32.add(U32.mul(acc, 10), 4), True{}, feed_and(ok, feed_port_no_over(acc, 4)))
        case 53: feed_port_go(t, U32.add(U32.mul(acc, 10), 5), True{}, feed_and(ok, feed_port_no_over(acc, 5)))
        case 54: feed_port_go(t, U32.add(U32.mul(acc, 10), 6), True{}, feed_and(ok, feed_port_no_over(acc, 6)))
        case 55: feed_port_go(t, U32.add(U32.mul(acc, 10), 7), True{}, feed_and(ok, feed_port_no_over(acc, 7)))
        case 56: feed_port_go(t, U32.add(U32.mul(acc, 10), 8), True{}, feed_and(ok, feed_port_no_over(acc, 8)))
        case 57: feed_port_go(t, U32.add(U32.mul(acc, 10), 9), True{}, feed_and(ok, feed_port_no_over(acc, 9)))
        case _: (0, False{})

def feed_port_parse(s: String) -> U32 & Bool:
  feed_port_go(s, 0, False{}, True{})

# Assemble: port first, host threads through as a param (defs precede use).
def feed_validate_host(+hok: Bool, +host: String, +p: U32) -> String & U32:
  match hok:
    case False{}: feed_def()
    case True{}: (host, p)

def feed_validate_h(+ok: Bool, +p: U32, +host: String) -> String & U32:
  match ok:
    case False{}: feed_def()
    case True{}: feed_validate_host(feed_host_valid(host), host, p)

def feed_validate_p(po: U32 & Bool, +host: String) -> String & U32:
  match po:
    case (p, ok): feed_validate_h(ok, p, host)

def feed_validate(+host: String, +portstr: String) -> String & U32:
  feed_validate_p(feed_port_parse(portstr), host)

def feed_split_res(hp: String & String) -> String & U32:
  match hp:
    case (host, portstr): feed_validate(host, portstr)

def feed_parse_target(s: String) -> String & U32:
  feed_split_res(feed_split_go(feed_trim(feed_strip_scheme(s)), ""))

# IO.get_env result -> (host, port). Missing var (Fail) -> default.
def feed_target_env(envr: Result<&1,&1, U32 & String, String>) -> String & U32:
  match envr:
    case Fail{e}: feed_def()
    case Done{s}: feed_parse_target(s)

# Fetch via the configured target (replaces the old hardcoded call).
def feed_fetch_target(tp: String & U32) -> IO(Result<&1,&1, U32 & String, String>):
  match tp:
    case (host, port): http_fetch(host, port, "/feed")

def feed_fetch_env(envr: Result<&1,&1, U32 & String, String>) -> IO(Result<&1,&1, U32 & String, String>):
  match envr:
    case Fail{e}: http_fetch(feed_def_host(), feed_def_port(), "/feed")
    case Done{s}: feed_fetch_target(feed_parse_target(s))
# FEED-TARGET-END

# ---------- reader live feed: fetch IO (#7) ----------
#
# Runs after the tab-pending IO, before the tab save/rebuild. Fires when
# EITHER the plain-fetch ('f') or the HTTPS-fetch ('h') key is pending;
# hpending selects the real-HTTPS target (news.ycombinator.com/rss via the
# TLS bridge, mandatory certificate verification, fail-closed). Best-effort:
# on any failure the old feed survives.
def tick_fetch_pick(or_: Result<&1,&1, U32 & String, String>, +old: String) -> String:
  match or_:
    case Fail{e}: old
    case Done{body}:
      match body:
        case SNil{}: old
        case SCon{_, _}: body

# 'f' fetches the SHELL_OS_FEED target (plain HTTP, default 127.0.0.1:18081);
# 'h' fires the same live article through REAL verified HTTPS: the feed is
# fetched from news.ycombinator.com/rss via the TLS bridge (mandatory
# certificate verification, fail-closed). Best-effort: on any failure the
# old feed survives.

# ---------- reader fetch-cache durability (atomic write + fsync) ----------
# The live feed body used to live only in memory: a restart always lost it
# and the reader opened empty until the next fetch. The cache persists the
# last successfully fetched body to feed_cache.txt with the SAME protocol
# as item write-back (shell.bend): serialize to <path>.tmp, close, fsync
# the tmp, rename over <path>. On any failure the old cache stays intact —
# a crash can never surface a half-synced cache. The body is re-read at
# startup (load_feed_cache) so the reader opens warm. Cached content flows
# through the same pure tokenizer/extractor/wrapper as a live fetch, so no
# new trust is placed in the file; the path is a fixed constant (never
# user- or network-controlled).
# (Defined before tick_fetch_fire: defs precede use.)

def feed_cache_path() -> String: "feed_cache.txt"
def feed_cache_tmp() -> String: "feed_cache.txt.tmp"

def feed_cache_synced(sr: Result<&1,&1, U32 & String, Unit>, +path: String, +tmp: String) -> IO(Bool):
  match sr:
    case Fail{e}: IO.pure(Bool, False{})
    case Done{_}:
      do IO<Bool>:
        rr : Result<&1,&1, U32 & String, Unit> <- filerename_raw(tmp, path)
        save_items_renamed(rr)

def feed_cache_wrote_res(f: File, +ok: Bool, +path: String, +tmp: String) -> IO(Bool):
  match ok:
    case True{}:
      do IO<Bool>:
        _u : Unit <- File.close(f)
        sr : Result<&1,&1, U32 & String, Unit> <- filesync_raw(tmp)
        feed_cache_synced(sr, path, tmp)
    case False{}:
      do IO<Bool>:
        _u : Unit <- File.close(f)
        IO.pure(Bool, False{})

def feed_cache_wrote(wr: File & Result<&1,&1, U32 & String, Unit>, +path: String, +tmp: String) -> IO(Bool):
  (f2, rres) = wr
  match rres:
    case Fail{e}: feed_cache_wrote_res(f2, False{}, path, tmp)
    case Done{_}: feed_cache_wrote_res(f2, True{}, path, tmp)

def feed_cache_opened(or_: Result<&1,&1, U32 & String, File>, +body: String, +path: String, +tmp: String) -> IO(Bool):
  match or_:
    case Fail{e}: IO.pure(Bool, False{})
    case Done{f}:
      do IO<Bool>:
        wr : File & Result<&1,&1, U32 & String, Unit> <- File.write(f, body)
        feed_cache_wrote(wr, path, tmp)

def save_str_atomic(+body: String, +path: String, +tmp: String) -> IO(Bool):
  do IO<Bool>:
    or_ : Result<&1,&1, U32 & String, File> <- File.open(tmp, "w")
    feed_cache_opened(or_, body, path, tmp)

def save_feed_cache(+body: String) -> IO(Bool):
  save_str_atomic(body, feed_cache_path(), feed_cache_tmp())

# Persist the body only when the fetch produced a NEW one: a failed fetch
# returns the old feed (tick_fetch_pick), which must not churn the cache.
def feed_cache_persist_body(+nb: String, changed: Bool) -> IO(String):
  match changed:
    case True{}:
      do IO<String>:
        _ok : Bool <- save_feed_cache(nb)
        IO.pure(String, nb)
    case False{}: IO.pure(String, nb)

def tick_fetch_persist(+nb: String, +old: String) -> IO(String):
  feed_cache_persist_body(nb, bool_not(String.eq(nb, old)))

def load_feed_cache_read(fr: File & Result<&1,&1, U32 & String, String>) -> IO(String):
  (f2, rres) = fr
  match rres:
    case Fail{e}:
      do IO<String>:
        _u : Unit <- File.close(f2)
        IO.pure(String, "")
    case Done{text}:
      do IO<String>:
        _u : Unit <- File.close(f2)
        IO.pure(String, text)

def load_feed_cache_opened(or_: Result<&1,&1, U32 & String, File>) -> IO(String):
  match or_:
    case Fail{e}: IO.pure(String, "")
    case Done{f}:
      do IO<String>:
        fr : File & Result<&1,&1, U32 & String, String> <- File.read(f, 1048576)
        load_feed_cache_read(fr)

def load_feed_cache() -> IO(String):
  do IO<String>:
    or_ : Result<&1,&1, U32 & String, File> <- File.open(feed_cache_path(), "r")
    load_feed_cache_opened(or_)

def tick_fetch_fire(+hpending: Bool, +feed: String) -> IO(String):
  match hpending:
    case True{}:
      do IO<String>:
        or_ : Result<&1,&1, U32 & String, String> <- https_fetch("news.ycombinator.com", 443, "/rss")
        tick_fetch_persist(tick_fetch_pick(or_, feed), feed)
    case False{}:
      do IO<String>:
        envr : Result<&1,&1, U32 & String, String> <- IO.get_env("SHELL_OS_FEED")
        or_ : Result<&1,&1, U32 & String, String> <- feed_fetch_env(envr)
        tick_fetch_persist(tick_fetch_pick(or_, feed), feed)

def tick_fetch_do(+fpending: Bool, +hpending: Bool, +feed: String) -> IO(String):
  match fpending:
    case True{}: tick_fetch_fire(hpending, feed)
    case False{}:
      match hpending:
        case True{}: tick_fetch_fire(hpending, feed)
        case False{}: IO.pure(String, feed)

def tick_fold6(+pending: U32, +sb: SbSt, +tabs: List<&2, Tab>, +tab_idx: U32, +sel: U32, +d: Nat, frame: Image, +tfocus: Bool, +vs: ViewSt, +emode: U32, +hover: U32, +sel2: U32, +items2: List<&2, Item>, +tfocus2: Bool, +dirty: Bool, quit: Bool, writes: TtyWList, +vs2: ViewSt, +entry2: String, +entry_mode2: U32, +mx2: U32, +my2: U32, +hover2: U32, +ps: ProfSt, +fpend: Bool, +hpend: Bool, +feed: String, +acc: AccSt) -> IO(Maybe<ShellSt>):
  do IO<Maybe<ShellSt>>:
    po : POut <- shell_tick_pend(pending, tabs, tab_idx)
    feed2 : String <- tick_fetch_do(fpend, hpend, feed)
    tick_after_pend(po, sb, sel, d, frame, tfocus, vs, emode, hover, sel2, items2, tfocus2, dirty, quit, writes, vs2, entry2, entry_mode2, mx2, my2, hover2, ps, feed, feed2, acc)

def tick_fold5_ps(ps: ProfSt, +sb: SbSt, +pending: U32, +sel: U32, +d: Nat, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus: Bool, +vs: ViewSt, +emode: U32, +hover: U32, +sel2: U32, +items2: List<&2, Item>, +tfocus2: Bool, +dirty: Bool, quit: Bool, writes: TtyWList, +vs2: ViewSt, +entry2: String, +entry_mode2: U32, +mx2: U32, +my2: U32, +hover2: U32, +fpend: Bool, +hpend: Bool, +feed: String, +acc: AccSt) -> IO(Maybe<ShellSt>):
  tick_fold6(pending, sb, tabs, tab_idx, sel, d, frame, tfocus, vs, emode, hover, sel2, items2, tfocus2, dirty, quit, writes, vs2, entry2, entry_mode2, mx2, my2, hover2, ps, fpend, hpend, feed, acc)

def tick_fold5(ts: TabSt, ps: ProfSt, +sb: SbSt, +sel: U32, +d: Nat, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus: Bool, +vs: ViewSt, +emode: U32, +hover: U32, +sel2: U32, +items2: List<&2, Item>, +tfocus2: Bool, +dirty: Bool, quit: Bool, writes: TtyWList, +vs2: ViewSt, +entry2: String, +entry_mode2: U32, +mx2: U32, +my2: U32, +hover2: U32, +fpend: Bool, +hpend: Bool, +feed: String, +acc: AccSt) -> IO(Maybe<ShellSt>):
  match ts:
    case TSt{_, pending}: tick_fold5_ps(ps, sb, pending, sel, d, frame, tabs, tab_idx, tfocus, vs, emode, hover, sel2, items2, tfocus2, dirty, quit, writes, vs2, entry2, entry_mode2, mx2, my2, hover2, fpend, hpend, feed, acc)

def tick_fold4(ms: MouseSt, ts: TabSt, ps: ProfSt, +sb: SbSt, +sel: U32, +d: Nat, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus: Bool, +vs: ViewSt, +emode: U32, +hover: U32, +sel2: U32, +items2: List<&2, Item>, +tfocus2: Bool, +dirty: Bool, quit: Bool, writes: TtyWList, +vs2: ViewSt, +entry2: String, +entry_mode2: U32, +fpend: Bool, +hpend: Bool, +feed: String, +acc: AccSt) -> IO(Maybe<ShellSt>):
  match ms:
    case MSt{mx2, my2, hover2}:
      tick_fold5(ts, ps, sb, sel, d, frame, tabs, tab_idx, tfocus, vs, emode, hover, sel2, items2, tfocus2, dirty, quit, writes, vs2, entry2, entry_mode2, mx2, my2, hover2, fpend, hpend, feed, acc)

def tick_fold3(ev: EvSt, ms: MouseSt, ts: TabSt, ps: ProfSt, +sb: SbSt, +sel: U32, +d: Nat, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus: Bool, +vs: ViewSt, +emode: U32, +hover: U32, +fpend: Bool, +hpend: Bool, +feed: String, +acc: AccSt) -> IO(Maybe<ShellSt>):
  match ev:
    case EvS{sel2, items2, tfocus2, dirty, quit, writes, vs2, entry2, entry_mode2}:
      tick_fold4(ms, ts, ps, sb, sel, d, frame, tabs, tab_idx, tfocus, vs, emode, hover, sel2, items2, tfocus2, dirty, quit, writes, vs2, entry2, entry_mode2, fpend, hpend, feed, acc)

def tick_fold2(fst: FoldSt, +sel: U32, +d: Nat, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus: Bool, +vs: ViewSt, +emode: U32, +hover: U32, +feed: String, +acc: AccSt) -> IO(Maybe<ShellSt>):
  match fst:
    case FSt{ev, ms, ts, ps, fs, sb}:
      match fs:
        case FchSt{fpend, hpend, _}: tick_fold3(ev, ms, ts, ps, sb, sel, d, frame, tabs, tab_idx, tfocus, vs, emode, hover, fpend, hpend, feed, acc)

# ---------- accretive key interception ----------
# Four panels: universal search (/), saved-article note editor (s),
# Gmail read-only tile (g), AI theme grouping (i).
#
# Modal priority for key events: search > note > gmail > ai > closed.
# Closed-panel keys are only intercepted when the entry bar is idle
# (entry_mode == 0); `s` additionally requires the reader to be focused
# (never steals typing from a focused terminal, never fires while the
# entry bar is active).
#
# Phase 0 (acc_io_step, in tick_fold_acc): runs BEFORE the scan. Commits
# staged note saves, applies staged AI suggestions, and advances one
# Gmail/AI IO transition per tick. Panels never retry on their own: each
# transition is triggered by a user key (toggle/Enter/m) or a staged
# request from the previous tick.
# Phase 1 (acc_scan): fold over Key events, updating AccSt.
# Phase 2 (acc_strip): if any panel was open before or after the scan,
# strip ALL Key events so the main fold doesn't act on them. Mouse passes.
# This keeps FoldSt/EvSt signatures frozen and avoids mutual recursion.

# ----- small view helpers -----

def viewst_focus_read(+vs: ViewSt, +a: U32, +feed: String) -> ViewSt:
  match vs:
    case VSt{page, _, _, _, _}: VSt{page, True{}, a, 0, reader_lines(a, feed)}

# ----- accd-touching setters (every acc mutation sets the rebuild flag) -----

def acc_set_note(+acc: AccSt, +note: NoteSt) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, _, save_req, _, search_go, pal, help}:
      Acc{q, open, sel, gmail, ai, note, save_req, True{}, search_go, pal, help}

def acc_set_gmail(+acc: AccSt, +m: MailSt) -> AccSt:
  match acc:
    case Acc{q, open, sel, _, ai, note, save_req, _, search_go, pal, help}:
      Acc{q, open, sel, m, ai, note, save_req, True{}, search_go, pal, help}

def acc_set_ai(+acc: AccSt, +a: AISt) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, _, note, save_req, _, search_go, pal, help}:
      Acc{q, open, sel, gmail, a, note, save_req, True{}, search_go, pal, help}

def acc_set_save_req(+acc: AccSt, +b: Bool) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, note, _, _, search_go, pal, help}:
      Acc{q, open, sel, gmail, ai, note, b, True{}, search_go, pal, help}

def acc_set_search_go(+acc: AccSt, +go: Maybe<&2, SearchHit>) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, note, save_req, _, _, pal, help}:
      Acc{q, open, sel, gmail, ai, note, save_req, True{}, go, pal, help}

def acc_search_go_of(+acc: AccSt) -> Maybe<&2, SearchHit>:
  match acc:
    case Acc{_, _, _, _, _, _, _, _, search_go, _, help}: search_go

def acc_search_go_cleared2(+go: Maybe<&2, SearchHit>, +acc: AccSt) -> AccSt:
  match go:
    case None{}: acc
    case Some{_}: acc_set_search_go(acc, None{})

def acc_search_go_cleared(+acc: AccSt) -> AccSt:
  acc_search_go_cleared2(acc_search_go_of(acc), acc)

# ----- panel classifiers -----

def acc_note_open_q(+note: NoteSt) -> Bool:
  match note:
    case NOff{}: False{}
    case _: True{}

def acc_any_open_go(+open: Bool, +note_o: Bool, +gmail_o: Bool, +ai_o: Bool, +pal_o: Bool) -> Bool:
  match open:
    case True{}: True{}
    case False{}: Bool.or(note_o, Bool.or(gmail_o, Bool.or(ai_o, pal_o)))

def acc_any_open(+acc: AccSt) -> Bool:
  match acc:
    case Acc{_, open, _, gmail, ai, note, _, _, _, pal, help}:
      acc_any_open_go(open, acc_note_open_q(note), acc_gmail_open_q(gmail), acc_ai_open_q(ai), acc_pal_is_open(pal))

# ----- search -----

def acc_search_toggle_go(+open: Bool, +gmail: MailSt, +ai: AISt, +note: NoteSt, +save_req: Bool, +pal: PalSt, +help: HelpSt) -> AccSt:
  match open:
    case True{}: Acc{"", False{}, 0, gmail, ai, note, save_req, True{}, None{}, pal, help}
    case False{}: Acc{"", True{}, 0, gmail, ai, note, save_req, True{}, None{}, pal, help}

def acc_search_toggle(+acc: AccSt) -> AccSt:
  match acc:
    case Acc{_, open, _, gmail, ai, note, save_req, _, _, pal, help}:
      acc_search_toggle_go(open, gmail, ai, note, save_req, pal, help)

def acc_search_close(+acc: AccSt) -> AccSt:
  match acc:
    case Acc{_, _, _, gmail, ai, note, save_req, _, _, pal, help}:
      Acc{"", False{}, 0, gmail, ai, note, save_req, True{}, None{}, pal, help}

def acc_search_exec(+acc: AccSt, +hit: SearchHit) -> AccSt:
  match acc:
    case Acc{_, _, _, gmail, ai, note, save_req, _, _, pal, help}:
      Acc{"", False{}, 0, gmail, ai, note, save_req, True{}, Some{hit}, pal, help}

def acc_search_type(+acc: AccSt, +c: U32) -> AccSt:
  match acc:
    case Acc{q, open, _, gmail, ai, note, save_req, _, search_go, pal, help}:
      Acc{entry_append(q, c), open, 0, gmail, ai, note, save_req, True{}, search_go, pal, help}

def acc_search_bs(+acc: AccSt) -> AccSt:
  match acc:
    case Acc{q, open, _, gmail, ai, note, save_req, _, search_go, pal, help}:
      Acc{entry_backspace(q), open, 0, gmail, ai, note, save_req, True{}, search_go, pal, help}

def acc_search_up_go(+is_zero: Bool, +sel: U32) -> U32:
  match is_zero:
    case True{}: 0
    case False{}: U32.sub(sel, 1)

def acc_search_up(+acc: AccSt) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, note, save_req, _, search_go, pal, help}:
      Acc{q, open, acc_search_up_go(U32.is_eq(sel, 0), sel), gmail, ai, note, save_req, True{}, search_go, pal, help}

def acc_search_down_pick(+nxt: U32, +lt: Bool) -> U32:
  match lt:
    case True{}: nxt
    case False{}: 0

def acc_search_down2(+nxt: U32, +nhits: U32) -> U32:
  acc_search_down_pick(nxt, U32.is_lt(nxt, nhits))

def acc_search_down_go(+no_hits: Bool, +sel: U32, +nhits: U32) -> U32:
  match no_hits:
    case True{}: 0
    case False{}: acc_search_down2(U32.add(sel, 1), nhits)

def acc_search_down(+acc: AccSt, +nhits: U32) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, note, save_req, _, search_go, pal, help}:
      Acc{q, open, acc_search_down_go(U32.is_eq(nhits, 0), sel, nhits), gmail, ai, note, save_req, True{}, search_go, pal, help}

def search_hits_for(+acc: AccSt, +items: List<&2, Item>, +feed: String, +termlines: List<&2, String>) -> List<&2, SearchHit>:
  match acc:
    case Acc{q, _, _, _, _, _, _, _, _, _, help}: search_all(q, items, feed, termlines)

def acc_search_enter_at(+mhit: Maybe<&2, SearchHit>, +acc: AccSt) -> (AccSt & Bool):
  match mhit:
    case None{}: (acc_search_close(acc), True{})
    case Some{hit}: (acc_search_exec(acc, hit), True{})

def acc_search_enter(+acc: AccSt, +items: List<&2, Item>, +feed: String, +termlines: List<&2, String>) -> (AccSt & Bool):
  acc_search_enter_at(search_hit_at(search_hits_for(acc, items, feed, termlines), acc_search_sel(acc)), acc)

def acc_search_print_go(+is_ascii: Bool, +acc: AccSt, +c: U32) -> (AccSt & Bool):
  match is_ascii:
    case True{}: (acc_search_type(acc, c), True{})
    case False{}: (acc, False{})

def acc_search_print(+acc: AccSt, +c: U32) -> (AccSt & Bool):
  acc_search_print_go(U32.is_lt(c, 128), acc, c)

def acc_search_key(+acc: AccSt, +items: List<&2, Item>, +c: U32, +feed: String, +termlines: List<&2, String>) -> (AccSt & Bool):
  match c:
    case 27: (acc_search_close(acc), True{})
    case 13: acc_search_enter(acc, items, feed, termlines)
    case 63232: (acc_search_up(acc), True{})
    case 63233: (acc_search_down(acc, search_hit_count(search_hits_for(acc, items, feed, termlines))), True{})
    case 127: (acc_search_bs(acc), True{})
    case 8: (acc_search_bs(acc), True{})
    case _: acc_search_print(acc, c)

# ----- note editor (saves the current reader article + inline note) -----

def acc_note_type_cap_go(+fits: Bool, +title: String, +url: String, +text: String, +c: U32) -> NoteSt:
  match fits:
    case True{}: NEdit{title, url, entry_append(text, c)}
    case False{}: NEdit{title, url, text}

def acc_note_type_go(+note: NoteSt, +c: U32) -> NoteSt:
  match note:
    case NEdit{title, url, text}: acc_note_type_cap_go(Nat.is_lt(String.length(text), 256n), title, url, text, c)
    case _: note

def acc_note_bs_go(+note: NoteSt) -> NoteSt:
  match note:
    case NEdit{title, url, text}: NEdit{title, url, entry_backspace(text)}
    case _: note

def acc_note_type(+acc: AccSt, +c: U32) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, note, save_req, _, search_go, pal, help}:
      Acc{q, open, sel, gmail, ai, acc_note_type_go(note, c), save_req, True{}, search_go, pal, help}

def acc_note_bs(+acc: AccSt) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, note, save_req, _, search_go, pal, help}:
      Acc{q, open, sel, gmail, ai, acc_note_bs_go(note), save_req, True{}, search_go, pal, help}

def acc_note_cancel(+acc: AccSt) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, _, save_req, _, search_go, pal, help}:
      Acc{q, open, sel, gmail, ai, NOff{}, save_req, True{}, search_go, pal, help}

def acc_note_enter_note(+note: NoteSt) -> NoteSt:
  match note:
    case NEdit{title, url, text}: NCommit{title, url, text}
    case _: note

def acc_note_enter(+acc: AccSt) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, note, save_req, _, search_go, pal, help}:
      Acc{q, open, sel, gmail, ai, acc_note_enter_note(note), save_req, True{}, search_go, pal, help}

def acc_note_print_go(+is_ascii: Bool, +acc: AccSt, +c: U32) -> (AccSt & Bool):
  match is_ascii:
    case True{}: (acc_note_type(acc, c), True{})
    case False{}: (acc, False{})

def acc_note_print(+acc: AccSt, +c: U32) -> (AccSt & Bool):
  acc_note_print_go(U32.is_lt(c, 128), acc, c)

def acc_note_key(+acc: AccSt, +c: U32) -> (AccSt & Bool):
  match c:
    case 27: (acc_note_cancel(acc), True{})
    case 13: (acc_note_enter(acc), True{})
    case 127: (acc_note_bs(acc), True{})
    case 8: (acc_note_bs(acc), True{})
    case _: acc_note_print(acc, c)

def acc_note_start_for(+acc: AccSt, +title: String, +url: String) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, ai, _, save_req, _, search_go, pal, help}:
      Acc{q, open, sel, gmail, ai, NEdit{title, url, ""}, save_req, True{}, search_go, pal, help}

# ----- gmail keys -----

def acc_gmail_toggle_m(+m: MailSt) -> MailSt:
  match m:
    case MOff{}: MOn{MUnknown{}}
    case _: MOff{}

def acc_gmail_toggle(+acc: AccSt) -> AccSt:
  acc_set_gmail(acc, acc_gmail_toggle_m(acc_gmail_inner(acc)))

def acc_gmail_esc(+acc: AccSt, +c: U32) -> (AccSt & Bool):
  match c:
    case 27: (acc_set_gmail(acc, MOff{}), True{})
    case _: (acc, False{})

# `m` retries from any terminal error state (one attempt per keypress;
# no retry storm). Esc closes from anywhere.
def acc_gmail_retry(+acc: AccSt, +c: U32) -> (AccSt & Bool):
  match c:
    case 27: (acc_set_gmail(acc, MOff{}), True{})
    case 109: (acc_set_gmail(acc, MOn{MUnknown{}}), True{})
    case _: (acc, False{})

def acc_gmail_list_key(+inner: MailInner, +acc: AccSt, +c: U32) -> (AccSt & Bool):
  match c:
    case 27: (acc_set_gmail(acc, MOff{}), True{})
    case 63232: (acc_set_gmail(acc, MOn{mail_list_cur_up(inner)}), True{})
    case 63233: (acc_set_gmail(acc, MOn{mail_list_cur_down(inner)}), True{})
    case 13: (acc_set_gmail(acc, MOn{mail_list_enter(inner)}), True{})
    # Wave 2 pagination: n = next page, p = prev page. Both are free in the
    # gmail tile (open panels strip keys from the main stream, so the
    # reader's n and the profile key p never fire while this panel is open).
    case 110: (acc_set_gmail(acc, MOn{mail_list_next(inner)}), True{})
    case 112: (acc_set_gmail(acc, MOn{mail_list_prev(inner)}), True{})
    case _: (acc, False{})

def acc_gmail_reading_key2(+c: U32, +acc: AccSt, +cid: String, +csec: String, +rtok: String, +token: String, +exp: Nat, +q: String, +cur: U32, +metas: List<&2, MailMeta>, +pg: MailPage) -> (AccSt & Bool):
  match c:
    case 27: (acc_set_gmail(acc, MOn{MList{cid, csec, rtok, token, exp, q, cur, metas, pg}}), True{})
    case _: (acc, False{})

def acc_gmail_reading_key(+inner: MailInner, +acc: AccSt, +c: U32) -> (AccSt & Bool):
  match inner:
    case MReading{cid, csec, rtok, token, exp, q, _, _, cur, metas, pg}:
      acc_gmail_reading_key2(c, acc, cid, csec, rtok, token, exp, q, cur, metas, pg)
    case _: (acc, False{})

# ----- gmail query box (Wave 6) -----

# Printable ASCII appends to the draft; the 256-char cap refuses a 257th char.
def mqry_type_go(+ok: Bool, +draft: String, +c: U32) -> String:
  match ok:
    case True{}: entry_append(draft, c)
    case False{}: draft

def mqry_type(+draft: String, +c: U32) -> String:
  mqry_type_go(Bool.and(Bool.and(U32.is_le(32, c), U32.is_le(c, 126)), Nat.is_lt(String.length(draft), 256n)), draft, c)

def acc_gmail_qry_key2(+c: U32, +draft: String, +base: MailInner, +acc: AccSt) -> (AccSt & Bool):
  match c:
    case 27: (acc_set_gmail(acc, MOn{base}), True{})
    case 13: (acc_set_gmail(acc, MOn{mqry_commit(base, draft)}), True{})
    case 127: (acc_set_gmail(acc, MOn{MQry{entry_backspace(draft), base}}), True{})
    case 8: (acc_set_gmail(acc, MOn{MQry{entry_backspace(draft), base}}), True{})
    case _: (acc_set_gmail(acc, MOn{MQry{mqry_type(draft, c), base}}), True{})

def acc_gmail_qry_key(+inner: MailInner, +acc: AccSt, +c: U32) -> (AccSt & Bool):
  match inner:
    case MQry{draft, base}: acc_gmail_qry_key2(c, draft, base, acc)
    case _: (acc, False{})

def acc_gmail_list_key_pal(+inner: MailInner, +acc: AccSt, +c: U32) -> (AccSt & Bool):
  match c:
    case 59: (acc_pal_open(acc), True{})
    case _: acc_gmail_list_key(inner, acc, c)

def acc_gmail_reading_key_pal(+inner: MailInner, +acc: AccSt, +c: U32) -> (AccSt & Bool):
  match c:
    case 59: (acc_pal_open(acc), True{})
    case _: acc_gmail_reading_key(inner, acc, c)

def acc_gmail_key_inner(+inner: MailInner, +acc: AccSt, +c: U32) -> (AccSt & Bool):
  match inner:
    case MUnknown{}: acc_gmail_esc(acc, c)
    case MNotCfg{}: acc_gmail_esc(acc, c)
    case MBadPerm{}: acc_gmail_retry(acc, c)
    case MCfgErr{msg}: acc_gmail_retry(acc, c)
    case MLoading{_, _, _, _, _, _, _}: acc_gmail_esc(acc, c)
    case MList{_, _, _, _, _, _, _, _, _}: acc_gmail_list_key_pal(inner, acc, c)
    case MFetchMsg{_, _, _, _, _, _, _, _, _, _}: acc_gmail_esc(acc, c)
    case MReading{_, _, _, _, _, _, _, _, _, _, _}: acc_gmail_reading_key_pal(inner, acc, c)
    case MQry{_, _}: acc_gmail_qry_key(inner, acc, c)
    case MAuthErr{}: acc_gmail_retry(acc, c)
    case MNetErr{_}: acc_gmail_retry(acc, c)

def acc_gmail_key_slash_go(+slash: Bool, +inner: MailInner, +acc: AccSt, +c: U32) -> (AccSt & Bool):
  match slash:
    case True{}: (acc_set_gmail(acc, MOn{mqry_open(inner)}), True{})
    case False{}: acc_gmail_key_inner(inner, acc, c)

def acc_gmail_key_slash(+inner: MailInner, +acc: AccSt, +c: U32) -> (AccSt & Bool):
  acc_gmail_key_slash_go(Bool.and(acc_gmail_slashable(inner), U32.is_eq(c, 47)), inner, acc, c)

def acc_gmail_key2(+m: MailSt, +acc: AccSt, +c: U32) -> (AccSt & Bool):
  match m:
    case MOn{inner}: acc_gmail_key_slash(inner, acc, c)
    case MOff{}: (acc, False{})

def acc_gmail_key(+acc: AccSt, +c: U32) -> (AccSt & Bool):
  acc_gmail_key2(acc_gmail_inner(acc), acc, c)

# ----- ai keys -----

def acc_ai_toggle_a(+a: AISt) -> AISt:
  match a:
    case AOff{}: AOn{AIUnknown{}}
    case _: AOff{}

def acc_ai_toggle(+acc: AccSt) -> AccSt:
  acc_set_ai(acc, acc_ai_toggle_a(acc_ai_inner(acc)))

def acc_ai_esc(+acc: AccSt, +c: U32) -> (AccSt & Bool):
  match c:
    case 27: (acc_set_ai(acc, AOff{}), True{})
    case _: (acc, False{})

def acc_ai_idle_key(+acc: AccSt, +c: U32) -> (AccSt & Bool):
  match c:
    case 27: (acc_set_ai(acc, AOff{}), True{})
    case 13: (acc_set_ai(acc, AOn{AISending{}}), True{})
    case _: (acc, False{})

def acc_ai_apply_key(+acc: AccSt, +applied: Bool) -> (AccSt & Bool):
  match applied:
    case True{}: (acc, True{})
    case False{}: (acc_set_save_req(acc, True{}), True{})

def acc_ai_sugg_key(+acc: AccSt, +c: U32, +applied: Bool) -> (AccSt & Bool):
  match c:
    case 27: (acc_set_ai(acc, AOff{}), True{})
    case 13: acc_ai_apply_key(acc, applied)
    case _: (acc, False{})

def acc_ai_key_inner(+inner: AIInner, +acc: AccSt, +c: U32) -> (AccSt & Bool):
  match inner:
    case AIUnknown{}: acc_ai_esc(acc, c)
    case AINone{}: acc_ai_esc(acc, c)
    case AIIdle{}: acc_ai_idle_key(acc, c)
    case AISending{}: acc_ai_esc(acc, c)
    case AISuggSt{_, _, applied}: acc_ai_sugg_key(acc, c, applied)
    case AIErr{}: acc_ai_esc(acc, c)

def acc_ai_key2(+a: AISt, +acc: AccSt, +c: U32) -> (AccSt & Bool):
  match a:
    case AOn{inner}: acc_ai_key_inner(inner, acc, c)
    case AOff{}: (acc, False{})

def acc_ai_key(+acc: AccSt, +c: U32) -> (AccSt & Bool):
  acc_ai_key2(acc_ai_inner(acc), acc, c)

# ----- closed-panel keys -----

def acc_closed_s_go2(+rfocus: Bool, +acc: AccSt, +vs: ViewSt, +feed: String) -> (AccSt & Bool):
  match rfocus:
    case False{}: (acc, False{})
    case True{}: (acc_note_start_for(acc, reader_art_title(viewst_rart_of(vs)), reader_art_url(viewst_rart_of(vs))), True{})

def acc_closed_s(+acc: AccSt, +vs: ViewSt, +feed: String) -> (AccSt & Bool):
  acc_closed_s_go2(viewst_rfocus(vs), acc, vs, feed)

def acc_closed_s_go(+tfocus: Bool, +acc: AccSt, +vs: ViewSt, +feed: String) -> (AccSt & Bool):
  match tfocus:
    case True{}: (acc, False{})
    case False{}: acc_closed_s(acc, vs, feed)

def acc_closed_slash_go(+tfocus: Bool, +acc: AccSt) -> (AccSt & Bool):
  match tfocus:
    case True{}: (acc, False{})
    case False{}: (acc_search_toggle(acc), True{})

def acc_closed_g_go(+tfocus: Bool, +acc: AccSt) -> (AccSt & Bool):
  match tfocus:
    case True{}: (acc, False{})
    case False{}: (acc_gmail_toggle(acc), True{})

def acc_closed_i_go(+tfocus: Bool, +acc: AccSt) -> (AccSt & Bool):
  match tfocus:
    case True{}: (acc, False{})
    case False{}: (acc_ai_toggle(acc), True{})

def acc_closed_pal_go(+tfocus: Bool, +acc: AccSt) -> (AccSt & Bool):
  match tfocus:
    case True{}: (acc, False{})
    case False{}: (acc_pal_open(acc), True{})

def acc_closed_key2(+acc: AccSt, +c: U32, +tfocus: Bool, +vs: ViewSt, +feed: String) -> (AccSt & Bool):
  match c:
    case 47: acc_closed_slash_go(tfocus, acc)
    case 115: acc_closed_s_go(tfocus, acc, vs, feed)
    case 103: acc_closed_g_go(tfocus, acc)
    case 105: acc_closed_i_go(tfocus, acc)
    case 59: acc_closed_pal_go(tfocus, acc)
    case _: (acc, False{})

def acc_closed_key_go(+idle: Bool, +acc: AccSt, +c: U32, +tfocus: Bool, +vs: ViewSt, +feed: String) -> (AccSt & Bool):
  match idle:
    case False{}: (acc, False{})
    case True{}: acc_closed_key2(acc, c, tfocus, vs, feed)

def acc_closed_key(+acc: AccSt, +c: U32, +tfocus: Bool, +entry_mode: U32, +vs: ViewSt, +feed: String) -> (AccSt & Bool):
  acc_closed_key_go(U32.is_eq(entry_mode, 0), acc, c, tfocus, vs, feed)

# ----- modal dispatch -----

def acc_panel_tag_go4(+ai_o: Bool) -> U32:
  match ai_o:
    case True{}: 4
    case False{}: 0

def acc_panel_tag_go3(+gmail_o: Bool, +ai_o: Bool) -> U32:
  match gmail_o:
    case True{}: 3
    case False{}: acc_panel_tag_go4(ai_o)

def acc_panel_tag_go2(+note_o: Bool, +gmail_o: Bool, +ai_o: Bool) -> U32:
  match note_o:
    case True{}: 2
    case False{}: acc_panel_tag_go3(gmail_o, ai_o)

def acc_panel_tag_go(+open: Bool, +note_o: Bool, +gmail_o: Bool, +ai_o: Bool) -> U32:
  match open:
    case True{}: 1
    case False{}: acc_panel_tag_go2(note_o, gmail_o, ai_o)

def acc_panel_tag_go5(+pal_o: Bool, +open: Bool, +note_o: Bool, +gmail_o: Bool, +ai_o: Bool) -> U32:
  match pal_o:
    case True{}: 5
    case False{}: acc_panel_tag_go(open, note_o, gmail_o, ai_o)

def acc_panel_tag(+acc: AccSt) -> U32:
  match acc:
    case Acc{_, open, _, gmail, ai, note, _, _, _, pal, help}:
      match help:
        case HOn{_}: 6
        case HOff{}: acc_panel_tag_go5(acc_pal_is_open(pal), open, acc_note_open_q(note), acc_gmail_open_q(gmail), acc_ai_open_q(ai))

# ---------- `?` shortcut overlay: context classifier and toggle (Wave 5) ----------
# Placed after acc_panel_tag (defs must precede use) and before acc_scan_tagged.
# Contexts: 0=normal, 1=search, 2=note/saved, 3=gmail, 4=ai, 5=palette,
# 6=entry, 7=reader, 8=terminal. Captured at open time; the underlying state
# is frozen while help is open, so the stored ctx stays valid.
def acc_help_ctx_rf(+rfocus: Bool) -> U32:
  match rfocus:
    case True{}: 7
    case False{}: 0

def acc_help_ctx_ev_go(+is_zero: Bool, +tfocus: Bool, +vs: ViewSt) -> U32:
  match is_zero:
    case False{}: 6
    case True{}:
      match tfocus:
        case True{}: 8
        case False{}: acc_help_ctx_rf(viewst_rfocus(vs))

def acc_help_ctx_ev(+tfocus: Bool, +entry_mode: U32, +vs: ViewSt) -> U32:
  acc_help_ctx_ev_go(U32.is_eq(entry_mode, 0), tfocus, vs)

def acc_help_ctx_for(+tag: U32, +tfocus: Bool, +entry_mode: U32, +vs: ViewSt) -> U32:
  match tag:
    case 0: acc_help_ctx_ev(tfocus, entry_mode, vs)
    case _: tag

def acc_help_toggle_go(+help: HelpSt, +acc: AccSt, +tfocus: Bool, +entry_mode: U32, +vs: ViewSt) -> (AccSt & Bool):
  match help:
    case HOn{_}: (acc_help_close(acc), True{})
    case HOff{}: (acc_help_open(acc, acc_help_ctx_for(acc_panel_tag(acc), tfocus, entry_mode, vs)), True{})

def acc_help_toggle(+acc: AccSt, +tfocus: Bool, +entry_mode: U32, +vs: ViewSt) -> (AccSt & Bool):
  acc_help_toggle_go(acc_help_of(acc), acc, tfocus, entry_mode, vs)


# ---------- command palette keys (Wave 3) ----------
# Placed after every panel key handler (defs must precede use) and before
# acc_scan_tagged, which routes tag 5 here. Enter dispatches the selected
# action's KEY through the same tag-routed handlers with the palette
# pre-dismissed (mirrors acc_scan_tagged — no mutual recursion, no
# duplicated behavior). When the underlying handler reports the key
# unconsumed (False{}), it belongs to the EvSt/Tab/Prof/fetch fold: the key
# is parked in Pal.fire and re-injected as one synthetic Key event AFTER
# acc_strip in tick_fold_acc_applied (a real keypress with panels open
# would be stripped, so the synthetic one is dropped when any panel is
# still open post-dispatch — exactly the physical key's fate).

def acc_pal_dispatch(+tag: U32, +acc: AccSt, +items: List<&2, Item>, +key: U32, +tfocus: Bool, +entry_mode: U32, +vs: ViewSt, +feed: String, +termlines: List<&2, String>) -> (AccSt & Bool):
  match tag:
    case 1: acc_search_key(acc, items, key, feed, termlines)
    case 2: acc_note_key(acc, key)
    case 3: acc_gmail_key(acc, key)
    case 4: acc_ai_key(acc, key)
    case _: acc_closed_key(acc, key, tfocus, entry_mode, vs, feed)

def acc_pal_fired(+fired: Bool, +acc3: AccSt, +key: U32) -> (AccSt & Bool):
  match fired:
    case True{}: (acc3, True{})
    case False{}: (acc_pal_set_fire(acc3, key), True{})

def acc_pal_enter_pick2(res: AccSt & Bool, +key: U32) -> (AccSt & Bool):
  match res:
    case (acc3, fired): acc_pal_fired(fired, acc3, key)

def acc_pal_enter_pick(+closed: AccSt, +key: U32, +items: List<&2, Item>, +tfocus: Bool, +entry_mode: U32, +vs: ViewSt, +feed: String, +termlines: List<&2, String>) -> (AccSt & Bool):
  acc_pal_enter_pick2(acc_pal_dispatch(acc_panel_tag(closed), closed, items, key, tfocus, entry_mode, vs, feed, termlines), key)

def acc_pal_enter_pick0(+sel: Maybe<&2, PalAct>, +acc: AccSt, +items: List<&2, Item>, +tfocus: Bool, +entry_mode: U32, +vs: ViewSt, +feed: String, +termlines: List<&2, String>) -> (AccSt & Bool):
  match sel:
    case None{}: (acc, True{})
    case Some{PAct{key, _, _}}: acc_pal_enter_pick(acc_pal_close(acc), key, items, tfocus, entry_mode, vs, feed, termlines)

def acc_pal_enter(+acc: AccSt, +items: List<&2, Item>, +tfocus: Bool, +entry_mode: U32, +vs: ViewSt, +feed: String, +termlines: List<&2, String>) -> (AccSt & Bool):
  acc_pal_enter_pick0(pal_at(pal_filter(acc_pal_q(acc_pal_of(acc)), pal_actions(pal_ctx_of(acc))), acc_pal_sel(acc_pal_of(acc))), acc, items, tfocus, entry_mode, vs, feed, termlines)

def acc_pal_up_go(+is_zero: Bool, +sel: U32) -> U32:
  match is_zero:
    case True{}: 0
    case False{}: U32.sub(sel, 1)

def acc_pal_down_go(+can_down: Bool, +sel: U32) -> U32:
  match can_down:
    case True{}: U32.add(sel, 1)
    case False{}: sel

def acc_pal_move_go(+up: Bool, +sel: U32, +n: U32) -> U32:
  match up:
    case True{}: acc_pal_up_go(U32.is_eq(sel, 0), sel)
    case False{}: acc_pal_down_go(U32.is_lt(U32.add(sel, 1), n), sel)

def acc_pal_move(+acc: AccSt, +up: Bool) -> AccSt:
  match acc:
    case Acc{sq, sopen, ssel, gmail, ai, note, save_req, accd, search_go, Pal{pq, popen, psel, _}, help}:
      Acc{sq, sopen, ssel, gmail, ai, note, save_req, accd, search_go, Pal{pq, popen, acc_pal_move_go(up, psel, pal_count(pal_filter(pq, pal_actions(pal_ctx_gmail(gmail))))), 0}, help}

def acc_pal_type(+acc: AccSt, +q: String) -> AccSt:
  match acc:
    case Acc{sq, sopen, ssel, gmail, ai, note, save_req, accd, search_go, Pal{_, popen, _, _}, help}:
      Acc{sq, sopen, ssel, gmail, ai, note, save_req, accd, search_go, Pal{q, popen, 0, 0}, help}

def acc_pal_bs(+acc: AccSt) -> AccSt:
  match acc:
    case Acc{sq, sopen, ssel, gmail, ai, note, save_req, accd, search_go, Pal{pq, popen, _, _}, help}:
      Acc{sq, sopen, ssel, gmail, ai, note, save_req, accd, search_go, Pal{entry_backspace(pq), popen, 0, 0}, help}

def acc_pal_print_go(+ok: Bool, +acc: AccSt, +c: U32) -> (AccSt & Bool):
  match ok:
    case True{}: (acc_pal_type(acc, entry_append(acc_pal_q(acc_pal_of(acc)), c)), True{})
    case False{}: (acc, False{})

def acc_pal_print(+acc: AccSt, +c: U32) -> (AccSt & Bool):
  acc_pal_print_go(U32.is_lt(c, 128), acc, c)

def acc_pal_key(+acc: AccSt, +items: List<&2, Item>, +c: U32, +tfocus: Bool, +entry_mode: U32, +vs: ViewSt, +feed: String, +termlines: List<&2, String>) -> (AccSt & Bool):
  match c:
    case 27: (acc_pal_close(acc), True{})
    case 59: (acc_pal_close(acc), True{})
    case 13: acc_pal_enter(acc, items, tfocus, entry_mode, vs, feed, termlines)
    case 63232: (acc_pal_move(acc, True{}), True{})
    case 63233: (acc_pal_move(acc, False{}), True{})
    case 127: (acc_pal_bs(acc), True{})
    case 8: (acc_pal_bs(acc), True{})
    case _: acc_pal_print(acc, c)

def acc_scan_tagged(+tag: U32, +acc: AccSt, +items: List<&2, Item>, +c: U32, +tfocus: Bool, +entry_mode: U32, +vs: ViewSt, +feed: String, +termlines: List<&2, String>) -> (AccSt & Bool):
  match tag:
    case 1: acc_search_key(acc, items, c, feed, termlines)
    case 2: acc_note_key(acc, c)
    case 3: acc_gmail_key(acc, c)
    case 4: acc_ai_key(acc, c)
    case 5: acc_pal_key(acc, items, c, tfocus, entry_mode, vs, feed, termlines)
    case 6: acc_help_key(acc, c)
    case _: acc_closed_key(acc, c, tfocus, entry_mode, vs, feed)

def acc_scan_key_go(+is_help: Bool, +acc: AccSt, +items: List<&2, Item>, +c: U32, +tfocus: Bool, +entry_mode: U32, +vs: ViewSt, +feed: String, +termlines: List<&2, String>) -> (AccSt & Bool):
  match is_help:
    case True{}: acc_help_toggle(acc, tfocus, entry_mode, vs)
    case False{}: acc_scan_tagged(acc_panel_tag(acc), acc, items, c, tfocus, entry_mode, vs, feed, termlines)

def acc_scan_key(+acc: AccSt, +items: List<&2, Item>, +c: U32, +tfocus: Bool, +entry_mode: U32, +vs: ViewSt, +feed: String, +termlines: List<&2, String>) -> (AccSt & Bool):
  acc_scan_key_go(U32.is_eq(c, 63), acc, items, c, tfocus, entry_mode, vs, feed, termlines)

# ----- scan / strip -----

def acc_scan_key_acc(kr: AccSt & Bool) -> AccSt:
  match kr:
    case (acc2, _): acc2

def acc_scan_go(evs: List<Event>, +acc: AccSt, +items: List<&2, Item>, +tfocus: Bool, +entry_mode: U32, +vs: ViewSt, +feed: String, +termlines: List<&2, String>, kept: List<Event>) -> (AccSt & List<Event>):
  match evs:
    case Nil{}: (acc, kept)
    case Key{+code, True{}} <> rest:
      acc_scan_go(rest, acc_scan_key_acc(acc_scan_key(acc, items, code, tfocus, entry_mode, vs, feed, termlines)), items, tfocus, entry_mode, vs, feed, termlines, Con{Key{code, True{}}, kept})
    case e <> rest:
      acc_scan_go(rest, acc, items, tfocus, entry_mode, vs, feed, termlines, Con{e, kept})

def acc_scan(+acc: AccSt, +items: List<&2, Item>, evs: List<Event>, +tfocus: Bool, +entry_mode: U32, +vs: ViewSt, +feed: String, +termlines: List<&2, String>) -> (AccSt & List<Event>):
  acc_scan_go(evs, acc, items, tfocus, entry_mode, vs, feed, termlines, Nil{})

def acc_list_rev(xs: List<Event>, acc: List<Event>) -> List<Event>:
  match xs:
    case Nil{}: acc
    case h <> t: acc_list_rev(t, Con{h, acc})

def acc_strip_keys(evs: List<Event>, kept: List<Event>) -> List<Event>:
  match evs:
    case Nil{}: acc_list_rev(kept, Nil{})
    case e <> rest:
      match e:
        case Key{_, _}: acc_strip_keys(rest, kept)
        case _: acc_strip_keys(rest, Con{e, kept})

def acc_strip_q(+pre: AccSt, +post: AccSt) -> Bool:
  Bool.or(acc_any_open(pre), acc_any_open(post))

def acc_strip_go(+strip: Bool, evs: List<Event>, kept: List<Event>) -> List<Event>:
  match strip:
    case False{}: evs
    case True{}: acc_strip_keys(evs, kept)

# ----- search jump application (Enter on a highlighted hit) -----

def acc_apply_hit(+hit: SearchHit, +sel: U32, +tfocus: Bool, +vs: ViewSt, +feed: String) -> (U32 & Bool & ViewSt):
  match hit:
    case HItem{i}: (i, False{}, viewst_page_reset(vs))
    case HRead{a}: (sel, False{}, viewst_focus_read(vs, a, feed))
    case HTerm{_}: (sel, True{}, vs)

def acc_apply_go(+go: Maybe<&2, SearchHit>, +sel: U32, +tfocus: Bool, +vs: ViewSt, +feed: String) -> (U32 & Bool & ViewSt):
  match go:
    case None{}: (sel, tfocus, vs)
    case Some{hit}: acc_apply_hit(hit, sel, tfocus, vs, feed)

# ----- note commit (IO preamble) -----

def acc_note_items(+items: List<&2, Item>, +title: String, +url: String, +text: String, +now: Nat) -> List<&2, Item>:
  append_item(items, Con{It{title, 4, text, now, url}, Nil{}})

def acc_note_saved(+items2: List<&2, Item>, +profile: String, +acc2: AccSt) -> IO(List<&2, Item> & AccSt):
  do IO<List<&2, Item> & AccSt>:
    _ok : Bool <- save_items_file(items2, profile_file(profile))
    IO.pure(List<&2, Item> & AccSt, (items2, acc2))

def acc_note_commit_go(+q: String, +open: Bool, +sel: U32, +gmail: MailSt, +ai: AISt, +title: String, +url: String, +text: String, +save_req: Bool, +search_go: Maybe<&2, SearchHit>, +help: HelpSt, +items: List<&2, Item>, +profile: String) -> IO(List<&2, Item> & AccSt):
  do IO<List<&2, Item> & AccSt>:
    now : Nat <- IO.now()
    acc_note_saved(acc_note_items(items, title, url, text, now), profile, Acc{q, open, sel, gmail, ai, NOff{}, save_req, True{}, search_go, Pal{"", False{}, 0, 0}, help})

def acc_note_commit(+acc: AccSt, +items: List<&2, Item>, +profile: String) -> IO(List<&2, Item> & AccSt):
  match acc:
    case Acc{q, open, sel, gmail, ai, NCommit{title, url, text}, save_req, _, search_go, _, help}:
      acc_note_commit_go(q, open, sel, gmail, ai, title, url, text, save_req, search_go, help, items, profile)
    case _: IO.pure(List<&2, Item> & AccSt, (items, acc))

# ----- AI apply (IO preamble) -----

def acc_applied(+acc: AccSt, +suggs: List<&2, AISugg>, +cur: U32) -> AccSt:
  match acc:
    case Acc{q, open, sel, gmail, _, note, _, _, search_go, pal, help}:
      Acc{q, open, sel, gmail, AOn{AISuggSt{suggs, cur, True{}}}, note, False{}, True{}, search_go, pal, help}

def acc_ai_saved(+items2: List<&2, Item>, +profile: String, +acc: AccSt, +suggs: List<&2, AISugg>, +cur: U32) -> IO(List<&2, Item> & AccSt):
  do IO<List<&2, Item> & AccSt>:
    _ok : Bool <- save_items_file(items2, profile_file(profile))
    IO.pure(List<&2, Item> & AccSt, (items2, acc_applied(acc, suggs, cur)))

def acc_ai_apply_go(+acc: AccSt, +items: List<&2, Item>, +profile: String, +suggs: List<&2, AISugg>, +cur: U32) -> IO(List<&2, Item> & AccSt):
  acc_ai_saved(ai_apply(items, suggs), profile, acc, suggs, cur)

def acc_ai_apply_step2(+a: AISt, +acc: AccSt, +items: List<&2, Item>, +profile: String) -> IO(List<&2, Item> & AccSt):
  match a:
    case AOn{AISuggSt{suggs, cur, _}}: acc_ai_apply_go(acc, items, profile, suggs, cur)
    case _: IO.pure(List<&2, Item> & AccSt, (items, acc))

def acc_ai_apply_step(+acc: AccSt, +items: List<&2, Item>, +profile: String) -> IO(List<&2, Item> & AccSt):
  acc_ai_apply_step2(acc_ai_inner(acc), acc, items, profile)

# ----- Gmail IO (preamble; one transition per tick, never self-retries) -----

def acc_gmail_creds3(+id: String, +sec: String, +rtok: Maybe<&2, String>) -> MailInner:
  match rtok:
    case None{}: MCfgErr{"missing refresh_token"}
    case Some{rt}: MLoading{id, sec, rt, "", mail_pg_fresh(), "", None{}}

def acc_gmail_creds2(+id: String, +csec: Maybe<&2, String>, +rtok: Maybe<&2, String>) -> MailInner:
  match csec:
    case None{}: MCfgErr{"missing client_secret"}
    case Some{sec}: acc_gmail_creds3(id, sec, rtok)

def acc_gmail_creds(+cid: Maybe<&2, String>, +csec: Maybe<&2, String>, +rtok: Maybe<&2, String>) -> MailInner:
  match cid:
    case None{}: MCfgErr{"missing client_id"}
    case Some{id}: acc_gmail_creds2(id, csec, rtok)

def acc_gmail_boot_inner(+cr: CfgRes) -> MailInner:
  match cr:
    case CfgOk{kv}: acc_gmail_creds(cfg_get(kv, "client_id"), cfg_get(kv, "client_secret"), cfg_get(kv, "refresh_token"))
    case CfgAbsent{}: MNotCfg{}
    case CfgBadPerm{}: MCfgErr{"config not owner-only (want 0600)"}
    case CfgBad{}: MCfgErr{"config unreadable"}

def acc_gmail_boot(+acc: AccSt, +items: List<&2, Item>) -> IO(List<&2, Item> & AccSt):
  do IO<List<&2, Item> & AccSt>:
    cr : CfgRes <- cfg_load("gmail.conf")
    IO.pure(List<&2, Item> & AccSt, (items, acc_set_gmail(acc, MOn{acc_gmail_boot_inner(cr)})))

# After gmail_list returns IDs, fetch metadata (Subject/From/Date + snippet)
# for each — gmail_get uses format=metadata, so this is lightweight.
# Failures are skipped; the list shows whatever loaded.
def acc_gmail_metas_add(gr: Result<&1,&1, U32 & String, (MailMeta & String)>, +metas: List<&2, MailMeta>) -> List<&2, MailMeta>:
  match gr:
    case Fail{_}: metas
    case Done{(meta, _)}: List.append(&2, MailMeta, metas, Con{meta, Nil{}})

def acc_gmail_metas_go(ids: List<&2, String>, +token: String, +metas: List<&2, MailMeta>) -> IO(List<&2, MailMeta>):
  match ids:
    case Nil{}: IO.pure(List<&2, MailMeta>, metas)
    case id <> rest:
      do IO<List<&2, MailMeta>>:
        gr : Result<&1,&1, U32 & String, (MailMeta & String)> <- gmail_get(token, id)
        acc_gmail_metas_go(rest, token, acc_gmail_metas_add(gr, metas))

def acc_gmail_listed_metas(+acc: AccSt, +items: List<&2, Item>, +cid: String, +csec: String, +rtok: String, +token: String, +exp: Nat, +q: String, ids: List<&2, String>, +nxt: Maybe<&2, String>, +page: U32, +ptok: String, +toks: List<&2, String>) -> IO(List<&2, Item> & AccSt):
  do IO<List<&2, Item> & AccSt>:
    metas : List<&2, MailMeta> <- acc_gmail_metas_go(ids, token, Nil{})
    IO.pure(List<&2, Item> & AccSt, (items, acc_set_gmail(acc, MOn{MList{cid, csec, rtok, token, exp, q, 0, metas, MPg{page, mail_toks_push(toks, page, ptok), nxt, None{}}}})))

def acc_gmail_listed2(lr: Result<&1,&1, U32 & String, (List<&2, String> & Maybe<&2, String>)>, +acc: AccSt, +items: List<&2, Item>, +cid: String, +csec: String, +rtok: String, +token: String, +exp: Nat, +q: String, +page: U32, +ptok: String, +toks: List<&2, String>, +prev: Maybe<&2, MailInner>) -> IO(List<&2, Item> & AccSt):
  match lr:
    case Fail{e}: IO.pure(List<&2, Item> & AccSt, (items, acc_set_gmail(acc, MOn{mail_list_fail(prev, e)})))
    case Done{(ids, nxt)}: acc_gmail_listed_metas(acc, items, cid, csec, rtok, token, exp, q, ids, nxt, page, ptok, toks)

def acc_gmail_listed_go(+acc: AccSt, +items: List<&2, Item>, +cid: String, +csec: String, +rtok: String, +token: String, +exp: Nat, +q: String, +page: U32, +ptok: String, +toks: List<&2, String>, +prev: Maybe<&2, MailInner>) -> IO(List<&2, Item> & AccSt):
  do IO<List<&2, Item> & AccSt>:
    lr : Result<&1,&1, U32 & String, (List<&2, String> & Maybe<&2, String>)> <- gmail_list(token, q, ptok)
    acc_gmail_listed2(lr, acc, items, cid, csec, rtok, token, exp, q, page, ptok, toks, prev)

def acc_gmail_listed(+acc: AccSt, +items: List<&2, Item>, +cid: String, +csec: String, +rtok: String, +q: String, +page: U32, +ptok: String, +toks: List<&2, String>, +prev: Maybe<&2, MailInner>, tr: Result<&1,&1, U32 & String, (String & Nat)>) -> IO(List<&2, Item> & AccSt):
  match tr:
    case Fail{e}: IO.pure(List<&2, Item> & AccSt, (items, acc_set_gmail(acc, MOn{mail_list_fail(prev, e)})))
    case Done{(token, exp)}: acc_gmail_listed_go(acc, items, cid, csec, rtok, token, exp, q, page, ptok, toks, prev)

def acc_gmail_load(+acc: AccSt, +items: List<&2, Item>, +cid: String, +csec: String, +rtok: String, +q: String, +page: U32, +ptok: String, +toks: List<&2, String>, +prev: Maybe<&2, MailInner>) -> IO(List<&2, Item> & AccSt):
  do IO<List<&2, Item> & AccSt>:
    tr : Result<&1,&1, U32 & String, (String & Nat)> <- gmail_refresh(cid, csec, rtok)
    acc_gmail_listed(acc, items, cid, csec, rtok, q, page, ptok, toks, prev, tr)

def acc_gmail_meta_id(+meta: MailMeta) -> String:
  match meta:
    case MM{id, _, _, _}: id

def acc_gmail_got(+cid: String, +csec: String, +rtok: String, +token: String, +exp: Nat, +q: String, +meta: MailMeta, +cur: U32, +metas: List<&2, MailMeta>, +pg: MailPage, gr: Result<&1,&1, U32 & String, (MailMeta & String)>) -> MailInner:
  match gr:
    case Fail{e}: mail_err_inner(e)
    case Done{(_, body)}: MReading{cid, csec, rtok, token, exp, q, meta, body, cur, metas, pg}

def acc_gmail_fetch_get(+acc: AccSt, +items: List<&2, Item>, +cid: String, +csec: String, +rtok: String, +token: String, +exp: Nat, +q: String, +meta: MailMeta, +cur: U32, +metas: List<&2, MailMeta>, +pg: MailPage) -> IO(List<&2, Item> & AccSt):
  do IO<List<&2, Item> & AccSt>:
    gr : Result<&1,&1, U32 & String, (MailMeta & String)> <- gmail_get(token, acc_gmail_meta_id(meta))
    IO.pure(List<&2, Item> & AccSt, (items, acc_set_gmail(acc, MOn{acc_gmail_got(cid, csec, rtok, token, exp, q, meta, cur, metas, pg, gr)})))

def acc_gmail_refetched(+acc: AccSt, +items: List<&2, Item>, +cid: String, +csec: String, +rtok: String, +q: String, +meta: MailMeta, +cur: U32, +metas: List<&2, MailMeta>, +pg: MailPage, tr: Result<&1,&1, U32 & String, (String & Nat)>) -> IO(List<&2, Item> & AccSt):
  match tr:
    case Fail{e}: IO.pure(List<&2, Item> & AccSt, (items, acc_set_gmail(acc, MOn{mail_err_inner(e)})))
    case Done{(token, exp)}: acc_gmail_fetch_get(acc, items, cid, csec, rtok, token, exp, q, meta, cur, metas, pg)

def acc_gmail_refetch(+acc: AccSt, +items: List<&2, Item>, +cid: String, +csec: String, +rtok: String, +q: String, +meta: MailMeta, +cur: U32, +metas: List<&2, MailMeta>, +pg: MailPage) -> IO(List<&2, Item> & AccSt):
  do IO<List<&2, Item> & AccSt>:
    tr : Result<&1,&1, U32 & String, (String & Nat)> <- gmail_refresh(cid, csec, rtok)
    acc_gmail_refetched(acc, items, cid, csec, rtok, q, meta, cur, metas, pg, tr)

def acc_gmail_fetch_go2(+fresh: Bool, +acc: AccSt, +items: List<&2, Item>, +cid: String, +csec: String, +rtok: String, +token: String, +exp: Nat, +q: String, +meta: MailMeta, +cur: U32, +metas: List<&2, MailMeta>, +pg: MailPage) -> IO(List<&2, Item> & AccSt):
  match fresh:
    case True{}: acc_gmail_fetch_get(acc, items, cid, csec, rtok, token, exp, q, meta, cur, metas, pg)
    case False{}: acc_gmail_refetch(acc, items, cid, csec, rtok, q, meta, cur, metas, pg)

def acc_gmail_fetch_go(+acc: AccSt, +items: List<&2, Item>, +cid: String, +csec: String, +rtok: String, +token: String, +exp: Nat, +q: String, +meta: MailMeta, +cur: U32, +metas: List<&2, MailMeta>, +pg: MailPage, +now: Nat) -> IO(List<&2, Item> & AccSt):
  acc_gmail_fetch_go2(Nat.is_lt(now, exp), acc, items, cid, csec, rtok, token, exp, q, meta, cur, metas, pg)

def acc_gmail_fetch(+acc: AccSt, +items: List<&2, Item>, +cid: String, +csec: String, +rtok: String, +token: String, +exp: Nat, +q: String, +meta: MailMeta, +cur: U32, +metas: List<&2, MailMeta>, +pg: MailPage) -> IO(List<&2, Item> & AccSt):
  do IO<List<&2, Item> & AccSt>:
    now : Nat <- IO.now()
    acc_gmail_fetch_go(acc, items, cid, csec, rtok, token, exp, q, meta, cur, metas, pg, now)

def acc_gmail_load_pg(+acc: AccSt, +items: List<&2, Item>, +cid: String, +csec: String, +rtok: String, +q: String, +pg: MailPage, +ptok: String, +prev: Maybe<&2, MailInner>) -> IO(List<&2, Item> & AccSt):
  match pg:
    case MPg{page, toks, _, _}: acc_gmail_load(acc, items, cid, csec, rtok, q, page, ptok, toks, prev)

def acc_gmail_step2(+m: MailSt, +acc: AccSt, +items: List<&2, Item>) -> IO(List<&2, Item> & AccSt):
  match m:
    case MOn{MUnknown{}}: acc_gmail_boot(acc, items)
    case MOn{MLoading{cid, csec, rtok, q, pg, ptok, prev}}: acc_gmail_load_pg(acc, items, cid, csec, rtok, q, pg, ptok, prev)
    case MOn{MFetchMsg{cid, csec, rtok, token, exp, q, meta, cur, metas, pg}}: acc_gmail_fetch(acc, items, cid, csec, rtok, token, exp, q, meta, cur, metas, pg)
    case _: IO.pure(List<&2, Item> & AccSt, (items, acc))

def acc_gmail_step(+acc: AccSt, +items: List<&2, Item>) -> IO(List<&2, Item> & AccSt):
  acc_gmail_step2(acc_gmail_inner(acc), acc, items)

# ----- AI IO (preamble) -----

def acc_ai_boot_cfg3(+e: String, +k: String, +model: Maybe<&2, String>) -> AIInner:
  match model:
    case None{}: AIErr{}
    case Some{_}: AIIdle{}

def acc_ai_boot_cfg2(+e: String, +key: Maybe<&2, String>, +model: Maybe<&2, String>) -> AIInner:
  match key:
    case None{}: AIErr{}
    case Some{k}: acc_ai_boot_cfg3(e, k, model)

def acc_ai_boot_cfg(+ep: Maybe<&2, String>, +key: Maybe<&2, String>, +model: Maybe<&2, String>) -> AIInner:
  match ep:
    case None{}: AIErr{}
    case Some{e}: acc_ai_boot_cfg2(e, key, model)

def acc_ai_boot_inner(+cr: CfgRes) -> AIInner:
  match cr:
    case CfgOk{kv}: acc_ai_boot_cfg(cfg_get(kv, "endpoint"), cfg_get(kv, "api_key"), cfg_get(kv, "model"))
    case CfgAbsent{}: AINone{}
    case CfgBadPerm{}: AIErr{}
    case CfgBad{}: AIErr{}

def acc_ai_boot(+acc: AccSt, +items: List<&2, Item>) -> IO(List<&2, Item> & AccSt):
  do IO<List<&2, Item> & AccSt>:
    cr : CfgRes <- cfg_load("ai.conf")
    IO.pure(List<&2, Item> & AccSt, (items, acc_set_ai(acc, AOn{acc_ai_boot_inner(cr)})))

def acc_ai_content_go(+mc: Maybe<&2, String>) -> String:
  match mc:
    case None{}: ""
    case Some{c}: c

def acc_ai_content(+body: String) -> String:
  acc_ai_content_go(ai_content(body))

def acc_ai_suggs(+suggs: List<&2, AISugg>) -> AIInner:
  match suggs:
    case Nil{}: AIErr{}
    case _ <> _: AISuggSt{suggs, 0, False{}}

def acc_ai_parsed2(+is_200: Bool, +body: String) -> AIInner:
  match is_200:
    case False{}: AIErr{}
    case True{}: acc_ai_suggs(ai_parse_sugg(acc_ai_content(body)))

def acc_ai_parsed(rr: Result<&1, &1, U32 & String, (U32 & String)>) -> AIInner:
  match rr:
    case Fail{_}: AIErr{}
    case Done{(status, body)}: acc_ai_parsed2(U32.is_eq(status, 200), body)

def acc_ai_send_req(+acc: AccSt, +items: List<&2, Item>, +ep: String, +key: String, +model: String) -> IO(List<&2, Item> & AccSt):
  do IO<List<&2, Item> & AccSt>:
    rr : Result<&1, &1, U32 & String, (U32 & String)> <- ai_send(ep, key, ai_req_body(ai_titles(items), model))
    IO.pure(List<&2, Item> & AccSt, (items, acc_set_ai(acc, AOn{acc_ai_parsed(rr)})))

def acc_ai_send_cfg3(+acc: AccSt, +items: List<&2, Item>, +ep: String, +key: String, +model: Maybe<&2, String>) -> IO(List<&2, Item> & AccSt):
  match model:
    case None{}: IO.pure(List<&2, Item> & AccSt, (items, acc_set_ai(acc, AOn{AIErr{}})))
    case Some{m}: acc_ai_send_req(acc, items, ep, key, m)

def acc_ai_send_cfg2(+acc: AccSt, +items: List<&2, Item>, +ep: String, +key: Maybe<&2, String>, +model: Maybe<&2, String>) -> IO(List<&2, Item> & AccSt):
  match key:
    case None{}: IO.pure(List<&2, Item> & AccSt, (items, acc_set_ai(acc, AOn{AIErr{}})))
    case Some{k}: acc_ai_send_cfg3(acc, items, ep, k, model)

def acc_ai_send_cfg(+acc: AccSt, +items: List<&2, Item>, +ep: Maybe<&2, String>, +key: Maybe<&2, String>, +model: Maybe<&2, String>) -> IO(List<&2, Item> & AccSt):
  match ep:
    case None{}: IO.pure(List<&2, Item> & AccSt, (items, acc_set_ai(acc, AOn{AIErr{}})))
    case Some{e}: acc_ai_send_cfg2(acc, items, e, key, model)

def acc_ai_send_cfg_loaded(+cr: CfgRes, +acc: AccSt, +items: List<&2, Item>) -> IO(List<&2, Item> & AccSt):
  match cr:
    case CfgOk{kv}: acc_ai_send_cfg(acc, items, cfg_get(kv, "endpoint"), cfg_get(kv, "api_key"), cfg_get(kv, "model"))
    case _: IO.pure(List<&2, Item> & AccSt, (items, acc_set_ai(acc, AOn{AIErr{}})))

def acc_ai_send_step(+acc: AccSt, +items: List<&2, Item>) -> IO(List<&2, Item> & AccSt):
  do IO<List<&2, Item> & AccSt>:
    cr : CfgRes <- cfg_load("ai.conf")
    acc_ai_send_cfg_loaded(cr, acc, items)

def acc_ai_step2(+a: AISt, +acc: AccSt, +items: List<&2, Item>) -> IO(List<&2, Item> & AccSt):
  match a:
    case AOn{AIUnknown{}}: acc_ai_boot(acc, items)
    case AOn{AISending{}}: acc_ai_send_step(acc, items)
    case _: IO.pure(List<&2, Item> & AccSt, (items, acc))

def acc_ai_step(+acc: AccSt, +items: List<&2, Item>) -> IO(List<&2, Item> & AccSt):
  acc_ai_step2(acc_ai_inner(acc), acc, items)

# ----- IO preamble dispatcher -----

def acc_io_step(+acc: AccSt, +items: List<&2, Item>, +profile: String) -> IO(List<&2, Item> & AccSt):
  match acc:
    case Acc{_, _, _, _, _, NCommit{_, _, _}, _, _, _, _, help}: acc_note_commit(acc, items, profile)
    case Acc{_, _, _, _, _, _, True{}, _, _, _, help}: acc_ai_apply_step(acc, items, profile)
    case Acc{_, _, _, MOn{MUnknown{}}, _, _, _, _, _, _, help}: acc_gmail_step(acc, items)
    case Acc{_, _, _, MOn{MLoading{_, _, _, _, _, _, _}}, _, _, _, _, _, _, help}: acc_gmail_step(acc, items)
    case Acc{_, _, _, MOn{MFetchMsg{_, _, _, _, _, _, _, _, _, _}}, _, _, _, _, _, _, help}: acc_gmail_step(acc, items)
    case Acc{_, _, _, _, AOn{AIUnknown{}}, _, _, _, _, _, help}: acc_ai_step(acc, items)
    case Acc{_, _, _, _, AOn{AISending{}}, _, _, _, _, _, help}: acc_ai_step(acc, items)
    case _: IO.pure(List<&2, Item> & AccSt, (items, acc))

# ----- tick integration -----

def acc_scan_termlines2(+is_open: Bool, +tabs: List<&2, Tab>, +tab_idx: U32) -> List<&2, String>:
  match is_open:
    case True{}: term_all_lines(tab_term(tabs_get(tabs, tab_idx)))
    case False{}: Nil{}

def acc_scan_termlines(+acc: AccSt, +tabs: List<&2, Tab>, +tab_idx: U32) -> List<&2, String>:
  acc_scan_termlines2(acc_any_open(acc), tabs, tab_idx)

def tick_fold_acc_applied(jump: U32 & Bool & ViewSt, +pre: AccSt, +acc3: AccSt, +items2: List<&2, Item>, evs2: List<Event>, +sel: U32, +d: Nat, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus: Bool, +vs: ViewSt, +entry: String, +entry_mode: U32, +mx: U32, +my: U32, +hover: U32, +profile: String, +feed: String) -> IO(Maybe<ShellSt>):
  match jump:
    case (sel2, tfocus2, vs2):
      tick_fold2(tick_ev_go2(acc_fire_evs(acc3, acc_strip_go(acc_strip_q(pre, acc3), evs2, Nil{})), FSt{evst_new(sel2, items2, tfocus2, vs2, entry, entry_mode), MSt{mx, my, hover}, TSt{tab_idx, 0}, PSt{profile, ""}, FchSt{False{}, False{}, feed}, sb_none()}), sel, d, frame, tabs, tab_idx, tfocus, vs, entry_mode, hover, feed, acc_search_go_cleared(acc3))

def tick_fold_acc_stripped(+pre: AccSt, +acc3: AccSt, +items2: List<&2, Item>, evs2: List<Event>, +sel: U32, +d: Nat, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus: Bool, +vs: ViewSt, +entry: String, +entry_mode: U32, +mx: U32, +my: U32, +hover: U32, +profile: String, +feed: String) -> IO(Maybe<ShellSt>):
  tick_fold_acc_applied(acc_apply_go(acc_search_go_of(acc3), sel, tfocus, vs, feed), pre, acc3, items2, evs2, sel, d, frame, tabs, tab_idx, tfocus, vs, entry, entry_mode, mx, my, hover, profile, feed)

def tick_fold_acc_scanned(pr: AccSt & List<Event>, +pre: AccSt, +items2: List<&2, Item>, +sel: U32, +d: Nat, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus: Bool, +vs: ViewSt, +entry: String, +entry_mode: U32, +mx: U32, +my: U32, +hover: U32, +profile: String, +feed: String) -> IO(Maybe<ShellSt>):
  match pr:
    case (acc3, rev):
      tick_fold_acc_stripped(pre, acc3, items2, acc_list_rev(rev, Nil{}), sel, d, frame, tabs, tab_idx, tfocus, vs, entry, entry_mode, mx, my, hover, profile, feed)

def tick_fold_acc_scan(+acc2: AccSt, +items2: List<&2, Item>, evs: List<Event>, +sel: U32, +d: Nat, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus: Bool, +vs: ViewSt, +entry: String, +entry_mode: U32, +mx: U32, +my: U32, +hover: U32, +profile: String, +feed: String) -> IO(Maybe<ShellSt>):
  tick_fold_acc_scanned(acc_scan(acc2, items2, evs, tfocus, entry_mode, vs, feed, acc_scan_termlines(acc2, tabs, tab_idx)), acc2, items2, sel, d, frame, tabs, tab_idx, tfocus, vs, entry, entry_mode, mx, my, hover, profile, feed)

def tick_fold_acc_step(step: List<&2, Item> & AccSt, evs: List<Event>, +sel: U32, +d: Nat, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus: Bool, +vs: ViewSt, +entry: String, +entry_mode: U32, +mx: U32, +my: U32, +hover: U32, +profile: String, +feed: String) -> IO(Maybe<ShellSt>):
  match step:
    case (items2, acc2):
      tick_fold_acc_scan(acc2, items2, evs, sel, d, frame, tabs, tab_idx, tfocus, vs, entry, entry_mode, mx, my, hover, profile, feed)

def tick_fold_acc(+acc: AccSt, evs: List<Event>, +sel: U32, +d: Nat, +items: List<&2, Item>, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus: Bool, +vs: ViewSt, +entry: String, +entry_mode: U32, +mx: U32, +my: U32, +hover: U32, +profile: String, +feed: String) -> IO(Maybe<ShellSt>):
  do IO<Maybe<ShellSt>>:
    step : List<&2, Item> & AccSt <- acc_io_step(acc, items, profile)
    tick_fold_acc_step(step, evs, sel, d, frame, tabs, tab_idx, tfocus, vs, entry, entry_mode, mx, my, hover, profile, feed)

def tick_fold(evs: List<Event>, +sel: U32, +d: Nat, +items: List<&2, Item>, frame: Image, +tabs: List<&2, Tab>, +tab_idx: U32, +tfocus: Bool, +vs: ViewSt, +entry: String, +entry_mode: U32, +mx: U32, +my: U32, +hover: U32, +profile: String, +feed: String, +acc: AccSt) -> IO(Maybe<ShellSt>):
  tick_fold_acc(acc, evs, sel, d, items, frame, tabs, tab_idx, tfocus, vs, entry, entry_mode, mx, my, hover, profile, feed)

def shell_tick(evs: List<Event>, s: ShellSt) -> IO(Maybe<ShellSt>):
  match s:
    case SSt{sel, d, items, frame, tabs, tab_idx, tfocus, vs, entry, entry_mode, mx, my, hover, profile, feed, acc}:
      tick_fold(evs, sel, d, items, frame, tabs, tab_idx, tfocus, vs, entry, entry_mode, mx, my, hover, profile, feed, acc)

def shell_app() -> App<ShellSt>:
  App{shell_view, shell_tick}

# acc_new: initial accumulator state for the four accretive features.
def acc_new() -> AccSt:
  Acc{"", False{}, 0, MOff{}, AOff{}, NOff{}, False{}, False{}, None{}, Pal{"", False{}, 0, 0}, HOff{}}

def app_start(+items: List<&2, Item>, +feed0: String, or_: Result<&1,&1, U32 & String, Pty>, +sess: SessSt) -> IO(Unit):
  match or_:
    case Fail{e}:
      App.run(~ShellSt, ~shell_app(), "Shell-OS", 1024, 1024,
              shell_state(10n, sess_sel_of(sess), items, Con{TTab{NoPty{}, term_dead()}, Nil{}}, 0, sess_tfocus_restore(sess), sess_vs_restore(sess, feed0), "", 0, 0, 0, 0, sess_profile_of(sess), feed0, sess_acc_restore(sess)))
    case Done{pty}:
      App.run(~ShellSt, ~shell_app(), "Shell-OS", 1024, 1024,
              shell_state(10n, sess_sel_of(sess), items, Con{TTab{YesPty{pty}, term_view_up(term_new(), sess_sbo_of(sess))}, Nil{}}, 0, sess_tfocus_restore(sess), sess_vs_restore(sess, feed0), "", 0, 0, 0, 0, sess_profile_of(sess), feed0, sess_acc_restore(sess)))

# Split the loaded session into (profile, session) so main's do-block
# uses each bound value exactly once (no affine double-use).
def sess_split_prof(+s: SessSt) -> (String & SessSt):
  (sess_profile_of(s), s)

def main_items(+prof: String, +sess: SessSt) -> IO(Unit):
  do IO<Unit>:
    items : List<&2, Item> <- load_items_file(profile_file(prof))
    feed0 : String <- load_feed_cache()
    or_ : Result<&1,&1, U32 & String, Pty> <- Pty.spawn()
    app_start(items, feed0, or_, sess)

def main_ps(ps: (String & SessSt)) -> IO(Unit):
  match ps:
    case (prof, sess): main_items(prof, sess)

def main() -> IO(Unit):
  do IO<Unit>:
    sess : SessSt <- load_session()
    main_ps(sess_split_prof(sess))
