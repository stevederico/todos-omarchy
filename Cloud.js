// Agent Cloud hosted todos (the agentcloud server). No I/O. QML and Node tests share this file.

var PRODUCT = "Agent Cloud"

function trim(s) {
  return String(s || "").replace(/^\s+|\s+$/g, "")
}

// The old default names ("Almanac", "Dottie") show as Agent Cloud.
function displayName(name) {
  var text = trim(name)
  if (!text || text === "Almanac" || text === "Dottie") return PRODUCT
  return text
}

function parseCalendars(raw) {
  var parsed = null
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { return [] }
  var list = []
  if (Array.isArray(parsed)) list = parsed
  else if (parsed && Array.isArray(parsed.calendars)) list = parsed.calendars
  else if (parsed && parsed.id) list = [parsed]
  var out = []
  for (var i = 0; i < list.length; i++) {
    var row = list[i]
    if (!row || !row.id) continue
    out.push({ id: String(row.id), name: displayName(row.name) })
  }
  return out
}

// "agentcloud" or "agentcloud:CAL_ID" in the add field; "almanac" still works.
var PATH_PREFIXES = ["agentcloud", "almanac"]

function isCloudPath(path) {
  var raw = trim(path)
  for (var i = 0; i < PATH_PREFIXES.length; i++) {
    if (raw === PATH_PREFIXES[i] || raw.indexOf(PATH_PREFIXES[i] + ":") === 0) return true
  }
  return false
}

function pathCalendarId(path) {
  var raw = trim(path)
  for (var i = 0; i < PATH_PREFIXES.length; i++) {
    var prefix = PATH_PREFIXES[i] + ":"
    if (raw.indexOf(prefix) === 0) return raw.slice(prefix.length)
  }
  return ""
}

function isCloudSource(src) {
  if (!src) return false
  // "almanac": the kind tabs were saved with before the Agent Cloud rename.
  if (src.kind === "cloud" || src.kind === "almanac") return true
  return isCloudPath(src.path)
}

function calendarIdOf(src) {
  if (!src) return ""
  if (src.calendarId) return String(src.calendarId)
  return pathCalendarId(src.path)
}

function resolveCalendar(calendars, wantedId) {
  var list = calendars || []
  if (!list.length) return null
  var want = trim(wantedId)
  if (want) {
    for (var i = 0; i < list.length; i++) if (list[i].id === want) return list[i]
    return null
  }
  return list[0]
}

function makeSource(cal, id) {
  return {
    id: id,
    kind: "cloud",
    title: displayName(cal && cal.name),
    calendarId: cal && cal.id ? String(cal.id) : "",
    path: ""
  }
}

function defaultTabId(sources) {
  var list = sources || []
  for (var i = 0; i < list.length; i++) {
    if (isCloudSource(list[i])) return list[i].id
  }
  return list.length ? list[0].id : ""
}

function ensureSource(sources, calendars, newIdFn) {
  var next = (sources || []).slice()
  for (var i = 0; i < next.length; i++) {
    if (isCloudSource(next[i])) return next
  }
  var cal = resolveCalendar(calendars, "")
  if (!cal) return next
  next.unshift(makeSource(cal, newIdFn ? newIdFn() : ("cloud-" + cal.id)))
  return next
}

function tagTitle(tag) {
  var raw = trim(tag)
  if (!raw) return "To-Dos"
  return raw.charAt(0).toUpperCase() + raw.slice(1)
}

function sectionOf(todo) {
  var tags = (todo && todo.tags) || []
  if (tags.length) return tagTitle(tags[0])
  return "To-Dos"
}

function itemFromTodo(todo) {
  var title = trim(todo && todo.title)
  var uid = todo && todo.uid ? String(todo.uid) : ""
  return {
    id: uid || ("todo:" + title),
    text: title,
    section: sectionOf(todo),
    lineIndex: -1,
    indent: 0,
    isCompleted: !!(todo && todo.done),
    uid: uid,
    due: todo && todo.due ? String(todo.due) : "",
    priority: todo && typeof todo.priority === "number" ? todo.priority : 0,
    tags: (todo && todo.tags) || [],
    description: todo && todo.description ? String(todo.description) : "",
    rev: todo && typeof todo.rev === "number" ? todo.rev : 0
  }
}

function parseTodos(payload) {
  var parsed = payload
  if (typeof payload === "string") {
    try { parsed = JSON.parse(payload) } catch (e) { return [] }
  }
  var todos = []
  if (parsed && Array.isArray(parsed.todos)) todos = parsed.todos
  else if (Array.isArray(parsed)) todos = parsed
  var buckets = []
  var index = {}
  for (var i = 0; i < todos.length; i++) {
    var item = itemFromTodo(todos[i])
    if (!item.text && !item.uid) continue
    var title = item.section
    if (!Object.prototype.hasOwnProperty.call(index, title)) {
      index[title] = buckets.length
      buckets.push({ id: title, title: title, items: [] })
    }
    buckets[index[title]].items.push(item)
  }
  return buckets
}

function countOpen(sections) {
  var n = 0
  for (var s = 0; s < (sections || []).length; s++) {
    var items = sections[s].items || []
    for (var i = 0; i < items.length; i++) if (!items[i].isCompleted) n++
  }
  return n
}

function countCompleted(sections) {
  var n = 0
  for (var s = 0; s < (sections || []).length; s++) {
    var items = sections[s].items || []
    for (var i = 0; i < items.length; i++) if (items[i].isCompleted) n++
  }
  return n
}

// The script prints ERROR:conflict when a --rev is stale (HTTP 412),
// then the server's {"deleted", "current"} on the next line.
function isConflict(raw) {
  return trim(String(raw || "").split("\n")[0]) === "ERROR:conflict"
}

// { deleted, current } from a conflict reply. current is the server's todo or null.
function conflictInfo(raw) {
  var parsed = null
  try { parsed = JSON.parse(String(raw || "").split("\n").slice(1).join("\n")) } catch (e) { parsed = null }
  var current = parsed && parsed.current && typeof parsed.current === "object" ? parsed.current : null
  return { deleted: !!(parsed && parsed.deleted), current: current }
}

// Title for the new todo that keeps an edit the server refused. Fits the 512-byte cap.
function conflictCopyTitle(title) {
  var suffix = " (conflict copy)"
  var chars = Array.from(trim(title))
  while (chars.length && encodeURIComponent(chars.join("")).replace(/%[0-9A-F]{2}/g, "x").length > 512 - suffix.length)
    chars.pop()
  return trim(chars.join("")) + suffix
}

function errorMessage(raw) {
  var text = String(raw || "")
  if (isConflict(text)) return "Changed elsewhere"
  if (text.indexOf("ERROR:") === 0) return trim(text.slice(6))
  try {
    var parsed = JSON.parse(text)
    if (parsed && parsed.error) return String(parsed.error)
  } catch (e) {}
  return trim(text) || PRODUCT + " request failed"
}

// What to queue after a write hit a stale rev (HTTP 412), or null. The server
// copy always stays. An edit is saved as a new todo. A toggle is sent again on
// top of the server copy, at its rev. A delete, or a toggle of a todo that is
// gone or already there, needs nothing.
function conflictRetry(job, info) {
  var payload = (job && job.payload) || {}
  var body = payload.body || {}
  if (!job || job.op === "delete") return null
  if (payload.toggle) {
    var current = info && info.current
    if (!current || info.deleted || !current.rev || !!current.done === !!body.done) return null
    return {
      op: "post",
      payload: { uid: job.uid || payload.uid, toggle: true, rev: current.rev, body: { title: current.title, done: !!body.done } }
    }
  }
  if (body.title === undefined) return null
  return { op: "post", payload: { body: { title: conflictCopyTitle(body.title), done: !!body.done } } }
}

if (typeof module !== "undefined") {
  module.exports = {
    PRODUCT: PRODUCT,
    displayName: displayName,
    isConflict: isConflict,
    conflictInfo: conflictInfo,
    conflictCopyTitle: conflictCopyTitle,
    conflictRetry: conflictRetry,
    parseCalendars: parseCalendars,
    isCloudPath: isCloudPath,
    pathCalendarId: pathCalendarId,
    isCloudSource: isCloudSource,
    calendarIdOf: calendarIdOf,
    resolveCalendar: resolveCalendar,
    makeSource: makeSource,
    defaultTabId: defaultTabId,
    ensureSource: ensureSource,
    tagTitle: tagTitle,
    sectionOf: sectionOf,
    itemFromTodo: itemFromTodo,
    parseTodos: parseTodos,
    countOpen: countOpen,
    countCompleted: countCompleted,
    errorMessage: errorMessage
  }
}
