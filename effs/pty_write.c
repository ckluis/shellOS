// Pty write — takes U32 idx, looks up fd, loops write() until every byte is
// written or a real error occurs. The master fd is O_NONBLOCK
// (pty_spawn.c), so a single write() may return a short count when the pty
// input queue fills; the old code mapped any n >= 0 to success and silently
// dropped the tail (audit F1). This mirrors sock_send.c: advance an offset,
// park via io_wait_on on EAGAIN so we never spin, and surface real errors
// as Fail. w->made carries the written offset across park/resume.
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdlib.h>
#include <poll.h>
extern int pty_get_fd(int idx);
static Term pty_write_more(Env e, IoWork* w) {
  int fd = pty_get_fd((int)w->hand);
  if (fd < 0) { free(w->data); return io_tup(e, io_hand(w->hand), io_fail(e, 9, NULL)); }
  size_t off = (size_t)w->made;
  while (off < w->size) {
    ssize_t n = write(fd, (const char*)w->data + off, w->size - off);
    if (n < 0) {
      if (errno == EINTR) continue;
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        w->made = (intptr_t)off;
        return io_wait_on(w, fd, POLLOUT, 0, pty_write_more);
      }
      free(w->data);
      return io_tup(e, io_hand(w->hand), io_fail(e, (u32)errno, NULL));
    }
    if (n == 0) break;
    off += (size_t)n;
  }
  free(w->data);
  return io_tup(e, io_hand(w->hand), io_done(e, term_pak(CID_UNIT, 0)));
}
Term pty_write_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->data = io_cstr(e, f[1], &w->size);
  w->made = 0;
  return pty_write_more(e, w);
}
static void __attribute__((constructor)) pty_write_use(void) {
  io_eff(CID_PTY_WRITE_RAW, pty_write_run, 0);
}
