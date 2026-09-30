# tls_proof_main.bend: real-TLS proof for the TLS bridge.
# Concatenated AFTER font.bend sock.bend reader.bend.
# (No `import Base`: font.bend already imports it; mid-file imports are a
# syntax error.)
#
# ENVIRONMENT NOTE (verified 2026-09-22): this sandbox transparently
# intercepts all outbound port-443 TCP (getpeername shows 198.19.0.1:3128,
# a raw ClientHello gets "wrong version number" — the interceptor expects
# an HTTP CONNECT). A raw-socket TLS client therefore cannot reach internet
# origins from here; that is a sandbox property, not a bridge limitation.
# The proof runs against a LOCAL TLS origin (127.0.0.1, not intercepted)
# with a REAL CA-issued chain: a test CA installed into the system bundle
# via update-ca-certificates, so the bridge's production verify path
# (SSL_CTX_set_default_verify_paths) is what gets exercised. PKI material
# lives in proofs/tls/.
#
# Proves:
#   1. POSITIVE: a real verified TLS handshake to localhost:18443
#      (peer cert subject/cipher/version printed from the C side via
#      Tls.peer_info), then the fetched RSS body runs through the existing
#      pure tokenizer -> extractor -> word-wrap pipeline.
#   2. NEGATIVE (fail-closed): a server presenting a cert for the WRONG
#      hostname (18444), an EXPIRED cert (18445), and a SELF-SIGNED cert
#      (18446) must ALL fail to connect. Any success is a security
#      violation and prints NEGATIVE-FAIL.

def take_lines(xs: List<&2, String>, n: Nat) -> List<&2, String>:
  match xs, n:
    case Nil{}, _: Nil{}
    case _, 0n: Nil{}
    case Con{x, rest}, 1n+m: Con{x, take_lines(rest, m)}

# All multi-use string math lives here, where + params are freely reusable
# (do-block pure binds consume their inputs affinely).
def proof_output(+stripped: String) -> String:
  String.append("BODY-CHARS=",
    String.append(Nat.show(String.length(stripped)),
      String.append(" TEXT-CHARS=",
        String.append(Nat.show(String.length(extract_text(tokenize(stripped)))),
          String.append("\n== first 12 wrapped lines ==\n",
            String.join(take_lines(word_wrap(extract_text(tokenize(stripped)), 60n), 12n), "\n"))))))

def fail_msg(e: U32 & String) -> String:
  match e:
    case (code, msg): String.append(U32.show(code), String.append(" ", msg))

def print_lines_take(+stripped: String) -> IO(Unit):
  do IO<Unit>:
    _a : Unit <- IO.print(proof_output(stripped))
    IO.print("(proof done)")

def pos_got(ts: Tls & String) -> IO(Unit):
  match ts:
    case (tls, body):
      do IO<Unit>:
        _u : Unit <- Tls.close(tls)
        stripped : String = http_strip_headers(body)
        _b : Unit <- IO.print("POSITIVE-OK")
        print_lines_take(stripped)

def pos_sent(sr: Tls & Result<&1,&1, U32 & String, Unit>) -> IO(Unit):
  match sr:
    case (tls, Fail{e}):
      do IO<Unit>:
        _u : Unit <- Tls.close(tls)
        IO.print(String.append("POSITIVE-FAIL send: ", fail_msg(e)))
    case (tls, Done{_}):
      do IO<Unit>:
        ts : Tls & String <- tls_recv_all(tls)
        pos_got(ts)

def pos_connected(+tls: Tls) -> IO(Unit):
  do IO<Unit>:
    info : String <- Tls.peer_info(tls)
    _a : Unit <- IO.print(String.append("PEER: ", info))
    sr : Tls & Result<&1,&1, U32 & String, Unit> <- Tls.send(tls, http_get_request("localhost", "/feed"))
    pos_sent(sr)

def pos_dispatch(cr: Result<&1,&1, U32 & String, Tls>) -> IO(Unit):
  match cr:
    case Fail{e}: IO.print(String.append("POSITIVE-FAIL connect: ", fail_msg(e)))
    case Done{tls}: pos_connected(tls)

def neg_report(name: String, r: Result<&1,&1, U32 & String, Tls>) -> IO(Unit):
  match r:
    case Fail{e}: IO.print(String.append(name, String.append(": NEGATIVE-OK (fail closed: ", String.append(fail_msg(e), ")"))))
    case Done{tls}:
      do IO<Unit>:
        _u : Unit <- Tls.close(tls)
        IO.print(String.append(name, ": NEGATIVE-FAIL (handshake must not succeed)"))

def neg3(port: U32, name: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1,&1, U32 & String, Tls> <- Tls.connect("localhost", port)
    _a : Unit <- neg_report(name, r)
    IO.print("== proof complete ==")

def neg2() -> IO(Unit):
  neg3(18446, "self-signed.localhost:18446")

def neg1() -> IO(Unit):
  do IO<Unit>:
    r : Result<&1,&1, U32 & String, Tls> <- Tls.connect("localhost", 18445)
    _a : Unit <- neg_report("expired.localhost:18445", r)
    neg2()

def neg0() -> IO(Unit):
  do IO<Unit>:
    r : Result<&1,&1, U32 & String, Tls> <- Tls.connect("localhost", 18444)
    _a : Unit <- neg_report("wrong-host.localhost:18444", r)
    neg1()

def main() -> IO(Unit):
  do IO<Unit>:
    _h : Unit <- IO.print("== TLS proof: positive ==")
    cr : Result<&1,&1, U32 & String, Tls> <- Tls.connect("localhost", 18443)
    _p : Unit <- pos_dispatch(cr)
    _n : Unit <- IO.print("== TLS proof: negative (must all fail closed) ==")
    neg0()
