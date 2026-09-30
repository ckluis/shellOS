// TLS recv — native-only stub, see tls_recv.c.

function tls_recv_raw(idx, max) {
  return io_fail(38);
}
