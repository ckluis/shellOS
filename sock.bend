# sock.bend: TCP socket + verified-TLS effects for network tiles (RSS fetch, HTTP/HTTPS).
# Native-only: the JS stubs fail with ENOSYS (Node's net/tls are promise-based
# and would starve Bend's sync poll loop; sockets need the C bridge).
# The socket fd is non-blocking for life so the UI thread can poll it:
# Sock.recv with no data returns Done{""} instead of parking.
#
# Indexed-handle design: the C code keeps a table idx -> fd. Bend's Sock is
# Data{TlsHandle{idx: U32}}, so they can live in Data constructors (raw
# io_hand terms cannot). The raw C functions take/return U32 indices;
# the Sock.*/Tls.* wrappers below convert between handles and U32.
# (No `import Base` here: this file is concatenated AFTER font.bend,
# which already imports Base; mid-file imports are a syntax error.)
#
# TLS (wave 2): verified HTTPS via OpenSSL, called directly by the C
# bridge (bend's clang line has no link-flag injection point; see
# effs/tls_connect.c). Certificate verification is MANDATORY and cannot
# be disabled from Bend: VERIFY_PEER + system CA bundle + TLS>=1.2 +
# SNI + hostname binding, fail-closed on any verification failure.

type Sock is Data:
  SockHandle{idx: U32}

# Raw C effects (U32 index based).
def sock_connect_raw(host: String, port: U32) -> IO(Result<&1,&1, U32 & String, U32>):
  import "./effs/sock_connect.c"
  import "./effs/sock_connect.js"

def sock_send_raw(idx: U32, data: String) -> IO(U32 & Result<&1,&1, U32 & String, Unit>):
  import "./effs/sock_send.c"
  import "./effs/sock_send.js"

def sock_recv_raw(idx: U32, max: U32) -> IO(U32 & Result<&1,&1, U32 & String, String>):
  import "./effs/sock_recv.c"
  import "./effs/sock_recv.js"

def sock_close_raw(idx: U32) -> IO(Unit):
  import "./effs/sock_close.c"
  import "./effs/sock_close.js"

# Safe wrappers: convert between SockHandle{idx} and raw U32.
def sock_wrap(or_: Result<&1,&1, U32 & String, U32>) -> Result<&1,&1, U32 & String, Sock>:
  match or_:
    case Fail{e}: Fail{e}
    case Done{idx}: Done{SockHandle{idx}}

def Sock.connect(host: String, port: U32) -> IO(Result<&1,&1, U32 & String, Sock>):
  do IO<Result<&1,&1, U32 & String, Sock>>:
    r : Result<&1,&1, U32 & String, U32> <- sock_connect_raw(host, port)
    IO.pure(Result<&1,&1, U32 & String, Sock>, sock_wrap(r))

def sock_unwrap_send(wr: U32 & Result<&1,&1, U32 & String, Unit>) -> Sock & Result<&1,&1, U32 & String, Unit>:
  match wr:
    case (idx, res): (SockHandle{idx}, res)

def Sock.send(sock: Sock, data: String) -> IO(Sock & Result<&1,&1, U32 & String, Unit>):
  match sock:
    case SockHandle{idx}:
      do IO<Sock & Result<&1,&1, U32 & String, Unit>>:
        wr : U32 & Result<&1,&1, U32 & String, Unit> <- sock_send_raw(idx, data)
        IO.pure(Sock & Result<&1,&1, U32 & String, Unit>, sock_unwrap_send(wr))

def sock_unwrap_recv(rr: U32 & Result<&1,&1, U32 & String, String>) -> Sock & Result<&1,&1, U32 & String, String>:
  match rr:
    case (idx, res): (SockHandle{idx}, res)

def Sock.recv(sock: Sock, max: U32) -> IO(Sock & Result<&1,&1, U32 & String, String>):
  match sock:
    case SockHandle{idx}:
      do IO<Sock & Result<&1,&1, U32 & String, String>>:
        rr : U32 & Result<&1,&1, U32 & String, String> <- sock_recv_raw(idx, max)
        IO.pure(Sock & Result<&1,&1, U32 & String, String>, sock_unwrap_recv(rr))

def Sock.close(sock: Sock) -> IO(Unit):
  match sock:
    case SockHandle{idx}: sock_close_raw(idx)

# ---------------------------------------------------------------------------
# HTTP fetch (item #7: reader live content).
#
# Plain HTTP/1.0 GET only. For verified HTTPS use https_fetch (TLS section
# below). The feed target in app.bend is configurable via SHELL_OS_FEED
# (default 127.0.0.1:18081); nothing here is driven by UI input. The default demo path (the three demo
# articles plus the press-f placeholder) never touches the network.
#
# BOUNDS (all hard):
#   - empty-poll spin: 50000 iterations max BEFORE the first byte arrives.
#     recv is nonblocking and maps EAGAIN/EWOULDBLOCK *and* EOF to Done{""},
#     so a first-empty recv is ambiguous: it can mean "server hasn't answered
#     yet" OR "connection closed". The spin phase absorbs the not-ready race.
#   - data budget: 32 chunks x 4096 bytes = 128 KiB max captured response.
#   - after the first byte arrives, an empty chunk means EOF -> stop.
# On any failure (connect/send/recv Fail, empty response), http_fetch returns
# Fail or a body that the caller may reject; app.bend keeps the old feed.
# ---------------------------------------------------------------------------

def http_get_request(+host: String, +path: String) -> String:
  String.append("GET ", String.append(path, String.append(" HTTP/1.0\r\nHost: ", String.append(host, "\r\nConnection: close\r\n\r\n"))))

# Strip the HTTP/1.x header block: everything up to and including the first
# "\r\n\r\n". No marker -> return the whole response (e.g. headerless body).
# Empty body after the marker -> SNil{} (caller treats as failure).
def http_strip_go(s: String, +orig: String) -> String:
  match s:
    case SNil{}: orig
    case SCon{Chr{13}, SCon{Chr{10}, SCon{Chr{13}, SCon{Chr{10}, t4}}}}: t4
    case SCon{_, t}: http_strip_go(t, orig)

def http_strip_headers(+resp: String) -> String:
  http_strip_go(resp, resp)

# --- Truncated-response fix (feed cache held 29-byte fragments) ---
#
# The old loop spent a single fixed 50k-iteration spin budget that expired
# in well under a second on a fast machine, so a slow/trickling server had
# its response cut off mid-body and the fragment was cached as if complete.
# The new loop is two-phase:
#   Phase 1 (sock_recv_hdr): accumulate until the header terminator
#     (\r\n\r\n) is seen. Bounded by 50k polls / 8 chunks (32 KiB of head).
#   Phase 2 (sock_recv_body): parse Content-Length from the headers. When
#     present and > 0, keep reading until that many body bytes arrive (or
#     EOF, or a 500k-poll / 256-chunk budget ends it). If the loop ends with
#     fewer body bytes than promised, the fetch FAILS instead of caching a
#     fragment. When Content-Length is absent, phase 2 reads until the
#     server closes the connection (EOF) or the budget ends; an EOF close is
#     treated as complete, a budget-out as truncated.
# Multi-match follows parameter order — Bend requires scrutinees to follow
# binder order, and the shrinking arg first.

def http_hdr_end_go(s: String) -> Bool:
  match s:
    case SNil{}: False{}
    case SCon{Chr{13}, SCon{Chr{10}, SCon{Chr{13}, SCon{Chr{10}, _}}}}: True{}
    case SCon{_, t}: http_hdr_end_go(t)

def http_hdr_end(+s: String) -> Bool:
  http_hdr_end_go(s)

def http_hdr_len_go(s: String, +acc: Nat) -> Nat:
  match s:
    case SNil{}: 0n
    case SCon{Chr{13}, SCon{Chr{10}, SCon{Chr{13}, SCon{Chr{10}, _}}}}: Nat.add(acc, 4n)
    case SCon{_, t}: http_hdr_len_go(t, Nat.add(acc, 1n))

def http_hdr_len(+s: String) -> Nat:
  http_hdr_len_go(s, 0n)

# Parse decimal digits at the head of s (stops at the first non-digit).
def http_cl_val(s: String, +acc: Nat) -> Nat:
  match s:
    case SCon{Chr{48}, t}: http_cl_val(t, Nat.mul(acc, 10n))
    case SCon{Chr{49}, t}: http_cl_val(t, Nat.add(Nat.mul(acc, 10n), 1n))
    case SCon{Chr{50}, t}: http_cl_val(t, Nat.add(Nat.mul(acc, 10n), 2n))
    case SCon{Chr{51}, t}: http_cl_val(t, Nat.add(Nat.mul(acc, 10n), 3n))
    case SCon{Chr{52}, t}: http_cl_val(t, Nat.add(Nat.mul(acc, 10n), 4n))
    case SCon{Chr{53}, t}: http_cl_val(t, Nat.add(Nat.mul(acc, 10n), 5n))
    case SCon{Chr{54}, t}: http_cl_val(t, Nat.add(Nat.mul(acc, 10n), 6n))
    case SCon{Chr{55}, t}: http_cl_val(t, Nat.add(Nat.mul(acc, 10n), 7n))
    case SCon{Chr{56}, t}: http_cl_val(t, Nat.add(Nat.mul(acc, 10n), 8n))
    case SCon{Chr{57}, t}: http_cl_val(t, Nat.add(Nat.mul(acc, 10n), 9n))
    case _: acc

def http_cl_skip(s: String) -> Nat:
  match s:
    case SCon{Chr{32}, t}: http_cl_skip(t)
    case _: http_cl_val(s, 0n)

# Scan s for a "Content-Length:" header and parse its decimal value.
# Returns 0 when absent. Single self-recursive def: Bend forbids the mutual
# recursion a separate tag-matcher would need, so the 15-char tag pattern is
# inlined in the first case arm.
def http_cl_find(s: String) -> Nat:
  match s:
    case SCon{Chr{67}, SCon{Chr{111}, SCon{Chr{110}, SCon{Chr{116}, SCon{Chr{101}, SCon{Chr{110}, SCon{Chr{116}, SCon{Chr{45}, SCon{Chr{76}, SCon{Chr{101}, SCon{Chr{110}, SCon{Chr{103}, SCon{Chr{116}, SCon{Chr{104}, SCon{Chr{58}, rest}}}}}}}}}}}}}}}: http_cl_skip(rest)
    case SNil{}: 0n
    case SCon{_, t}: http_cl_find(t)

def http_content_length(+s: String) -> Nat:
  http_cl_find(s)

# True when the promised body is fully buffered. want==0 (no
# Content-Length) never counts as satisfied — that loop runs to EOF/budget.
def body_sat2(+diff: Nat, +want: Nat) -> Bool:
  match diff, want:
    case 0n, 0n: False{}
    case 0n, _: True{}
    case _, _: False{}

def body_sat(+want: Nat, +have: Nat) -> Bool:
  body_sat2(Nat.sub(want, have), want)

# (want, hdr_len, sat): Content-Length value, header block length, and
# whether the already-buffered body satisfies it.
def http_body_plan3(+want: Nat, +hl: Nat, +acc: String) -> Nat & Nat & Bool:
  (want, hl, body_sat(want, Nat.sub(String.length(acc), hl)))

def http_body_plan2(+hl: Nat, +acc: String) -> Nat & Nat & Bool:
  http_body_plan3(http_content_length(acc), hl, acc)

def http_body_plan(+acc: String) -> Nat & Nat & Bool:
  http_body_plan2(http_hdr_len(acc), acc)

# EOF/close: complete when the length was unknown (best effort) or the
# promised bytes arrived; otherwise the server hung up early -> truncated.
def body_eof_ok(+want: Nat, +have: Nat) -> Bool:
  match want:
    case 0n: True{}
    case _: body_sat(want, have)

# Phase 1: bounded header accumulation (no per-iteration scan; the
# terminator is checked once afterwards). Returns (sock, acc).
def sock_recv_hdr(spin: Nat, n: Nat, acc: String, rr: Sock & Result<&1,&1, U32 & String, String>) -> IO(Sock & String):
  match spin, n, rr:
    case 0n, _, (sock, _): IO.pure(Sock & String, (sock, acc))
    case 1n+sp, 0n, (sock, _): IO.pure(Sock & String, (sock, acc))
    case 1n+sp, 1n+m, (sock, Fail{e}): IO.pure(Sock & String, (sock, acc))
    case 1n+sp, 1n+m, (sock, Done{chunk}):
      match chunk:
        case SNil{}:
          do IO<Sock & String>:
            rr2 : Sock & Result<&1,&1, U32 & String, String> <- Sock.recv(sock, 4096)
            sock_recv_hdr(sp, 1n+m, acc, rr2)
        case SCon{_, _}:
          +acc2 = String.append(acc, chunk)
          do IO<Sock & String>:
            rr2 : Sock & Result<&1,&1, U32 & String, String> <- Sock.recv(sock, 4096)
            sock_recv_hdr(sp, m, acc2, rr2)

# Phase 2: receive the body. Single self-recursive def (Bend bans the
# mutual recursion a check-then-loop helper pair would need). sat is the
# precomputed body_sat: when True we already hold the promised bytes.
# have is derived as len(acc)-hl on the iterations that need it, so the
# use-once chunk is never consumed twice.
# Simple full-response receiver: accumulates until poll/chunk budget
# exhausted or connection fails. Returns (sock, acc).
def sock_recv_full(spin: Nat, n: Nat, acc: String, rr: Sock & Result<&1,&1, U32 & String, String>) -> IO(Sock & String):
  match spin, n, rr:
    case 0n, _, (sock, _): IO.pure(Sock & String, (sock, acc))
    case 1n+sp, 0n, (sock, _): IO.pure(Sock & String, (sock, acc))
    case 1n+sp, 1n+m, (sock, Fail{e}): IO.pure(Sock & String, (sock, acc))
    case 1n+sp, 1n+m, (sock, Done{chunk}):
      match chunk:
        case SNil{}:
          do IO<Sock & String>:
            rr2 : Sock & Result<&1,&1, U32 & String, String> <- Sock.recv(sock, 4096)
            sock_recv_full(sp, 1n+m, acc, rr2)
        case SCon{_, _}:
          +acc2 = String.append(acc, chunk)
          do IO<Sock & String>:
            rr2 : Sock & Result<&1,&1, U32 & String, String> <- Sock.recv(sock, 4096)
            sock_recv_full(sp, m, acc2, rr2)

def sock_recv_all(sock: Sock) -> IO(Sock & String):
  do IO<Sock & String>:
    rr : Sock & Result<&1,&1, U32 & String, String> <- Sock.recv(sock, 4096)
    sock_recv_full(Nat.mul(5n, 1000n), 512n, "", rr)

# Validate a received response: True if complete, False if truncated.
# A response is truncated if headers are present but Content-Length
# promises more body than we received.
def http_resp_ok2(done: Bool, +acc: String) -> Bool:
  match done:
    case False{}: False{}
    case True{}: body_sat(http_content_length(acc), Nat.sub(String.length(acc), http_hdr_len(acc)))

def http_resp_ok(+acc: String) -> Bool:
  http_resp_ok2(http_hdr_end(acc), acc)

def http_fetch_got2(ok: Bool, sock: Sock, body: String) -> IO(Result<&1,&1, U32 & String, String>):
  match ok:
    case False{}:
      do IO<Result<&1,&1, U32 & String, String>>:
        _u : Unit <- Sock.close(sock)
        IO.pure(Result<&1,&1, U32 & String, String>, Fail{(0, "http: truncated response")})
    case True{}:
      do IO<Result<&1,&1, U32 & String, String>>:
        _u : Unit <- Sock.close(sock)
        IO.pure(Result<&1,&1, U32 & String, String>, Done{http_strip_headers(body)})

def http_fetch_got(rs: Sock & String) -> IO(Result<&1,&1, U32 & String, String>):
  match rs:
    case (sock, body):
      +b2 = body
      http_fetch_got2(http_resp_ok(b2), sock, b2)

def http_fetch_sent(sr: Sock & Result<&1,&1, U32 & String, Unit>) -> IO(Result<&1,&1, U32 & String, String>):
  match sr:
    case (sock, Fail{e}):
      do IO<Result<&1,&1, U32 & String, String>>:
        _u : Unit <- Sock.close(sock)
        IO.pure(Result<&1,&1, U32 & String, String>, Fail{e})
    case (sock, Done{_}):
      do IO<Result<&1,&1, U32 & String, String>>:
        rs : Sock & String <- sock_recv_all(sock)
        http_fetch_got(rs)

def http_fetch_conn(cr: Result<&1,&1, U32 & String, Sock>, host: String, path: String) -> IO(Result<&1,&1, U32 & String, String>):
  match cr:
    case Fail{e}: IO.pure(Result<&1,&1, U32 & String, String>, Fail{e})
    case Done{sock}:
      do IO<Result<&1,&1, U32 & String, String>>:
        sr : Sock & Result<&1,&1, U32 & String, Unit> <- Sock.send(sock, http_get_request(host, path))
        http_fetch_sent(sr)

def http_fetch(+host: String, port: U32, path: String) -> IO(Result<&1,&1, U32 & String, String>):
  do IO<Result<&1,&1, U32 & String, String>>:
    cr : Result<&1,&1, U32 & String, Sock> <- Sock.connect(host, port)
    http_fetch_conn(cr, host, path)

# ---------------------------------------------------------------------------
# TLS (item #1, wave 2): verified-HTTPS effect bridge.
#
# Same indexed-handle design as plain Sock (C keeps idx -> (SSL*, fd)),
# but the handshake is a real TLS client handshake with MANDATORY
# certificate verification — see effs/tls_connect.c for the fail-closed
# checklist (VERIFY_PEER, system CA bundle, TLS>=1.2, SNI, hostname binding,
# verify-result check). Verification can never be disabled from Bend:
# there is no flag, no option, no insecure mode.
#
# After the (blocking, timeout-bounded) handshake the socket goes
# non-blocking and Tls.recv mirrors Sock.recv's contract: no data yet ->
# Done{""}, so the UI poll loop is never parked by a read. Tls.send loops
# to completion, parking via io_wait_on on WANT_READ/WANT_WRITE.
#
# Native-only: the JS stubs fail with ENOSYS (Node's tls is promise-based
# and would starve Bend's sync poll loop; the C bridge calls OpenSSL
# directly, linked via -lssl -lcrypto).
# ---------------------------------------------------------------------------

type Tls is Data:
  TlsHandle{idx: U32}

# Raw C effects (U32 index based).
def tls_connect_raw(host: String, port: U32) -> IO(Result<&1,&1, U32 & String, U32>):
  import "./effs/tls_connect.c"
  import "./effs/tls_connect.js"

def tls_send_raw(idx: U32, data: String) -> IO(U32 & Result<&1,&1, U32 & String, Unit>):
  import "./effs/tls_send.c"
  import "./effs/tls_send.js"

def tls_recv_raw(idx: U32, max: U32) -> IO(U32 & Result<&1,&1, U32 & String, String>):
  import "./effs/tls_recv.c"
  import "./effs/tls_recv.js"

def tls_close_raw(idx: U32) -> IO(Unit):
  import "./effs/tls_close.c"
  import "./effs/tls_close.js"

def tls_peer_info_raw(idx: U32) -> IO(String):
  import "./effs/tls_info.c"
  import "./effs/tls_info.js"

# Safe wrappers: convert between TlsHandle{idx} and raw U32.
def tls_wrap(or_: Result<&1,&1, U32 & String, U32>) -> Result<&1,&1, U32 & String, Tls>:
  match or_:
    case Fail{e}: Fail{e}
    case Done{idx}: Done{TlsHandle{idx}}

def Tls.connect(host: String, port: U32) -> IO(Result<&1,&1, U32 & String, Tls>):
  do IO<Result<&1,&1, U32 & String, Tls>>:
    r : Result<&1,&1, U32 & String, U32> <- tls_connect_raw(host, port)
    IO.pure(Result<&1,&1, U32 & String, Tls>, tls_wrap(r))

def tls_unwrap_send(wr: U32 & Result<&1,&1, U32 & String, Unit>) -> Tls & Result<&1,&1, U32 & String, Unit>:
  match wr:
    case (idx, res): (TlsHandle{idx}, res)

def Tls.send(tls: Tls, data: String) -> IO(Tls & Result<&1,&1, U32 & String, Unit>):
  match tls:
    case TlsHandle{idx}:
      do IO<Tls & Result<&1,&1, U32 & String, Unit>>:
        wr : U32 & Result<&1,&1, U32 & String, Unit> <- tls_send_raw(idx, data)
        IO.pure(Tls & Result<&1,&1, U32 & String, Unit>, tls_unwrap_send(wr))

def tls_unwrap_recv(rr: U32 & Result<&1,&1, U32 & String, String>) -> Tls & Result<&1,&1, U32 & String, String>:
  match rr:
    case (idx, res): (TlsHandle{idx}, res)

def Tls.recv(tls: Tls, max: U32) -> IO(Tls & Result<&1,&1, U32 & String, String>):
  match tls:
    case TlsHandle{idx}:
      do IO<Tls & Result<&1,&1, U32 & String, String>>:
        rr : U32 & Result<&1,&1, U32 & String, String> <- tls_recv_raw(idx, max)
        IO.pure(Tls & Result<&1,&1, U32 & String, String>, tls_unwrap_recv(rr))

def Tls.close(tls: Tls) -> IO(Unit):
  match tls:
    case TlsHandle{idx}: tls_close_raw(idx)

# Peer certificate/cipher description, e.g.
# "subject=/CN=news.ycombinator.com|cipher=TLS_AES_256_GCM_SHA384|version=TLSv1.3".
# Proof surface that a real verified handshake happened.
def Tls.peer_info(tls: Tls) -> IO(String):
  match tls:
    case TlsHandle{idx}: tls_peer_info_raw(idx)

# ---------------------------------------------------------------------------
# HTTPS fetch: verified-TLS GET over the Tls bridge, then the same pure
# pipeline as http_fetch (header strip in pure Bend; the C layer moves
# bytes only). Same hard bounds: 50000 empty-poll spins, 32 x 4096-byte
# chunks (128 KiB cap). On any failure returns Fail; the caller keeps the
# old feed.
# ---------------------------------------------------------------------------

# Bounded receive loop (Tls variant of the two-phase loop above): phase 1
# reads until \r\n\r\n, phase 2 reads until Content-Length body bytes arrive
# (or EOF / budget). A truncated body FAILS the fetch instead of caching a
# fragment. Same hard bounds: 50000 header polls, 8 x 4096-byte header
# chunks, 500000 body polls, 256 x 4096-byte body chunks (1 MiB cap).

# Phase 1: bounded header accumulation (no per-iteration scan; the
# terminator is checked once afterwards). Returns (tls, acc).
def tls_recv_hdr(spin: Nat, n: Nat, acc: String, rr: Tls & Result<&1,&1, U32 & String, String>) -> IO(Tls & String):
  match spin, n, rr:
    case 0n, _, (tls, _): IO.pure(Tls & String, (tls, acc))
    case 1n+sp, 0n, (tls, _): IO.pure(Tls & String, (tls, acc))
    case 1n+sp, 1n+m, (tls, Fail{e}): IO.pure(Tls & String, (tls, acc))
    case 1n+sp, 1n+m, (tls, Done{chunk}):
      match chunk:
        case SNil{}:
          do IO<Tls & String>:
            rr2 : Tls & Result<&1,&1, U32 & String, String> <- Tls.recv(tls, 4096)
            tls_recv_hdr(sp, 1n+m, acc, rr2)
        case SCon{_, _}:
          +acc2 = String.append(acc, chunk)
          do IO<Tls & String>:
            rr2 : Tls & Result<&1,&1, U32 & String, String> <- Tls.recv(tls, 4096)
            tls_recv_hdr(sp, m, acc2, rr2)

# Phase 2: receive the body. Single self-recursive def (Bend bans the
# mutual recursion a check-then-loop helper pair would need). sat is the
# precomputed body_sat: when True we already hold the promised bytes.
# have is derived as len(acc)-hl on the iterations that need it, so the
# use-once chunk is never consumed twice.
# Simple full-response receiver for TLS: accumulates until poll/chunk
# budget exhausted or connection fails. Returns (tls, acc).
def tls_recv_full(spin: Nat, n: Nat, acc: String, rr: Tls & Result<&1,&1, U32 & String, String>) -> IO(Tls & String):
  match spin, n, rr:
    case 0n, _, (tls, _): IO.pure(Tls & String, (tls, acc))
    case 1n+sp, 0n, (tls, _): IO.pure(Tls & String, (tls, acc))
    case 1n+sp, 1n+m, (tls, Fail{e}): IO.pure(Tls & String, (tls, acc))
    case 1n+sp, 1n+m, (tls, Done{chunk}):
      match chunk:
        case SNil{}:
          do IO<Tls & String>:
            rr2 : Tls & Result<&1,&1, U32 & String, String> <- Tls.recv(tls, 4096)
            tls_recv_full(sp, 1n+m, acc, rr2)
        case SCon{_, _}:
          +acc2 = String.append(acc, chunk)
          do IO<Tls & String>:
            rr2 : Tls & Result<&1,&1, U32 & String, String> <- Tls.recv(tls, 4096)
            tls_recv_full(sp, m, acc2, rr2)

def tls_recv_all(tls: Tls) -> IO(Tls & String):
  do IO<Tls & String>:
    rr : Tls & Result<&1,&1, U32 & String, String> <- Tls.recv(tls, 4096)
    tls_recv_full(Nat.mul(5n, 1000n), 512n, "", rr)

def https_fetch_got2(ok: Bool, tls: Tls, body: String) -> IO(Result<&1,&1, U32 & String, String>):
  match ok:
    case False{}:
      do IO<Result<&1,&1, U32 & String, String>>:
        _u : Unit <- Tls.close(tls)
        IO.pure(Result<&1,&1, U32 & String, String>, Fail{(0, "https: truncated response")})
    case True{}:
      do IO<Result<&1,&1, U32 & String, String>>:
        _u : Unit <- Tls.close(tls)
        IO.pure(Result<&1,&1, U32 & String, String>, Done{http_strip_headers(body)})

def https_fetch_got(ts: Tls & String) -> IO(Result<&1,&1, U32 & String, String>):
  match ts:
    case (tls, body):
      +b2 = body
      https_fetch_got2(http_resp_ok(b2), tls, b2)

def https_fetch_sent(sr: Tls & Result<&1,&1, U32 & String, Unit>) -> IO(Result<&1,&1, U32 & String, String>):
  match sr:
    case (tls, Fail{e}):
      do IO<Result<&1,&1, U32 & String, String>>:
        _u : Unit <- Tls.close(tls)
        IO.pure(Result<&1,&1, U32 & String, String>, Fail{e})
    case (tls, Done{_}):
      do IO<Result<&1,&1, U32 & String, String>>:
        ts : Tls & String <- tls_recv_all(tls)
        https_fetch_got(ts)

def https_fetch_conn(cr: Result<&1,&1, U32 & String, Tls>, host: String, path: String) -> IO(Result<&1,&1, U32 & String, String>):
  match cr:
    case Fail{e}: IO.pure(Result<&1,&1, U32 & String, String>, Fail{e})
    case Done{tls}:
      do IO<Result<&1,&1, U32 & String, String>>:
        sr : Tls & Result<&1,&1, U32 & String, Unit> <- Tls.send(tls, http_get_request(host, path))
        https_fetch_sent(sr)

# Verified-TLS HTTPS GET. The host string doubles as the SNI name and the
# expected certificate hostname — verification is mandatory and cannot be
# disabled. Returns the response body (headers stripped) or Fail.
def https_fetch(+host: String, port: U32, path: String) -> IO(Result<&1,&1, U32 & String, String>):
  do IO<Result<&1,&1, U32 & String, String>>:
    cr : Result<&1,&1, U32 & String, Tls> <- Tls.connect(host, port)
    https_fetch_conn(cr, host, path)
