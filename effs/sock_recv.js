// Socket recv — native-only stub, see sock_connect.js.

function sock_recv_raw(idx, max) {
  return io_fail(38);
}
