// TLS peer info — takes U32 idx, returns a String describing the verified
// peer: "subject=<DN>|cipher=<name>|version=<TLSv1.3>". This is the proof
// surface that a real verified handshake happened (the connect effect
// itself returns only the handle). No peer certificate -> "" (bare IO(String)
// has no Fail channel; the C layer returns the raw String term).
// Direct OpenSSL calls; linked via -lssl -lcrypto (see tls_connect.c).

#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <openssl/ssl.h>

extern SSL* tls_get_ssl(int idx);

Term tls_peer_info_run(Env e, Term* f, IoWork* w) {
  (void)w;
  SSL* ssl = tls_get_ssl((int)io_hand_v(f[0]));
  if (!ssl) return io_str(e, "", 0);
  X509* cert = SSL_get_peer_certificate(ssl);
  // NOTE: this effect is declared `-> IO(String)` (bare String, not a
  // Result), so the C layer must return the raw String term — NOT
  // io_done/io_fail wrapped. (Bend delivers the effect's return term
  // directly to the continuation; io_done/io_fail correspond to the
  // Bend-level Result Done/Fail used by the other TLS effects.)
  // On error there is no Fail channel: return "" instead.
  if (!cert) return io_str(e, "", 0);
  char* subj = X509_NAME_oneline(X509_get_subject_name(cert), NULL, 0);
  const char* cipher = SSL_get_cipher_name(ssl);
  const char* ver = SSL_get_version(ssl);
  char buf[1024];
  snprintf(buf, sizeof(buf), "subject=%s|cipher=%s|version=%s",
           subj ? subj : "?", cipher ? cipher : "?", ver ? ver : "?");
  if (subj) OPENSSL_free(subj);
  X509_free(cert);
  return io_str(e, buf, strlen(buf));
}

static void __attribute__((constructor)) tls_peer_info_use(void) {
  io_eff(CID_TLS_PEER_INFO_RAW, tls_peer_info_run, 0);
}
