// TLS connect — native-only stub, see tls_connect.c.
//
// TLS is native-only (OpenSSL called directly from ./tls_connect.c (linked -lssl -lcrypto)); Node's tls
// module is promise-based and would starve Bend's sync poll loop.
// Every entry fails LOUD with ENOSYS so misuse is never silent.

function tls_connect_raw(host, port) {
  return io_fail(38);
}
