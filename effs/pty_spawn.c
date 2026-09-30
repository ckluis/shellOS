// Pty spawn — returns a U32 index into a table mapping idx -> master fd.
// Bend wraps the idx in PtyHandle{idx}.
//
// WAVE 2 NARROWING: the spawned shell is FIXED to "/bin/sh" at this seam.
// The Bend FFI takes no path argument, so no caller (Bend, JS, or future
// code) can express another binary. The data argument is not read at all.

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/types.h>

extern int posix_openpt(int);
extern int grantpt(int);
extern int unlockpt(int);
extern char *ptsname(int);

#define PTY_MAX 64
static int pty_fds[PTY_MAX];
static int pty_used[PTY_MAX];
static pid_t pty_pids[PTY_MAX];
static int pty_next = 0;

int pty_alloc_fd(int fd) {
  for (int i = 0; i < PTY_MAX; i++) {
    int idx = (pty_next + i) % PTY_MAX;
    if (!pty_used[idx]) {
      pty_used[idx] = 1; pty_fds[idx] = fd;
      pty_next = (idx + 1) % PTY_MAX; return idx;
    }
  }
  return -1;
}
int pty_get_fd(int idx) {
  if (idx < 0 || idx >= PTY_MAX || !pty_used[idx]) return -1;
  return pty_fds[idx];
}
// Close the master and free the slot. Children are auto-reaped via
// SIG_IGN on SIGCHLD (see constructor), so no waitpid here.
// NOTE (audit F4): we deliberately do NOT kill(-pid, SIGHUP) anymore.
// With SIGCHLD ignored the kernel reaps a dead child immediately, so the
// pid can be recycled by an unrelated process before we get here —
// signalling it (or its process GROUP via -pid) can hit innocents.
// Closing the master already delivers SIGHUP to the pty's foreground
// process group by standard pty semantics; the shell exits on the next
// stdin read (EIO) and is reaped automatically.
void pty_free_idx(int idx) {
  if (idx >= 0 && idx < PTY_MAX && pty_used[idx]) {
    close(pty_fds[idx]); pty_used[idx] = 0; pty_fds[idx] = -1;
    pty_pids[idx] = 0;
  }
}

static Term pty_spawn_pack(Env e, IoWork* w) {
  return w->code != 0 ? io_fail(e, w->code, NULL)
    : io_done(e, io_hand((intptr_t)w->made));
}

Term pty_spawn_run(Env e, Term* f, IoWork* w) {
  (void)f; // Wave 2: no arguments — the shell path is fixed below.
  const char* shell = "/bin/sh";
  int master = posix_openpt(O_RDWR | O_NOCTTY);
  if (master < 0) { w->code = errno; return pty_spawn_pack(e, w); }
  // Audit F3: the forked shell must not inherit this (or any session) fd
  // across exec — FD_CLOEXEC on every fd we allocate.
  fcntl(master, F_SETFD, FD_CLOEXEC);
  if (grantpt(master) < 0 || unlockpt(master) < 0) {
    w->code = errno; close(master); return pty_spawn_pack(e, w);
  }
  char pts[64]; const char* pn = ptsname(master);
  if (!pn) { w->code = errno; close(master); return pty_spawn_pack(e, w); }
  strncpy(pts, pn, sizeof(pts)-1); pts[sizeof(pts)-1] = '\0';
  // Audit F7: the non-blocking invariant is load-bearing for the whole
  // poll loop — fail closed if we cannot establish it.
  int fl = fcntl(master, F_GETFL, 0);
  if (fl < 0 || fcntl(master, F_SETFL, fl | O_NONBLOCK) < 0) {
    w->code = errno ? errno : EIO; close(master); return pty_spawn_pack(e, w);
  }
  // Wave 2: `shell` is the compile-time literal "/bin/sh" — no copy, no
  // truncation, no ENAMETOOLONG path (the old F19 check is dead).
  pid_t pid = fork();
  if (pid < 0) { w->code = errno; close(master); return pty_spawn_pack(e, w); }
  if (pid == 0) {
    close(master); setsid();
    int slave = open(pts, O_RDWR);
    if (slave < 0) _exit(127);
#ifdef TIOCSCTTY
    ioctl(slave, TIOCSCTTY, 0);
#endif
    dup2(slave,0); dup2(slave,1); dup2(slave,2);
    if (slave > 2) close(slave);
    execl(shell, shell, (char*)NULL); _exit(127);
  }
  int idx = pty_alloc_fd(master);
  // Audit F8: table-full AFTER fork — the child is already running; kill it
  // instead of leaking a detached shell.
  if (idx < 0) { w->code = 12; close(master); kill(pid, SIGKILL); return pty_spawn_pack(e, w); }
  pty_pids[idx] = pid;
  w->made = (intptr_t)idx; w->code = 0;
  return pty_spawn_pack(e, w);
}
static void __attribute__((constructor)) pty_spawn_use(void) {
  // Auto-reap children: with SIGCHLD ignored the kernel reaps them, so a
  // closed PTY can never leave a zombie behind.
  signal(SIGCHLD, SIG_IGN);
  io_eff(CID_PTY_SPAWN_RAW, pty_spawn_run, 0);
}
