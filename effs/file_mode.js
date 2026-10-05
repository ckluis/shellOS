// File mode bits
// ===============
// stat(2) permission bits for a path (config 0600 guard). Returns the low
// 9 permission bits as a U32 via io_done. On stat failure the effect fails
// with the errno. Mirrors effs/file_mode.c.

function filemode_raw(path) {
  const fs = require("fs");
  try {
    const mode = fs.statSync(Buffer.from(io_bytes(path))).mode & 0o777;
    return io_done(mode);
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}
