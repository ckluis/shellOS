// File mode bits — stat(2) permission bits for a path (config 0600 guard).
// Bend def `filemode_raw` (see gmail.bend) imports this file. Returns the
// low 9 permission bits (st.st_mode & 0777) packed as a U32 via io_hand.
// On stat failure the effect fails with the errno, so callers can tell
// "absent" (ENOENT) from other errors. The JS stub (effs/file_mode.js)
// mirrors this via fs.statSync. Never follows the fail-open path: callers
// must treat any failure as "do not read".

#include <sys/stat.h>
#include <errno.h>
#include <stdlib.h>

static Term file_mode_pack(Env e, IoWork* w) {
  Term r = w->code != 0 ? io_fail(e, w->code, NULL)
    : io_done(e, io_hand((intptr_t)(w->made & 0777)));
  return r;
}

Term file_mode_run(Env e, Term* f, IoWork* w) {
  size_t n0 = 0;
  char* s0 = io_cstr(e, f[0], &n0);
  if (!s0) {
    w->code = 22;  /* EINVAL */
  } else {
    struct stat st;
    if (stat(s0, &st) != 0) {
      w->code = errno ? errno : 5;  /* EIO fallback */
    } else {
      w->code = 0;
      w->made = (intptr_t)(st.st_mode & 0777);
    }
    free(s0);
  }
  return file_mode_pack(e, w);
}
static void __attribute__((constructor)) file_mode_use(void) {
  io_eff(CID_FILEMODE_RAW, file_mode_run, 0);
}
