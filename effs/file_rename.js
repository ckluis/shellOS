// File rename
// ====
// Atomic rename for crash-safe item write-back: write items.txt.tmp, then
// rename over items.txt. rename(2) is atomic on POSIX; fs.renameSync is
// atomic on the same filesystem in Node/Bun.

function filerename_raw(from, to) {
  const fs = require("fs");
  try {
    fs.renameSync(Buffer.from(io_bytes(from)), Buffer.from(io_bytes(to)));
    return io_done({ $: "Unit" });
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 5));
  }
}
