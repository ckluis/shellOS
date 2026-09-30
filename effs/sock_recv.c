// Socket recv — takes U32 idx, looks up fd, recv with poll timeout.
// Uses poll() with 50ms timeout to avoid busy-spin; empty/timeout/EOF
// returns Done{""}; the caller loops. Never parks the UI thread.
// Structure mirrors pty_read.c.
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <poll.h>

extern int sock_get_fd(int idx);

static void sock_recv_call(IoWork* w) {
  int fd = sock_get_fd((int)w->hand);
  if (fd < 0) { w->size = io_sys_end(w, -9); return; }
  // Wait up to 50ms for data to avoid busy-spin in the Bend poll loop.
  // This keeps the UI responsive while preventing 1M+ polls/sec.
  struct pollfd pfd;
  pfd.fd = fd;
  pfd.events = POLLIN;
  pfd.revents = 0;
  int pr;
  do { pr = poll(&pfd, 1, 50); } while (pr < 0 && errno == EINTR);
  if (pr <= 0) { w->size = io_sys_end(w, 0); return; }  // timeout or error: empty
  ssize_t n;
  do { n = recv(fd, w->data, w->word, 0); } while (n < 0 && errno == EINTR); // audit F11
  if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) n = 0;
  w->size = io_sys_end(w, n);
}
static Term sock_recv_pack(Env e, IoWork* w) {
  Term r = w->code ? io_fail(e, w->code, NULL) : io_done(e, io_str(e, w->data, w->size));
  free(w->data);
  return io_tup(e, io_hand(w->hand), r);
}
Term sock_recv_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->word = f[1] < INT32_MAX ? f[1] : INT32_MAX;
  w->data = io_mem(malloc(w->word + 1));
  if (!w->data) { w->code = 12; w->size = 0; return sock_recv_pack(e, w); } // audit F18
  return io_work(w, sock_recv_call, sock_recv_pack);
}
static void __attribute__((constructor)) sock_recv_use(void) {
  io_eff(CID_SOCK_RECV_RAW, sock_recv_run, 0);
}
