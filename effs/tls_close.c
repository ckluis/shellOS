// TLS close — takes U32 idx, best-effort SSL_shutdown, SSL_free,
// close(fd), free the table slot. Mirrors sock_close.c.

#include <openssl/ssl.h>

extern void tls_free_idx(int idx);

Term tls_close_run(Env e, Term* f, IoWork* w) {
  (void)e; (void)w;
  tls_free_idx((int)io_hand_v(f[0]));
  return term_pak(CID_UNIT, 0);
}

static void __attribute__((constructor)) tls_close_use(void) {
  io_eff(CID_TLS_CLOSE_RAW, tls_close_run, 0);
}
