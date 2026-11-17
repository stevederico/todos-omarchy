var PRODUCT = "Agent Cloud"

function trim(s) {
  return String(s || "").replace(/^\s+|\s+$/g, "")
}

function displayName(name) {
  const text = trim(name)
  if (!text || text === "Almanac" || text === "Dottie") return PRODUCT
  return text
}

function parseCalendars(raw) {
  let parsed = null
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { return [] }
  let list = []
  if (Array.isArray(parsed)) list = parsed
  else if (parsed && Array.isArray(parsed.calendars)) list = parsed.calendars
  else if (parsed && parsed.id) list = [parsed]
  const out = []
  for (let i = 0; i < list.length; i++) {
    const row = list[i]
    if (!row || !row.id) continue
    out.push({ id: String(row.id), name: displayName(row.name) })
  }
  return out
}

var PATH_PREFIXES = ["agentcloud", "almanac"]

function isCloudPath(path) {
  const raw = trim(path)
  for (let i = 0; i < PATH_PREFIXES.length; i++) {
    if (raw === PATH_PREFIXES[i] || raw.indexOf(PATH_PREFIXES[i] + ":") === 0) return true
  }
  return false
}

function pathCalendarId(path) {
  const raw = trim(path)
  for (let i = 0; i < PATH_PREFIXES.length; i++) {
    const prefix = PATH_PREFIXES[i] + ":"
    if (raw.indexOf(prefix) === 0) return raw.slice(prefix.length)
  }
  return ""
}

function isCloudSource(src) {
  if (!src) return false
  if (src.kind === "cloud" || src.kind === "almanac") return true
  return isCloudPath(src.path)
}

function calendarIdOf(src) {
  if (!src) return ""
  if (src.calendarId) return String(src.calendarId)
  return pathCalendarId(src.path)
}

function resolveCalendar(calendars, wantedId) {
  const list = calendars || []
  if (!list.length) return null
  const want = trim(wantedId)
  if (want) {
    for (let i = 0; i < list.length; i++) if (list[i].id === want) return list[i]
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
  const list = sources || []
  for (let i = 0; i < list.length; i++) {
    if (isCloudSource(list[i])) return list[i].id
  }
  return list.length ? list[0].id : ""
}

function ensureSource(sources, calendars, newIdFn) {
  const next = (sources || []).slice()
  for (let i = 0; i < next.length; i++) {
    if (isCloudSource(next[i])) return next
  }
  const cal = resolveCalendar(calendars, "")
  if (!cal) return next
  next.unshift(makeSource(cal, newIdFn ? newIdFn() : ("cloud-" + cal.id)))
  return next
}

function tagTitle(tag) {
  const raw = trim(tag)
  if (!raw) return "To-Dos"
  return raw.charAt(0).toUpperCase() + raw.slice(1)
}

function sectionOf(todo) {
  const tags = (todo && todo.tags) || []
  if (tags.length) return tagTitle(tags[0])
  return "To-Dos"
}

function itemFromTodo(todo) {
  const title = trim(todo && todo.title)
  const uid = todo && todo.uid ? String(todo.uid) : ""
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
  let parsed = payload
  if (typeof payload === "string") {
    try { parsed = JSON.parse(payload) } catch (e) { return [] }
  }
  let todos = []
  if (parsed && Array.isArray(parsed.todos)) todos = parsed.todos
  else if (Array.isArray(parsed)) todos = parsed
  const buckets = []
  const index = {}
  for (let i = 0; i < todos.length; i++) {
    const item = itemFromTodo(todos[i])
    if (!item.text && !item.uid) continue
    const title = item.section
    if (!Object.prototype.hasOwnProperty.call(index, title)) {
      index[title] = buckets.length
      buckets.push({ id: title, title: title, items: [] })
    }
    buckets[index[title]].items.push(item)
  }
  return buckets
}

function countOpen(sections) {
  let n = 0
  for (let s = 0; s < (sections || []).length; s++) {
    const items = sections[s].items || []
    for (let i = 0; i < items.length; i++) if (!items[i].isCompleted) n++
  }
  return n
}

function countCompleted(sections) {
  let n = 0
  for (let s = 0; s < (sections || []).length; s++) {
    const items = sections[s].items || []
    for (let i = 0; i < items.length; i++) if (items[i].isCompleted) n++
  }
  return n
}

function isConflict(raw) {
  return trim(String(raw || "").split("\n")[0]) === "ERROR:conflict"
}

function conflictInfo(raw) {
  let parsed = null
  try { parsed = JSON.parse(String(raw || "").split("\n").slice(1).join("\n")) } catch (e) { parsed = null }
  const current = parsed && parsed.current && typeof parsed.current === "object" ? parsed.current : null
  return { deleted: !!(parsed && parsed.deleted), current: current }
}

const MAX_TITLE_BYTES = 512

function utf8Length(text) {
  return encodeURIComponent(text).replace(/%[0-9A-F]{2}/g, "x").length
}

function conflictCopyTitle(title) {
  const suffix = " (conflict copy)"
  const chars = Array.from(trim(title))
  while (chars.length && utf8Length(chars.join("")) > MAX_TITLE_BYTES - suffix.length)
    chars.pop()
  return trim(chars.join("")) + suffix
}

function errorMessage(raw) {
  const text = String(raw || "")
  if (isConflict(text)) return "Changed elsewhere"
  if (text.indexOf("ERROR:") === 0) return trim(text.slice(6))
  try {
    const parsed = JSON.parse(text)
    if (parsed && parsed.error) return String(parsed.error)
  } catch (e) {}
  return trim(text) || PRODUCT + " request failed"
}

function conflictRetry(job, info) {
  const payload = (job && job.payload) || {}
  const body = payload.body || {}
  if (!job || job.op === "delete") return null
  if (payload.toggle) {
    const current = info && info.current
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
    MAX_TITLE_BYTES: MAX_TITLE_BYTES,
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
