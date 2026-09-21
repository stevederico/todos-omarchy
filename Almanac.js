// Almanac hosted todos. No I/O. QML and Node tests share this file.

function trim(s) {
  return String(s || "").replace(/^\s+|\s+$/g, "")
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
    out.push({ id: String(row.id), name: trim(row.name) || "Almanac" })
  }
  return out
}

function isAlmanacPath(path) {
  var raw = trim(path)
  return raw === "almanac" || raw.indexOf("almanac:") === 0
}

function pathCalendarId(path) {
  var raw = trim(path)
  if (raw === "almanac" || raw === "almanac:") return ""
  if (raw.indexOf("almanac:") === 0) return raw.slice(8)
  return ""
}

function isAlmanacSource(src) {
  if (!src) return false
  if (src.kind === "almanac") return true
  return isAlmanacPath(src.path)
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
    kind: "almanac",
    title: (cal && cal.name) || "Almanac",
    calendarId: cal && cal.id ? String(cal.id) : "",
    path: ""
  }
}

function ensureSource(sources, calendars, newIdFn) {
  var next = (sources || []).slice()
  for (var i = 0; i < next.length; i++) {
    if (isAlmanacSource(next[i])) return next
  }
  var cal = resolveCalendar(calendars, "")
  if (!cal) return next
  next.unshift(makeSource(cal, newIdFn ? newIdFn() : ("almanac-" + cal.id)))
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
    description: todo && todo.description ? String(todo.description) : ""
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

function errorMessage(raw) {
  var text = String(raw || "")
  if (text.indexOf("ERROR:") === 0) return trim(text.slice(6))
  try {
    var parsed = JSON.parse(text)
    if (parsed && parsed.error) return String(parsed.error)
  } catch (e) {}
  return trim(text) || "Almanac request failed"
}

if (typeof module !== "undefined") {
  module.exports = {
    parseCalendars: parseCalendars,
    isAlmanacPath: isAlmanacPath,
    pathCalendarId: pathCalendarId,
    isAlmanacSource: isAlmanacSource,
    calendarIdOf: calendarIdOf,
    resolveCalendar: resolveCalendar,
    makeSource: makeSource,
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
