// TLS close — native-only stub, see tls_close.c.

function tls_close_raw(idx) {
  return io_fail(38);
}
