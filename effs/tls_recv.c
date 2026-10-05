// TLS recv — takes U32 idx, looks up the SSL*, one SSL_read with poll timeout.
// Uses poll() with 50ms timeout on the underlying fd to avoid busy-spin;
// WANT_READ/WANT_WRITE (no data yet) returns Done{""}; clean shutdown (0)
// also returns Done{""}; the caller loops. Any real error -> Fail.
// Never parks the UI thread. Structure mirrors sock_recv.c;
// the SSL* table lives in tls_connect.c. Direct OpenSSL calls;
// linked via -lssl -lcrypto (see tls_connect.c).

#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <poll.h>
#include <openssl/ssl.h>

extern SSL* tls_get_ssl(int idx);
extern int tls_get_fd(int idx);

static void tls_recv_call(IoWork* w) {
  SSL* ssl = tls_get_ssl((int)w->hand);
  if (!ssl) { w->size = io_sys_end(w, -9); return; }
  // Wait up to 50ms for data to avoid busy-spin in the Bend poll loop.
  int fd = tls_get_fd((int)w->hand);
  if (fd >= 0) {
    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLIN;
    pfd.revents = 0;
    int pr;
    do { pr = poll(&pfd, 1, 50); } while (pr < 0 && errno == EINTR);
    if (pr <= 0) { w->size = io_sys_end(w, 0); return; }  // timeout: empty
  }
  int n = SSL_read(ssl, w->data, (int)w->word);
  if (n < 0) {
    int se = SSL_get_error(ssl, n);
    if (se == SSL_ERROR_WANT_READ || se == SSL_ERROR_WANT_WRITE) n = 0;
    else { w->size = io_sys_end(w, -EPROTO); return; }
  }
  w->size = io_sys_end(w, n);
}
static Term tls_recv_pack(Env e, IoWork* w) {
  Term r = w->code ? io_fail(e, w->code, "tls: read failed") : io_done(e, io_str(e, w->data, w->size));
  free(w->data);
  return io_tup(e, io_hand(w->hand), r);
}
Term tls_recv_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->word = f[1] < INT32_MAX ? f[1] : INT32_MAX;
  w->data = io_mem(malloc(w->word + 1));
  if (!w->data) { w->code = 12; w->size = 0; return tls_recv_pack(e, w); } // audit F18
  return io_work(w, tls_recv_call, tls_recv_pack);
}
static void __attribute__((constructor)) tls_recv_use(void) {
  io_eff(CID_TLS_RECV_RAW, tls_recv_run, 0);
}
