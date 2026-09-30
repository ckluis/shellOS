// Pty close — takes U32 idx, closes fd and frees slot.
#include <unistd.h>
#include <stdlib.h>
extern void pty_free_idx(int idx);
static Term pty_close_pack(Env e, IoWork* w) {
  return io_done(e, term_pak(CID_UNIT, 0));
}
Term pty_close_run(Env e, Term* f, IoWork* w) {
  int idx = (int)io_hand_v(f[0]);
  pty_free_idx(idx);
  return pty_close_pack(e, w);
}
static void __attribute__((constructor)) pty_close_use(void) {
  io_eff(CID_PTY_CLOSE_RAW, pty_close_run, 0);
}
