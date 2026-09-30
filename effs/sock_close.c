// Socket close — takes U32 idx, closes fd and frees the slot.
// Mirrors pty_close.c.
#include <unistd.h>
#include <stdlib.h>

extern void sock_free_idx(int idx);

static Term sock_close_pack(Env e, IoWork* w) {
  return io_done(e, term_pak(CID_UNIT, 0));
}
Term sock_close_run(Env e, Term* f, IoWork* w) {
  int idx = (int)io_hand_v(f[0]);
  sock_free_idx(idx);
  return sock_close_pack(e, w);
}
static void __attribute__((constructor)) sock_close_use(void) {
  io_eff(CID_SOCK_CLOSE_RAW, sock_close_run, 0);
}
