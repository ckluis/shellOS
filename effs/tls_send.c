// TLS send — takes U32 idx, looks up the SSL*, loops SSL_write until every
// byte is written. On WANT_READ/WANT_WRITE the poll loop parks us (io_wait_on)
// until the fd is ready again, so we never spin. Returns (idx, Done{Unit}).
// Structure mirrors sock_send.c; the SSL* table lives in tls_connect.c.
// Direct OpenSSL calls; linked via -lssl -lcrypto (see tls_connect.c).

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <poll.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <openssl/ssl.h>

extern SSL* tls_get_ssl(int idx);
extern int tls_get_fd(int idx);

// w->made carries the already-written byte offset across park/resume.
static Term tls_send_more(Env e, IoWork* w) {
  SSL* ssl = tls_get_ssl((int)w->hand);
  int fd = tls_get_fd((int)w->hand);
  if (!ssl || fd < 0)
    { free(w->data); return io_tup(e, io_hand(w->hand), io_fail(e, 9, "tls: bad handle")); }
  size_t off = (size_t)w->made;
  while (off < w->size) {
    size_t want = w->size - off;
    if (want > 16384) want = 16384; // one TLS record per call
    int n = SSL_write(ssl, (const char*)w->data + off, (int)want);
    if (n <= 0) {
      int se = SSL_get_error(ssl, n);
      if (se == SSL_ERROR_WANT_READ)
        { w->made = (intptr_t)off; return io_wait_on(w, fd, POLLIN, 0, tls_send_more); }
      if (se == SSL_ERROR_WANT_WRITE)
        { w->made = (intptr_t)off; return io_wait_on(w, fd, POLLOUT, 0, tls_send_more); }
      free(w->data);
      return io_tup(e, io_hand(w->hand), io_fail(e, EPROTO, "tls: write failed"));
    }
    off += (size_t)n;
  }
  free(w->data);
  return io_tup(e, io_hand(w->hand), io_done(e, term_pak(CID_UNIT, 0)));
}

Term tls_send_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->data = io_cstr(e, f[1], &w->size);
  w->made = 0;
  return tls_send_more(e, w);
}

static void __attribute__((constructor)) tls_send_use(void) {
  io_eff(CID_TLS_SEND_RAW, tls_send_run, 0);
}
