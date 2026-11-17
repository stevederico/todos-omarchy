function dirname(p) {
  const s = String(p || "")
  const i = s.lastIndexOf("/")
  return i <= 0 ? "" : s.slice(0, i)
}

function parseSourceDirs(raw) {
  let parsed = null
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
  const sources = parsed && parsed.sources && parsed.sources.length ? parsed.sources : []
  const seen = {}
  const out = []
  for (let i = 0; i < sources.length; i++) {
    const src = sources[i]
    if (!src || src.kind === "cloud" || src.kind === "almanac" || !src.path) continue
    const dir = dirname(src.path)
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
