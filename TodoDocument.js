// Pure markdown todo mutations. Panel.qml imports this; Node tests require
// the same file. No I/O, no git, no QML types.

function fromText(text) {
  var raw = String(text || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n")
  return raw.split("\n")
}

function toText(lines) {
  var body = (lines || []).join("\n")
  if (body.length === 0 || body.charAt(body.length - 1) !== "\n") body += "\n"
  return body
}

function trim(s) {
  return String(s || "").replace(/^\s+|\s+$/g, "")
}

function error(code) {
  var messages = {
    emptyText: "Empty to-do text",
    notFound: "Item out of date — refresh and try again",
    invalidLine: "File changed under us — refresh and try again"
  }
  var err = new Error(messages[code] || code)
  err.code = code
  throw err
}

function isSectionHeader(trimmed) {
  return trimmed.indexOf("##") === 0 && trimmed.indexOf("###") !== 0
}

function sectionTitle(fromHeader) {
  return trim(fromHeader.slice(2))
}

function isTodoLine(line) {
  return /^[\t ]*-\s+\S/.test(line)
}

function isCompletedTodoLine(line) {
  return /^[\t ]*-\s+\[[xX]\](\s|$)/.test(line)
}

function todoText(line) {
  var dash = line.match(/^[\t ]*-\s+/)
  if (!dash) return ""
  var rest = line.slice(dash[0].length)
  var box = rest.match(/^\[[xX ]\]\s*/)
  if (box) rest = rest.slice(box[0].length)
  return trim(rest)
}

function leadingWhitespace(line) {
  var i = 0
  while (i < line.length && (line.charAt(i) === " " || line.charAt(i) === "\t")) i++
  return line.slice(0, i)
}

function formatTodoLine(indent, text, completed) {
  return (indent || "") + (completed ? "- [x] " : "- ") + text
}

function makeItem(offset, body, section, indent, done, ordinal) {
  return {
    id: (done ? "x" : "o") + ":" + section + ":" + String(ordinal || 1) + ":" + body,
    text: body,
    section: section,
    lineIndex: offset,
    indent: indent,
    isCompleted: done
  }
}

function parse(lines) {
  var currentTitle = "To-Dos"
  var buckets = []
  var index = {}
  var ordinals = {}

  function ensureSection(title) {
    if (Object.prototype.hasOwnProperty.call(index, title)) return index[title]
    buckets.push({ title: title, items: [] })
    var i = buckets.length - 1
    index[title] = i
    return i
  }

  for (var offset = 0; offset < lines.length; offset++) {
    var line = lines[offset]
    var trimmed = trim(line)
    if (isSectionHeader(trimmed)) {
      currentTitle = sectionTitle(trimmed)
      ensureSection(currentTitle)
      continue
    }
    if (!isTodoLine(line)) continue
    var body = todoText(line)
    if (body.length === 0) continue
    var done = isCompletedTodoLine(line)
    var si = ensureSection(currentTitle)
    var key = currentTitle + "\0" + body + "\0" + (done ? "x" : "o")
    ordinals[key] = (ordinals[key] || 0) + 1
    buckets[si].items.push(makeItem(offset, body, currentTitle, leadingWhitespace(line).length, done, ordinals[key]))
  }

  var out = []
  for (var b = 0; b < buckets.length; b++) {
    var open = []
    var doneItems = []
    var items = buckets[b].items
    for (var i = 0; i < items.length; i++) {
      if (items[i].isCompleted) doneItems.push(items[i])
      else open.push(items[i])
    }
    var combined = open.concat(doneItems)
    if (combined.length === 0) continue
    out.push({ id: buckets[b].title, title: buckets[b].title, items: combined })
  }
  return out
}

function openCount(lines) {
  var sections = parse(lines)
  var n = 0
  for (var s = 0; s < sections.length; s++) {
    var items = sections[s].items
    for (var i = 0; i < items.length; i++) if (!items[i].isCompleted) n++
  }
  return n
}

function completedCount(lines) {
  var sections = parse(lines)
  var n = 0
  for (var s = 0; s < sections.length; s++) {
    var items = sections[s].items
    for (var i = 0; i < items.length; i++) if (items[i].isCompleted) n++
  }
  return n
}

function defaultAddSection(lines) {
  var i
  for (i = 0; i < lines.length; i++) {
    var trimmed = trim(lines[i])
    if (isSectionHeader(trimmed)) break
    if (isTodoLine(lines[i])) return "To-Dos"
  }
  for (i = 0; i < lines.length; i++) {
    trimmed = trim(lines[i])
    if (isSectionHeader(trimmed)) return sectionTitle(trimmed)
  }
  return "To-Dos"
}

function hasSection(lines, title) {
  if (title === "To-Dos") {
    var sawTodoBeforeHeader = false
    var sawHeader = false
    for (var i = 0; i < lines.length; i++) {
      var t = trim(lines[i])
      if (isSectionHeader(t)) {
        sawHeader = true
        break
      }
      if (isTodoLine(lines[i])) sawTodoBeforeHeader = true
    }
    if (sawTodoBeforeHeader || !sawHeader) return true
  }
  for (var j = 0; j < lines.length; j++) {
    var header = trim(lines[j])
    if (isSectionHeader(header) && sectionTitle(header) === title) return true
  }
  return false
}

function resolveLineIndex(lines, text, section, hint, isCompleted) {
  if (hint >= 0 && hint < lines.length) {
    var line = lines[hint]
    if (isTodoLine(line) && todoText(line) === text && isCompletedTodoLine(line) === isCompleted)
      return hint
  }
  var current = "To-Dos"
  for (var offset = 0; offset < lines.length; offset++) {
    var trimmed = trim(lines[offset])
    if (isSectionHeader(trimmed)) {
      current = sectionTitle(trimmed)
      continue
    }
    if (current !== section) continue
    if (!isTodoLine(lines[offset]) || todoText(lines[offset]) !== text) continue
    if (isCompletedTodoLine(lines[offset]) === isCompleted) return offset
  }
  for (var i = 0; i < lines.length; i++) {
    if (isTodoLine(lines[i]) && todoText(lines[i]) === text) return i
  }
  return -1
}

function insertIndex(lines, sectionTitleName, completed, prepend) {
  var current = "To-Dos"
  var firstOpen = -1
  var lastOpen = -1
  var lastTodo = -1
  var firstCompleted = -1
  var headerIndex = -1
  var sectionEnd = -1
  var sawExplicitHeader = false

  for (var offset = 0; offset < lines.length; offset++) {
    var line = lines[offset]
    var trimmed = trim(line)
    if (isSectionHeader(trimmed)) {
      var title = sectionTitle(trimmed)
      if (current === sectionTitleName && sectionEnd < 0) sectionEnd = offset
      current = title
      sawExplicitHeader = true
      if (current === sectionTitleName) {
        headerIndex = offset
        firstOpen = -1
        lastOpen = -1
        lastTodo = -1
        firstCompleted = -1
        sectionEnd = -1
      }
      continue
    }

    var inSection = false
    if (sectionTitleName === "To-Dos" && !sawExplicitHeader) inSection = true
    else if (current === sectionTitleName) inSection = true
    if (!inSection || !isTodoLine(line)) continue

    lastTodo = offset
    if (isCompletedTodoLine(line)) {
      if (firstCompleted < 0) firstCompleted = offset
    } else {
      if (firstOpen < 0) firstOpen = offset
      lastOpen = offset
    }
  }

  if (completed) {
    if (lastTodo >= 0) return lastTodo + 1
    if (headerIndex >= 0) return headerIndex + 1
    if (sectionEnd >= 0) return sectionEnd
    return lines.length
  }

  if (prepend) {
    if (firstOpen >= 0) return firstOpen
    if (firstCompleted >= 0) return firstCompleted
    if (headerIndex >= 0) return headerIndex + 1
    if (sectionTitleName === "To-Dos") {
      var i = 0
      while (i < lines.length) {
        var t = trim(lines[i])
        if (isSectionHeader(t)) return i
        if (t.indexOf("#") === 0 || t.length === 0) {
          i++
          continue
        }
        return i
      }
    }
    if (sectionEnd >= 0) return sectionEnd
    return 0
  }

  if (lastOpen >= 0) return lastOpen + 1
  if (firstCompleted >= 0) return firstCompleted
  if (headerIndex >= 0) return headerIndex + 1
  if (sectionEnd >= 0) return sectionEnd
  return lines.length
}

function addItem(lines, text, sectionTitleName) {
  var next = lines.slice()
  var trimmed = trim(text)
  if (trimmed.length === 0) error("emptyText")

  var target = sectionTitleName || defaultAddSection(next)
  var newLine = formatTodoLine("", trimmed, false)
  var hasTodos = false
  for (var i = 0; i < next.length; i++) if (isTodoLine(next[i])) { hasTodos = true; break }

  if (hasSection(next, target) || (target === "To-Dos" && hasTodos)) {
    var at = insertIndex(next, target, false, true)
    next.splice(at, 0, newLine)
    return { lines: next, index: at }
  }

  if (next.length === 0 || (next.length === 1 && next[0].length === 0)) {
    next = ["## " + target, "", newLine]
    return { lines: next, index: 2 }
  }

  var insertAt = 0
  if (next.length > 0 && trim(next[0]).indexOf("#") === 0) {
    insertAt = 1
    while (insertAt < next.length && trim(next[insertAt]).length === 0) insertAt++
  }
  var block = ["## " + target, newLine, ""]
  for (var b = 0; b < block.length; b++) next.splice(insertAt + b, 0, block[b])
  return { lines: next, index: insertAt + 1 }
}

function toggleComplete(lines, text, section, hint, wasCompleted) {
  var next = lines.slice()
  var idx = resolveLineIndex(next, text, section, hint, wasCompleted)
  if (idx < 0) error("notFound")
  var line = next[idx]
  if (!isTodoLine(line) || todoText(line) !== text) error("invalidLine")
  var indent = leadingWhitespace(line)
  var markCompleted = !isCompletedTodoLine(line)
  next.splice(idx, 1)

  if (markCompleted) {
    next.push(formatTodoLine(indent, text, true))
  } else {
    var openLine = formatTodoLine(indent, text, false)
    var target = defaultAddSection(next)
    var hasTodos = false
    for (var i = 0; i < next.length; i++) if (isTodoLine(next[i])) { hasTodos = true; break }
    if (hasSection(next, target) || (target === "To-Dos" && hasTodos)) {
      var at = insertIndex(next, target, false, true)
      next.splice(Math.min(at, next.length), 0, openLine)
    } else {
      next.splice(0, 0, openLine)
    }
  }
  return { lines: next, completed: markCompleted }
}

function updateItem(lines, oldText, section, hint, isCompleted, newText) {
  var next = lines.slice()
  var trimmed = trim(newText)
  if (trimmed.length === 0) error("emptyText")
  if (trimmed === oldText) return { lines: next }
  var idx = resolveLineIndex(next, oldText, section, hint, isCompleted)
  if (idx < 0) error("notFound")
  var line = next[idx]
  if (!isTodoLine(line) || todoText(line) !== oldText) error("invalidLine")
  next[idx] = formatTodoLine(leadingWhitespace(line), trimmed, isCompleted)
  return { lines: next }
}

function deleteItem(lines, text, section, hint, isCompleted) {
  var next = lines.slice()
  var idx = resolveLineIndex(next, text, section, hint, isCompleted)
  if (idx < 0) error("notFound")
  var line = next[idx]
  if (!isTodoLine(line) || todoText(line) !== text) error("invalidLine")
  next.splice(idx, 1)
  if (idx < next.length && trim(next[idx]).length === 0) {
    var prevBlank = idx > 0 && trim(next[idx - 1]).length === 0
    if (prevBlank) next.splice(idx, 1)
  }
  return { lines: next }
}

function moveItems(items, sourceIndexes, destination) {
  var moving = []
  var sorted = sourceIndexes.slice().sort(function (a, b) { return a - b })
  var i
  for (i = 0; i < sorted.length; i++) moving.push(items[sorted[i]])
  var next = items.slice()
  for (i = sorted.length - 1; i >= 0; i--) next.splice(sorted[i], 1)
  var dest = Math.min(Math.max(destination, 0), next.length)
  for (i = 0; i < moving.length; i++) next.splice(dest + i, 0, moving[i])
  return next
}

function moveOpenItems(lines, sectionTitleName, sourceIndexes, destination) {
  var next = lines.slice()
  var sections = parse(next)
  var section = null
  var s
  for (s = 0; s < sections.length; s++) {
    if (sections[s].title === sectionTitleName) { section = sections[s]; break }
  }
  if (!section) error("notFound")
  var open = []
  for (s = 0; s < section.items.length; s++) {
    if (!section.items[s].isCompleted) open.push(section.items[s])
  }
  if (open.length === 0 || !sourceIndexes || sourceIndexes.length === 0) return { lines: next }
  open = moveItems(open, sourceIndexes, destination)

  var slots = []
  for (s = 0; s < section.items.length; s++) {
    if (!section.items[s].isCompleted) slots.push(section.items[s].lineIndex)
  }
  slots.sort(function (a, b) { return a - b })
  if (slots.length !== open.length) error("invalidLine")

  for (s = 0; s < slots.length; s++) {
    var slot = slots[s]
    if (slot >= next.length || !isTodoLine(next[slot])) error("invalidLine")
    next[slot] = formatTodoLine(leadingWhitespace(next[slot]), open[s].text, false)
  }
  return { lines: next }
}

function moveOpenItem(lines, item, direction) {
  if (!item || item.isCompleted) return { lines: lines.slice() }
  var sections = parse(lines)
  var section = null
  for (var s = 0; s < sections.length; s++) {
    if (sections[s].title === item.section) { section = sections[s]; break }
  }
  if (!section) return { lines: lines.slice() }
  var open = []
  for (var i = 0; i < section.items.length; i++) {
    if (!section.items[i].isCompleted) open.push(section.items[i])
  }
  var idx = -1
  for (i = 0; i < open.length; i++) if (open[i].id === item.id) { idx = i; break }
  if (idx < 0) return { lines: lines.slice() }
  var dest = idx + direction
  if (dest < 0 || dest >= open.length) return { lines: lines.slice() }
  return moveOpenItems(lines, item.section, [idx], dest)
}

function commitMessage(prefix, text) {
  var oneLine = String(text || "").replace(/\n/g, " ")
  var clipped = oneLine.length > 60 ? oneLine.slice(0, 57) + "..." : oneLine
  return prefix + " " + clipped
}

function todayHeader(date) {
  var d = date || new Date()
  var mm = d.getMonth() + 1
  var dd = d.getDate()
  var yy = d.getFullYear() % 100
  function pad(n) { return n < 10 ? "0" + n : String(n) }
  return pad(mm) + "/" + pad(dd) + "/" + pad(yy)
}

function insertChangelogEntry(content, dateHeader, entryLine) {
  var normalized = String(content || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n")
  var lines = normalized.split("\n")
  var idx = -1
  var i
  for (i = 0; i < lines.length; i++) {
    if (trim(lines[i]) === dateHeader) { idx = i; break }
  }
  if (idx >= 0) {
    var insertAt = idx + 1
    if (insertAt < lines.length && trim(lines[insertAt]).length === 0) insertAt++
    lines.splice(insertAt, 0, entryLine)
    var s = lines.join("\n")
    if (s.charAt(s.length - 1) !== "\n") s += "\n"
    return s
  }
  return [dateHeader, "", entryLine, ""].concat(lines).join("\n")
}

function defaultTitle(path) {
  var cleaned = String(path || "").replace(/\/+$/, "")
  var parts = cleaned.split("/")
  var file = parts.length ? parts[parts.length - 1] : cleaned
  var base = file.replace(/\.md$/i, "")
  var lower = base.toLowerCase()
  if (lower === "todo" || lower === "todos" || lower === "to-do") {
    return parts.length >= 2 ? parts[parts.length - 2] : base
  }
  return base
}

function defaultTodosPath(home, existsFn) {
  var candidates = [home + "/todos.md", home + "/Documents/todos.md"]
  for (var i = 0; i < candidates.length; i++) {
    if (existsFn && existsFn(candidates[i])) return candidates[i]
  }
  return candidates[0]
}

function filterSections(sections, query, showCompleted) {
  var q = trim(query)
  var out = []
  for (var s = 0; s < (sections || []).length; s++) {
    var section = sections[s]
    var items = []
    for (var i = 0; i < section.items.length; i++) {
      var item = section.items[i]
      if (!showCompleted && item.isCompleted) continue
      if (q.length > 0) {
        var hay = (item.text + " " + section.title).toLowerCase()
        if (hay.indexOf(q.toLowerCase()) < 0) continue
      }
      items.push(item)
    }
    if (items.length === 0) continue
    out.push({ id: section.id, title: section.title, items: items })
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    fromText: fromText,
    toText: toText,
    parse: parse,
    openCount: openCount,
    completedCount: completedCount,
    defaultAddSection: defaultAddSection,
    isSectionHeader: isSectionHeader,
    sectionTitle: sectionTitle,
    isTodoLine: isTodoLine,
    isCompletedTodoLine: isCompletedTodoLine,
    todoText: todoText,
    leadingWhitespace: leadingWhitespace,
    formatTodoLine: formatTodoLine,
    insertIndex: insertIndex,
    addItem: addItem,
    toggleComplete: toggleComplete,
    updateItem: updateItem,
    deleteItem: deleteItem,
    moveItems: moveItems,
    moveOpenItems: moveOpenItems,
    moveOpenItem: moveOpenItem,
    commitMessage: commitMessage,
    todayHeader: todayHeader,
    insertChangelogEntry: insertChangelogEntry,
    defaultTitle: defaultTitle,
    defaultTodosPath: defaultTodosPath,
    filterSections: filterSections
  }
}
