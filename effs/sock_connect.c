// Socket connect — resolves host, non-blocking connect, returns a U32 index
// into a table mapping idx -> socket fd. Bend wraps the idx in SockHandle{idx}.
// Pattern: pty_spawn.c's indexed-handle table + the toolchain tcp_connect.c's
// non-blocking connect + io_wait_on park (proven 2026-09-21).
//
// The socket stays O_NONBLOCK for life, so Sock.recv never parks the UI
// thread: a recv with no data returns Done{""} and the caller re-polls.

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <poll.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>

#define SOCK_MAX 64
static int sock_fds[SOCK_MAX];
static int sock_used[SOCK_MAX];
static int sock_next = 0;

int sock_alloc_fd(int fd) {
  for (int i = 0; i < SOCK_MAX; i++) {
    int idx = (sock_next + i) % SOCK_MAX;
    if (!sock_used[idx]) {
      sock_used[idx] = 1; sock_fds[idx] = fd;
      sock_next = (idx + 1) % SOCK_MAX; return idx;
    }
  }
  return -1;
}
int sock_get_fd(int idx) {
  if (idx < 0 || idx >= SOCK_MAX || !sock_used[idx]) return -1;
  return sock_fds[idx];
}
// Close the socket and free the slot.
void sock_free_idx(int idx) {
  if (idx >= 0 && idx < SOCK_MAX && sock_used[idx]) {
    close(sock_fds[idx]); sock_used[idx] = 0; sock_fds[idx] = -1;
  }
}

// Non-blocking connect outcome: w->code = EINPROGRESS means the poll loop
// parked us until the socket was writable; SO_ERROR then says how it ended.
// Any other code means connect finished synchronously (0) or the setup
// itself failed (socket/address errno).
static Term sock_connect_more(Env e, IoWork* w) {
  int       fd  = (int)w->made;
  int       err = (int)w->code;
  socklen_t len = sizeof(err);
  if (err == EINPROGRESS && getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)) {
    err = errno;
  }
  free(w->data);
  if (err != 0) {
    if (fd >= 0) close(fd);
    return io_fail(e, (u32)err, NULL);
  }
  int idx = sock_alloc_fd(fd);
  if (idx < 0) { close(fd); return io_fail(e, 12, NULL); } // ENOMEM: table full
  return io_done(e, io_hand((intptr_t)idx));
}

Term sock_connect_run(Env e, Term* f, IoWork* w) {
  struct sockaddr_in at;
  w->data = io_cstr(e, f[0], &w->size);
  int fd  = -1;
  errno   = EINVAL;
  if (!io_nul(w->data, w->size) && io_sys_addr(w->data, (u32)f[1], &at) == 0) {
    fd = socket(AF_INET, SOCK_STREAM, 0);
  }
  if (fd >= 0) {
    fcntl(fd, F_SETFD, FD_CLOEXEC); // audit F3: no fd leaks across exec
    int fl = fcntl(fd, F_GETFL, 0); // audit F7: checked (was nested/unchecked)
    if (fl < 0 || fcntl(fd, F_SETFL, fl | O_NONBLOCK) < 0) {
      close(fd);
      fd = -1;
    }
  }
  w->made = fd;
  io_sys_end(w, fd < 0 ? fd : connect(fd, (struct sockaddr*)&at, sizeof(at)));
  return w->code == EINPROGRESS
    ? io_wait_on(w, fd, POLLOUT, 0, sock_connect_more) : sock_connect_more(e, w);
}

static void __attribute__((constructor)) sock_connect_use(void) {
  io_eff(CID_SOCK_CONNECT_RAW, sock_connect_run, 0);
}
