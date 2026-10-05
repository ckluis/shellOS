// File sync — fsync(2) a path for write-back durability.
// Bend def `filesync_raw` (see shell.bend) imports this file. The JS stub
// (effs/file_sync.js) performs the real fsync via fs.fsyncSync.
// Called after closing items.txt.tmp and BEFORE rename(2): on fsync
// failure the caller does NOT rename, so a crashed-then-rebooted box can
// never see a half-synced items.txt.

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdlib.h>
#include <stdio.h>

static Term file_sync_pack(Env e, IoWork* w) {
  Term r = w->code != 0 ? io_fail(e, w->code, NULL)
    : io_done(e, term_pak(CID_UNIT, 0));
  return r;
}

Term file_sync_run(Env e, Term* f, IoWork* w) {
  u64 n0 = 0;
  char* s0 = io_cstr(e, f[0], &n0);
  if (!s0) {
    w->code = 22;  /* EINVAL */
  } else {
    /* O_RDWR first; O_RDONLY fallback (fsync works on a read-only fd too). */
    int fd = open(s0, O_RDWR);
    if (fd < 0) {
      fd = open(s0, O_RDONLY);
    }
    if (fd < 0) {
      w->code = errno ? errno : 5;  /* EIO fallback */
    } else if (fsync(fd) != 0) {
      w->code = errno ? errno : 5;
      close(fd);
    } else {
      w->code = 0;
      close(fd);
    }
    free(s0);
  }
  return file_sync_pack(e, w);
}
static void __attribute__((constructor)) file_sync_use(void) {
  io_eff(CID_FILESYNC_RAW, file_sync_run, 0);
}
