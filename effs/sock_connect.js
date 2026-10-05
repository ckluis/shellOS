// Socket
// ======
// Sockets are native-only (the C bridge in ./sock_connect.c); Node's net
// module is promise-based and would starve Bend's sync poll loop.
// Every entry fails LOUD with ENOSYS so misuse is never silent.

function sock_connect_raw(host, port) {
  return io_fail(38);
}
