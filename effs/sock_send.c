// Socket send — takes U32 idx, looks up fd, loops send() until every byte is
// written or a real error occurs (partial sends happen on non-blocking
// sockets). On EAGAIN the poll loop parks us until the socket is writable
// again, so we never spin. Structure mirrors pty_write.c.
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdlib.h>
#include <poll.h>
#include <sys/types.h>
#include <sys/socket.h>

extern int sock_get_fd(int idx);

// w->made carries the already-written byte offset across park/resume.
static Term sock_send_more(Env e, IoWork* w) {
  int fd = sock_get_fd((int)w->hand);
  if (fd < 0) { free(w->data); return io_tup(e, io_hand(w->hand), io_fail(e, 9, NULL)); }
  size_t off = (size_t)w->made;
  while (off < w->size) {
    ssize_t n = send(fd, (const char*)w->data + off, w->size - off, 0);
    if (n < 0) {
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        w->made = (intptr_t)off;
        return io_wait_on(w, fd, POLLOUT, 0, sock_send_more);
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

Term sock_send_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->data = io_cstr(e, f[1], &w->size);
  w->made = 0;
  return sock_send_more(e, w);
}

static void __attribute__((constructor)) sock_send_use(void) {
  io_eff(CID_SOCK_SEND_RAW, sock_send_run, 0);
}
