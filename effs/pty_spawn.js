// Pty
// ====
// Node.js has no built-in PTY; the PTY effects are native-only.
// Every entry fails with ENOSYS so misuse is loud, not silent.

function pty_spawn_raw() {
  return io_fail(38);
}
