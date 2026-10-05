// TLS connect — resolves host (getaddrinfo), blocking TCP connect with a
// 10s timeout, then a synchronous OpenSSL client handshake with MANDATORY
// certificate verification. Returns a U32 index into a table mapping
// idx -> (SSL*, fd). Bend wraps the idx in TlsHandle{idx} (see sock.bend).
//
// SECURITY (fail-closed, no exceptions):
//   - SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL)
//   - SSL_CTX_set_default_verify_paths(ctx) must succeed (system CA bundle)
//   - SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION)
//   - SNI via SSL_set_tlsext_host_name (must succeed)
//   - Hostname check via X509_VERIFY_PARAM_set1_host (chain alone is NOT
//     enough — without this a valid cert for another name would pass)
//   - SSL_connect must return 1 AND SSL_get_verify_result must be X509_V_OK
// Any failure -> io_fail, never a half-open connection. The C layer moves
// bytes only; all parsing stays in pure Bend.
//
// LINKING: this file calls OpenSSL directly (several OpenSSL "functions"
// are actually macros, e.g. SSL_CTX_set_min_proto_version,
// SSL_set_tlsext_host_name, SSL_get_peer_certificate, so a dlsym-based
// runtime binding cannot work). The build links -lssl -lcrypto via a
// build-scoped PATH-local clang wrapper (build/clangwrap/clang) that is
// used ONLY for this project's native builds — it is never installed and
// never shadows the system clang outside the build command.

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <poll.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netdb.h>
#include <openssl/ssl.h>
#include <openssl/x509_vfy.h>

#define TLS_MAX 32
#define TLS_CONNECT_TIMEOUT_S 10

static SSL* tls_ssl_tab[TLS_MAX];
static int  tls_fd_tab[TLS_MAX];
static int  tls_used[TLS_MAX];
static int  tls_next = 0;

int tls_alloc(SSL* ssl, int fd) {
  for (int i = 0; i < TLS_MAX; i++) {
    int idx = (tls_next + i) % TLS_MAX;
    if (!tls_used[idx]) {
      tls_used[idx] = 1; tls_ssl_tab[idx] = ssl; tls_fd_tab[idx] = fd;
      tls_next = (idx + 1) % TLS_MAX; return idx;
    }
  }
  return -1;
}
SSL* tls_get_ssl(int idx) {
  if (idx < 0 || idx >= TLS_MAX || !tls_used[idx]) return NULL;
  return tls_ssl_tab[idx];
}
int tls_get_fd(int idx) {
  if (idx < 0 || idx >= TLS_MAX || !tls_used[idx]) return -1;
  return tls_fd_tab[idx];
}
// Best-effort shutdown, then free everything and release the slot.
void tls_free_idx(int idx);

// Blocking TCP connect with a hard timeout (synchronous, fd-based —
// no async/promise APIs). Returns fd or -1 with errno set.
static int tls_tcp_connect(const char* host, const char* port) {
  struct addrinfo hints, *ai = NULL, *a;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  if (getaddrinfo(host, port, &hints, &ai) != 0) { errno = EHOSTUNREACH; return -1; }
  int fd = -1;
  for (a = ai; a; a = a->ai_next) {
    fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
    if (fd < 0) continue;
    fcntl(fd, F_SETFD, FD_CLOEXEC); // audit F3: no fd leaks across exec
    int fl = fcntl(fd, F_GETFL, 0);
    if (fl < 0) { close(fd); fd = -1; continue; }
    if (fcntl(fd, F_SETFL, fl | O_NONBLOCK) < 0) { close(fd); fd = -1; continue; }
    int rc = connect(fd, a->ai_addr, a->ai_addrlen);
    if (rc < 0 && errno == EINPROGRESS) {
      // poll(), not select(): fd_set is a fixed FD_SETSIZE-bit stack array
      // and FD_SET(fd) with fd >= 1024 is a stack buffer overflow (audit F2).
      struct pollfd pfd;
      pfd.fd = fd; pfd.events = POLLOUT; pfd.revents = 0;
      rc = poll(&pfd, 1, TLS_CONNECT_TIMEOUT_S * 1000);
      if (rc > 0) {
        int se = 0; socklen_t sl = sizeof(se);
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &se, &sl) != 0)
          se = errno ? errno : EIO;
        if (se) { errno = se; rc = -1; } else rc = 0;
      } else if (rc == 0) { errno = ETIMEDOUT; rc = -1; }
    }
    if (rc == 0) break;
    close(fd); fd = -1;
  }
  int saved = errno;
  freeaddrinfo(ai);
  errno = saved;
  return fd;
}

Term tls_connect_run(Env e, Term* f, IoWork* w) {
  w->data = io_cstr(e, f[0], &w->size);
  const char* host = (const char*)w->data;
  char portbuf[12]; // max u32 = 10 digits + NUL (audit F12)
  snprintf(portbuf, sizeof(portbuf), "%u", (u32)f[1]);

  int fd = -1, err = 0;
  const char* emsg = NULL;
  SSL* ssl = NULL;
  SSL_CTX* ctx = NULL;

  fd = tls_tcp_connect(host, portbuf);
  if (fd < 0) { err = errno; emsg = "tls: tcp connect failed"; goto done; }

  // Blocking I/O from here, bounded by socket timeouts.
  { int fl2 = fcntl(fd, F_GETFL, 0);
    if (fl2 < 0 || fcntl(fd, F_SETFL, fl2 & ~O_NONBLOCK) < 0) {
      err = errno ? errno : EIO; emsg = "tls: fcntl clear-nonblock failed";
      goto done; } }
  { struct timeval tv = { TLS_CONNECT_TIMEOUT_S, 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv)); }

  ctx = SSL_CTX_new(TLS_client_method());
  if (!ctx) { err = EPROTO; emsg = "tls: SSL_CTX_new failed"; goto done; }
  SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
  SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
  if (SSL_CTX_set_default_verify_paths(ctx) != 1) {
    err = EPROTO; emsg = "tls: no system CA bundle"; goto done;
  }
  ssl = SSL_new(ctx);
  SSL_CTX_free(ctx); ctx = NULL; // SSL holds its own ctx reference
  if (!ssl) { err = EPROTO; emsg = "tls: SSL_new failed"; goto done; }

  // Hostname binding: a valid chain for the WRONG name must NOT pass.
  { X509_VERIFY_PARAM* pm = SSL_get0_param(ssl);
    if (!pm || X509_VERIFY_PARAM_set1_host(pm, host, 0) != 1) {
      err = EPROTO; emsg = "tls: hostname verify-param failed"; goto done; } }

  if (SSL_set_tlsext_host_name(ssl, host) != 1) {
    err = EPROTO; emsg = "tls: SNI failed"; goto done; }
  if (SSL_set_fd(ssl, fd) != 1) {
    err = EPROTO; emsg = "tls: SSL_set_fd failed"; goto done; }
  if (SSL_connect(ssl) != 1) {
    err = EPROTO; emsg = "tls: handshake failed"; goto done; }
  if (SSL_get_verify_result(ssl) != X509_V_OK) {
    err = EPROTO; emsg = "tls: certificate verify failed"; goto done; }

  // Verified: hand the session to the non-blocking poll loop.
  { int fl3 = fcntl(fd, F_GETFL, 0);
    if (fl3 < 0 || fcntl(fd, F_SETFL, fl3 | O_NONBLOCK) < 0) {
      err = errno ? errno : EIO; emsg = "tls: fcntl set-nonblock failed";
      goto done; } }
  { int idx = tls_alloc(ssl, fd);
    free(w->data);
    if (idx < 0) {
      SSL_shutdown(ssl); SSL_free(ssl); close(fd);
      return io_fail(e, 12, "tls: session table full");
    }
    return io_done(e, io_hand((intptr_t)idx)); }

done:
  free(w->data);
  if (ctx) SSL_CTX_free(ctx);
  if (ssl) SSL_free(ssl);
  if (fd >= 0) close(fd);
  return io_fail(e, (u32)err, emsg);
}

void tls_free_idx(int idx) {
  if (idx >= 0 && idx < TLS_MAX && tls_used[idx]) {
    if (tls_ssl_tab[idx]) { SSL_shutdown(tls_ssl_tab[idx]); SSL_free(tls_ssl_tab[idx]); }
    if (tls_fd_tab[idx] >= 0) close(tls_fd_tab[idx]);
    tls_ssl_tab[idx] = NULL; tls_fd_tab[idx] = -1; tls_used[idx] = 0;
  }
}

static void __attribute__((constructor)) tls_connect_use(void) {
  io_eff(CID_TLS_CONNECT_RAW, tls_connect_run, 0);
}
