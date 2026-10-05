// Pty read — takes U32 idx, looks up fd, non-blocking read.
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <stdint.h> // audit F13: INT32_MAX was implicitly provided
extern int pty_get_fd(int idx);
static void pty_read_call(IoWork* w) {
  int fd = pty_get_fd((int)w->hand);
  if (fd < 0) { w->size = io_sys_end(w, -9); return; }
  ssize_t n;
  // audit F11: retry on EINTR so a future signal handler can't turn a
  // transient interruption into a spurious Fail.
  do { n = read(fd, w->data, w->word); } while (n < 0 && errno == EINTR);
  if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) n = 0;
  w->size = io_sys_end(w, n);
}
static Term pty_read_pack(Env e, IoWork* w) {
  Term r = w->code ? io_fail(e, w->code, NULL) : io_done(e, io_str(e, w->data, w->size));
  free(w->data);
  return io_tup(e, io_hand(w->hand), r);
}
Term pty_read_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->word = f[1] < INT32_MAX ? f[1] : INT32_MAX;
  w->data = io_mem(malloc(w->word + 1));
  // audit F18: a NULL buffer would make read() fail EFAULT; degrade to a
  // clean ENOMEM Fail instead of relying on that path.
  if (!w->data) { w->code = 12; w->size = 0; return pty_read_pack(e, w); }
  return io_work(w, pty_read_call, pty_read_pack);
}
static void __attribute__((constructor)) pty_read_use(void) {
  io_eff(CID_PTY_READ_RAW, pty_read_run, 0);
}
