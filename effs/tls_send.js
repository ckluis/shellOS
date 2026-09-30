// TLS send — native-only stub, see tls_send.c.

function tls_send_raw(idx, data) {
  return io_fail(38);
}
