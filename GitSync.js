function dirname(p) {
  var s = String(p || "")
  var i = s.lastIndexOf("/")
  return i <= 0 ? "" : s.slice(0, i)
}

function parseSourceDirs(raw) {
  var parsed = null
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
  var sources = parsed && parsed.sources && parsed.sources.length ? parsed.sources : []
  var seen = {}
  var out = []
  for (var i = 0; i < sources.length; i++) {
    var src = sources[i]
    if (!src || !src.path) continue
    var dir = dirname(src.path)
    if (!dir || seen[dir]) continue
    seen[dir] = true
    out.push(dir)
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    dirname: dirname,
    parseSourceDirs: parseSourceDirs
  }
}
