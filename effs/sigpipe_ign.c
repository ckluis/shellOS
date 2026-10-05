// Ignore SIGPIPE process-wide (audit F6). A TCP RST arriving while
// Sock.send/Tls.send (or any other send/write) is in flight would
// otherwise terminate the entire shell with the default SIGPIPE
// disposition. With SIGPIPE ignored, the syscall fails with EPIPE and
// the Bend side observes a normal Fail{...} it can handle.
#include <signal.h>
static void __attribute__((constructor)) sigpipe_ign_use(void) {
  signal(SIGPIPE, SIG_IGN);
}
