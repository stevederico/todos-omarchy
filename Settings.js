function defaultSettings() {
  return {
    gitCommit: false,
    gitPush: false,
    updateChangelog: false
  }
}

function asBool(value, fallback) {
  if (value === true) return true
  if (value === false) return false
  return fallback === true
}

function parseSettings(raw) {
  var parsed = null
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) parsed = {}
  var defaults = defaultSettings()
  return {
    gitCommit: asBool(parsed.gitCommit, defaults.gitCommit),
    gitPush: asBool(parsed.gitPush, defaults.gitPush),
    updateChangelog: asBool(parsed.updateChangelog, defaults.updateChangelog)
  }
}

function serializeSettings(settings) {
  var next = parseSettings(JSON.stringify(settings || {}))
  return JSON.stringify({
    gitCommit: next.gitCommit === true,
    gitPush: next.gitPush === true,
    updateChangelog: next.updateChangelog === true
  }, null, 2) + "\n"
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultSettings: defaultSettings,
    parseSettings: parseSettings,
    serializeSettings: serializeSettings
  }
}
