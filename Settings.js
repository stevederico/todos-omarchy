function defaultSettings() {
  return {}
}

function parseSettings(raw) {
  var parsed = null
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) parsed = {}
  return {}
}

function serializeSettings(settings) {
  return "{}\n"
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultSettings: defaultSettings,
    parseSettings: parseSettings,
    serializeSettings: serializeSettings
  }
}
