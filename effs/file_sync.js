// File sync
// ====
// fsync(2) a path for write-back durability: called after closing
// items.txt.tmp and BEFORE rename, so a crash can never leave a
// half-synced items.txt. On failure the caller skips the rename.

function filesync_raw(path) {
  const fs = require("fs");
  try {
    const fd = fs.openSync(Buffer.from(io_bytes(path)), "r");
    fs.fsyncSync(fd);
    fs.closeSync(fd);
    return io_done({ $: "Unit" });
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}
