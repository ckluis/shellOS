# reader.bend: HTML-subset tokenizer and text extraction in pure Bend.
# Tokenizes <p>, <h1>, <a>, text. Extracts text density. Word wrap.

type Tok is Data:
  TOpen{tag: String}
  TClose{tag: String}
  TText{text: String}

# Simple tokenizer: single self-recursive function with an in_tag mode flag.
# (A multi-function tok_go/tok_tag/tok_text split would be banned mutual recursion.)
def close_or_open2(+buf: String, is_close: Bool) -> Tok:
  match is_close:
    case True{}: TClose{String.drop(buf, 1n)}
    case False{}: TOpen{buf}

def close_or_open(+buf: String) -> Tok:
  close_or_open2(buf, String.starts_with(buf, "/"))

def rev_tok(xs: List<&2, Tok>, acc: List<&2, Tok>) -> List<&2, Tok>:
  match xs:
    case Nil{}: acc
    case h <> t: rev_tok(t, Con{h, acc})

# str_rev: reverse a String in O(n). The tokenizer and wrapper below accumulate
# the current buffer REVERSED via O(1) prepends (String.append is O(len) in its
# FIRST argument, so appending one char at a time is quadratic); str_rev flips
# the buffer back to forward order once, at token/line boundaries.
def str_rev_go(s: String, +acc: String) -> String:
  match s:
    case SNil{}: acc
    case SCon{Chr{c}, t}: str_rev_go(t, String.append(Char.show(Chr{c}), acc))

def str_rev(+s: String) -> String:
  str_rev_go(s, "")

def rev_str(xs: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t: rev_str(t, Con{h, acc})

def tok_text_end(+buf_rev: String, acc: List<&2, Tok>, empty: Bool) -> List<&2, Tok>:
  match empty:
    case True{}: rev_tok(acc, Nil{})
    case False{}: rev_tok(Con{TText{str_rev(buf_rev)}, acc}, Nil{})

def tok_end(acc: List<&2, Tok>, in_tag: Bool, +buf_rev: String) -> List<&2, Tok>:
  match in_tag:
    case True{}: rev_tok(acc, Nil{})  # unterminated tag: drop
    case False{}: tok_text_end(buf_rev, acc, String.eq(buf_rev, ""))

def tok_go(s: String, acc: List<&2, Tok>, +in_tag: Bool, +buf_rev: String) -> List<&2, Tok>:
  match s:
    case SNil{}: tok_end(acc, in_tag, buf_rev)
    case SCon{Chr{c}, t}:
      match c:
        case 60:  # '<'
          match in_tag:
            case True{}: tok_go(t, acc, True{}, String.append("<", buf_rev))
            case False{}: tok_go(t, Con{TText{str_rev(buf_rev)}, acc}, True{}, "")
        case 62:  # '>'
          match in_tag:
            case True{}: tok_go(t, Con{close_or_open(str_rev(buf_rev)), acc}, False{}, "")
            case False{}: tok_go(t, acc, False{}, String.append(">", buf_rev))
        case _:
          tok_go(t, acc, in_tag, String.append(Char.show(Chr{c}), buf_rev))

def tokenize(s: String) -> List<&2, Tok>:
  tok_go(s, Nil{}, False{}, "")

# Extract text from tokens (concatenate TText).
# Adjacent TText tokens come from separate elements (e.g. </h1><p>), so one
# space separates them; without this, "Shell-OS" + "A pure…" fused into
# "Shell-OSA pure…" in the proof render.
# Linear-time version: collect the TText strings into a reversed list (O(1)
# cons per token), drop leading empties (matches the old String.eq(acc,"")
# gate), then join right-to-left so each character is copied exactly once.
# Byte-identical output to the old quadratic ext_go, verified by probe diff.
def ext_collect(toks: List<&2, Tok>, +acc: List<&2, String>) -> List<&2, String>:
  match toks:
    case Nil{}: acc
    case h <> t:
      match h:
        case TText{text}: ext_collect(t, Con{text, acc})
        case _: ext_collect(t, acc)

def ext_drop_lead(+xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case h <> t:
      match h:
        case SNil{}: ext_drop_lead(t)
        case SCon{_, _}: Con{h, t}

def ext_join(+xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case h <> t:
      match t:
        case Nil{}: h
        case _ <> _: String.append(h, String.append(" ", ext_join(t)))

def extract_text(toks: List<&2, Tok>) -> String:
  ext_join(ext_drop_lead(rev_str(ext_collect(toks, Nil{}), Nil{})))

# Word wrap: break text into lines of max width (in chars).
# (rev_str moved above; used by both extract_text and wrap_go.)
#
# cur is accumulated REVERSED (O(1) prepend per char); str_rev flips it once
# when a line is emitted. cur_len tracks the line length, word_len tracks the
# current word length (since last space) — both avoid O(n) String.length calls.
#
# Hard-break policy: a line may exceed width to complete a word (preserving
# ordinary article output), but an uninterrupted word is HARD-BROKEN at width
# (bounded lines for pathological inputs like 200KB uninterrupted runs).
#
# Single recursive def (no mutual recursion): `full` (cur_len >= width) and
# `word_full` (word_len >= width) are Bool parameters so arms can match on them.

def wrap_go(s: String, +width: Nat, +cur_rev: String, +cur_len: Nat, +word_len: Nat, acc: List<&2, String>, full: Bool, word_full: Bool) -> List<&2, String>:
  match s:
    case SNil{}:
      rev_str(Con{str_rev(cur_rev), acc}, Nil{})
    case SCon{Chr{c}, t}:
      match c:
        case 32:  # space
          match full:
            case True{}:
              # line is full: emit it, reset (space consumed as the break)
              wrap_go(t, width, "", 0n, 0n, Con{str_rev(cur_rev), acc}, False{}, False{})
            case False{}:
              # append space, continue; word resets
              wrap_go(t, width, String.append(" ", cur_rev), Nat.add(cur_len, 1n), 0n, acc, Nat.is_ge(Nat.add(cur_len, 1n), width), False{})
        case _:
          match full:
            case True{}:
              match word_full:
                case True{}:
                  # Hard break: the word itself exceeds width; emit line, start new word
                  wrap_go(t, width, Char.show(Chr{c}), 1n, 1n, Con{str_rev(cur_rev), acc}, Nat.is_ge(1n, width), Nat.is_ge(1n, width))
                case False{}:
                  # Line full but word not: allow overshoot to complete the word
                  wrap_go(t, width, String.append(Char.show(Chr{c}), cur_rev), Nat.add(cur_len, 1n), Nat.add(word_len, 1n), acc, True{}, Nat.is_ge(Nat.add(word_len, 1n), width))
            case False{}:
              wrap_go(t, width, String.append(Char.show(Chr{c}), cur_rev), Nat.add(cur_len, 1n), Nat.add(word_len, 1n), acc, Nat.is_ge(Nat.add(cur_len, 1n), width), Nat.is_ge(Nat.add(word_len, 1n), width))

def word_wrap_go(s: String, +width: Nat, positive: Bool) -> List<&2, String>:
  match positive:
    case True{}: wrap_go(s, width, "", 0n, 0n, Nil{}, False{}, False{})
    case False{}: wrap_go(s, 1n, "", 0n, 0n, Nil{}, False{}, False{})

def word_wrap(s: String, +width: Nat) -> List<&2, String>:
  # Guard: width 0 would loop forever; treat as width 1.
  word_wrap_go(s, width, Nat.is_gt(width, 0n))
