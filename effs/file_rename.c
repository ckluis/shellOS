// File rename — atomic rename(2) for crash-safe item write-back.
// Bend def `filerename_raw` (see shell.bend) imports this file. The JS stub
// (effs/file_rename.js) performs the real rename via fs.renameSync —
// verified end to end 2026-09-21. PTY stubs remain ENOSYS on the JS target.

#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <stdio.h>

static Term file_rename_pack(Env e, IoWork* w) {
  Term r = w->code != 0 ? io_fail(e, w->code, NULL)
    : io_done(e, term_pak(CID_UNIT, 0));
  return r;
}

Term file_rename_run(Env e, Term* f, IoWork* w) {
  size_t n0 = 0, n1 = 0;
  char* s0 = io_cstr(e, f[0], &n0);
  char* s1 = io_cstr(e, f[1], &n1);
  if (!s0 || !s1) {
    w->code = 22;  /* EINVAL */
  } else if (rename(s0, s1) != 0) {
    w->code = errno ? errno : 5;  /* EIO fallback */
  } else {
    w->code = 0;
  }
  free(s0); free(s1);
  return file_rename_pack(e, w);
}
static void __attribute__((constructor)) file_rename_use(void) {
  io_eff(CID_FILERENAME_RAW, file_rename_run, 0);
}
