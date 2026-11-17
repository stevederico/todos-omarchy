// Pure markdown todo mutations. Panel.qml imports this; Node tests require
// the same file. No I/O, no git, no QML types.

function fromText(text) {
  const raw = String(text || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n")
  return raw.split("\n")
}

function toText(lines) {
  let body = (lines || []).join("\n")
  if (body.length === 0 || body.charAt(body.length - 1) !== "\n") body += "\n"
  return body
}

function trim(s) {
  return String(s || "").replace(/^\s+|\s+$/g, "")
}

function error(code) {
  const messages = {
    emptyText: "Empty to-do text",
    notFound: "Item out of date — refresh and try again",
    invalidLine: "File changed under us — refresh and try again"
  }
  const err = new Error(messages[code] || code)
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

function isCheckboxLine(line) {
  return /^[\t ]*-\s+\[[xX ]\](\s|$)/.test(line)
}

function isOpenCheckboxLine(line) {
  return /^[\t ]*-\s+\[ \](\s|$)/.test(line)
}

function todoText(line) {
  const dash = line.match(/^[\t ]*-\s+/)
  if (!dash) return ""
  let rest = line.slice(dash[0].length)
  const box = rest.match(/^\[[xX ]\]\s*/)
  if (box) rest = rest.slice(box[0].length)
  return trim(rest)
}

function leadingWhitespace(line) {
  let i = 0
  while (i < line.length && (line.charAt(i) === " " || line.charAt(i) === "\t")) i++
  return line.slice(0, i)
}

function formatTodoLine(indent, text, completed, checkbox) {
  if (completed) return (indent || "") + "- [x] " + text
  return (indent || "") + (checkbox ? "- [ ] " : "- ") + text
}

// Two layouts share this module.
// Plain: optional "# Title", "## Section" groups, "- item" open, "- [x] item" done.
// Status: two or more "# HEADER" lines (e.g. "# TODAY", "# LATER"). Only
// "- [ ]" / "- [x]" lines are items, "# DETAILS…" sections repeat items with
// notes and stay hidden, and a leading "# To-Do 22" title keeps the open count.
function isStatusHeader(trimmed) {
  return /^#\s+\S/.test(trimmed)
}

function detectFormat(lines) {
  let count = 0
  let i
  for (i = 0; i < lines.length; i++) if (isStatusHeader(trim(lines[i]))) count++
  if (count < 2) return { status: false, titleIndex: -1 }
  let titleIndex = -1
  for (i = 0; i < lines.length; i++) {
    if (trim(lines[i]).length === 0) continue
    if (!isStatusHeader(trim(lines[i]))) break
    let j = i + 1
    while (j < lines.length && trim(lines[j]).length === 0) j++
    if (j >= lines.length || isStatusHeader(trim(lines[j]))) titleIndex = i
    break
  }
  return { status: true, titleIndex: titleIndex }
}

function headerTitle(lines, offset, fmt) {
  const trimmed = trim(lines[offset])
  if (!fmt.status) return isSectionHeader(trimmed) ? sectionTitle(trimmed) : null
  if (offset === fmt.titleIndex || !isStatusHeader(trimmed)) return null
  return trim(trimmed.slice(1))
}

function isItemLine(line, fmt) {
  if (!fmt.status) return isTodoLine(line)
  return isCheckboxLine(line) && todoText(line).length > 0
}

function isHiddenSection(title, fmt) {
  return fmt.status && /^details\b/i.test(String(title || ""))
}

function sectionOfLines(lines, fmt) {
  let current = "To-Dos"
  const out = []
  for (let offset = 0; offset < lines.length; offset++) {
    const title = headerTitle(lines, offset, fmt)
    if (title !== null) {
      current = title
      out.push(null)
    } else {
      out.push(current)
    }
  }
  return out
}

function makeItem(offset, body, section, indent, done, ordinal) {
  return {
    id: section + ":" + String(ordinal || 1) + ":" + body,
    text: body,
    section: section,
    lineIndex: offset,
    indent: indent,
    isCompleted: done
  }
}

function parse(lines) {
  const fmt = detectFormat(lines)
  let currentTitle = "To-Dos"
  const buckets = []
  const index = {}
  const ordinals = {}

  function ensureSection(title) {
    if (Object.prototype.hasOwnProperty.call(index, title)) return index[title]
    buckets.push({ title: title, items: [] })
    const i = buckets.length - 1
    index[title] = i
    return i
  }

  for (let offset = 0; offset < lines.length; offset++) {
    const line = lines[offset]
    const header = headerTitle(lines, offset, fmt)
    if (header !== null) {
      currentTitle = header
      if (!isHiddenSection(currentTitle, fmt)) ensureSection(currentTitle)
      continue
    }
    if (isHiddenSection(currentTitle, fmt)) continue
    if (!isItemLine(line, fmt)) continue
    const body = todoText(line)
    if (body.length === 0) continue
    const done = isCompletedTodoLine(line)
    const si = ensureSection(currentTitle)
    const key = currentTitle + "\0" + body
    ordinals[key] = (ordinals[key] || 0) + 1
    buckets[si].items.push(makeItem(offset, body, currentTitle, leadingWhitespace(line).length, done, ordinals[key]))
  }

  const out = []
  for (let b = 0; b < buckets.length; b++) {
    const open = []
    const doneItems = []
    const items = buckets[b].items
    for (let i = 0; i < items.length; i++) {
      if (items[i].isCompleted) doneItems.push(items[i])
      else open.push(items[i])
    }
    const combined = open.concat(doneItems)
    if (combined.length === 0) continue
    out.push({ id: buckets[b].title, title: buckets[b].title, items: combined })
  }
  return out
}

function openCount(lines) {
  const sections = parse(lines)
  let n = 0
  for (let s = 0; s < sections.length; s++) {
    const items = sections[s].items
    for (let i = 0; i < items.length; i++) if (!items[i].isCompleted) n++
  }
  return n
}

function completedCount(lines) {
  const sections = parse(lines)
  let n = 0
  for (let s = 0; s < sections.length; s++) {
    const items = sections[s].items
    for (let i = 0; i < items.length; i++) if (items[i].isCompleted) n++
  }
  return n
}

// Status layout: keep "# To-Do 22" equal to the open count.
function syncTitleCount(lines) {
  const fmt = detectFormat(lines)
  if (fmt.titleIndex < 0) return lines
  const m = lines[fmt.titleIndex].match(/^(\s*#\s+.*\S\s+)(\d+)(\s*)$/)
  if (!m) return lines
  lines[fmt.titleIndex] = m[1] + String(openCount(lines)) + m[3]
  return lines
}

function defaultAddSection(lines) {
  const fmt = detectFormat(lines)
  let i
  let title
  if (fmt.status) {
    let first = null
    for (i = 0; i < lines.length; i++) {
      title = headerTitle(lines, i, fmt)
      if (title === null || isHiddenSection(title, fmt)) continue
      if (title.toUpperCase() === "LATER") return title
      if (first === null) first = title
    }
    return first === null ? "To-Dos" : first
  }
  for (i = 0; i < lines.length; i++) {
    if (headerTitle(lines, i, fmt) !== null) break
    if (isItemLine(lines[i], fmt)) return "To-Dos"
  }
  for (i = 0; i < lines.length; i++) {
    title = headerTitle(lines, i, fmt)
    if (title !== null) return title
  }
  return "To-Dos"
}

function hasSection(lines, title) {
  const fmt = detectFormat(lines)
  if (title === "To-Dos") {
    let sawTodoBeforeHeader = false
    let sawHeader = false
    for (let i = 0; i < lines.length; i++) {
      if (headerTitle(lines, i, fmt) !== null) {
        sawHeader = true
        break
      }
      if (isItemLine(lines[i], fmt)) sawTodoBeforeHeader = true
    }
    if (sawTodoBeforeHeader || !sawHeader) return true
  }
  for (let j = 0; j < lines.length; j++) {
    if (headerTitle(lines, j, fmt) === title) return true
  }
  return false
}

function resolveLineIndex(lines, text, section, hint, isCompleted) {
  const fmt = detectFormat(lines)
  const owners = sectionOfLines(lines, fmt)
  function matches(i) {
    return owners[i] !== null && !isHiddenSection(owners[i], fmt) &&
      isItemLine(lines[i], fmt) && todoText(lines[i]) === text
  }
  if (hint >= 0 && hint < lines.length && matches(hint) && isCompletedTodoLine(lines[hint]) === isCompleted)
    return hint
  let offset
  for (offset = 0; offset < lines.length; offset++) {
    if (owners[offset] !== section || !matches(offset)) continue
    if (isCompletedTodoLine(lines[offset]) === isCompleted) return offset
  }
  for (offset = 0; offset < lines.length; offset++) if (matches(offset)) return offset
  return -1
}

function insertIndex(lines, sectionTitleName, completed, prepend) {
  const fmt = detectFormat(lines)
  let current = "To-Dos"
  let firstOpen = -1
  let lastOpen = -1
  let lastTodo = -1
  let firstCompleted = -1
  let headerIndex = -1
  let sectionEnd = -1
  let sawExplicitHeader = false

  for (let offset = 0; offset < lines.length; offset++) {
    const line = lines[offset]
    const title = headerTitle(lines, offset, fmt)
    if (title !== null) {
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

    let inSection = false
    if (sectionTitleName === "To-Dos" && !sawExplicitHeader) inSection = true
    else if (current === sectionTitleName) inSection = true
    if (!inSection || !isItemLine(line, fmt)) continue

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
      let i = 0
      while (i < lines.length) {
        if (headerTitle(lines, i, fmt) !== null) return i
        const t = trim(lines[i])
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
  let next = lines.slice()
  const trimmed = trim(text)
  if (trimmed.length === 0) error("emptyText")

  const fmt = detectFormat(next)
  const target = sectionTitleName || defaultAddSection(next)
  const newLine = formatTodoLine("", trimmed, false, fmt.status)
  let hasTodos = false
  for (let i = 0; i < next.length; i++) if (isItemLine(next[i], fmt)) { hasTodos = true; break }

  if (hasSection(next, target) || (target === "To-Dos" && hasTodos)) {
    const at = insertIndex(next, target, false, true)
    next.splice(at, 0, newLine)
    return { lines: syncTitleCount(next), index: at }
  }

  const marker = fmt.status ? "# " : "## "
  if (next.length === 0 || (next.length === 1 && next[0].length === 0)) {
    next = [marker + target, "", newLine]
    return { lines: next, index: 2 }
  }

  let insertAt = 0
  if (next.length > 0 && trim(next[0]).indexOf("#") === 0) {
    insertAt = 1
    while (insertAt < next.length && trim(next[insertAt]).length === 0) insertAt++
  }
  const block = [marker + target, newLine, ""]
  for (let b = 0; b < block.length; b++) next.splice(insertAt + b, 0, block[b])
  return { lines: syncTitleCount(next), index: insertAt + 1 }
}

// Status layout: the item's copy in a hidden "# DETAILS…" section follows
// every check and edit so the two never drift apart.
function detailCopies(lines, fmt, text, isCompleted) {
  const out = []
  if (!fmt.status) return out
  const owners = sectionOfLines(lines, fmt)
  for (let i = 0; i < lines.length; i++) {
    if (owners[i] === null || !isHiddenSection(owners[i], fmt)) continue
    if (!isItemLine(lines[i], fmt) || todoText(lines[i]) !== text) continue
    if (isCompletedTodoLine(lines[i]) === isCompleted) out.push(i)
  }
  return out
}

function toggleComplete(lines, text, section, hint, wasCompleted) {
  const next = lines.slice()
  const fmt = detectFormat(next)
  const idx = resolveLineIndex(next, text, section, hint, wasCompleted)
  if (idx < 0) error("notFound")
  const line = next[idx]
  if (!isTodoLine(line) || todoText(line) !== text) error("invalidLine")
  const indent = leadingWhitespace(line)
  const markCompleted = !isCompletedTodoLine(line)

  if (fmt.status) {
    const targets = [idx].concat(detailCopies(next, fmt, text, !markCompleted))
    for (let t = 0; t < targets.length; t++) {
      const at = targets[t]
      next[at] = formatTodoLine(leadingWhitespace(next[at]), text, markCompleted, true)
    }
    return { lines: syncTitleCount(next), completed: markCompleted }
  }

  next.splice(idx, 1)

  if (markCompleted) {
    next.push(formatTodoLine(indent, text, true))
  } else {
    const openLine = formatTodoLine(indent, text, false, isCheckboxLine(line))
    const target = defaultAddSection(next)
    let hasTodos = false
    for (let i = 0; i < next.length; i++) if (isTodoLine(next[i])) { hasTodos = true; break }
    if (hasSection(next, target) || (target === "To-Dos" && hasTodos)) {
      const insertAt = insertIndex(next, target, false, true)
      next.splice(Math.min(insertAt, next.length), 0, openLine)
    } else {
      next.splice(0, 0, openLine)
    }
  }
  return { lines: next, completed: markCompleted }
}

function updateItem(lines, oldText, section, hint, isCompleted, newText) {
  const next = lines.slice()
  const trimmed = trim(newText)
  if (trimmed.length === 0) error("emptyText")
  if (trimmed === oldText) return { lines: next }
  const fmt = detectFormat(next)
  const idx = resolveLineIndex(next, oldText, section, hint, isCompleted)
  if (idx < 0) error("notFound")
  const line = next[idx]
  if (!isTodoLine(line) || todoText(line) !== oldText) error("invalidLine")
  const targets = [idx].concat(detailCopies(next, fmt, oldText, isCompleted))
  for (let t = 0; t < targets.length; t++) {
    const at = targets[t]
    next[at] = formatTodoLine(leadingWhitespace(next[at]), trimmed, isCompleted, fmt.status || isOpenCheckboxLine(next[at]))
  }
  return { lines: next }
}

function deleteItem(lines, text, section, hint, isCompleted) {
  const next = lines.slice()
  const idx = resolveLineIndex(next, text, section, hint, isCompleted)
  if (idx < 0) error("notFound")
  const line = next[idx]
  if (!isTodoLine(line) || todoText(line) !== text) error("invalidLine")
  next.splice(idx, 1)
  if (idx < next.length && trim(next[idx]).length === 0) {
    const prevBlank = idx > 0 && trim(next[idx - 1]).length === 0
    if (prevBlank) next.splice(idx, 1)
  }
  return { lines: syncTitleCount(next) }
}

function moveItems(items, sourceIndexes, destination) {
  const moving = []
  const sorted = sourceIndexes.slice().sort(function (a, b) { return a - b })
  let i
  for (i = 0; i < sorted.length; i++) moving.push(items[sorted[i]])
  const next = items.slice()
  for (i = sorted.length - 1; i >= 0; i--) next.splice(sorted[i], 1)
  const dest = Math.min(Math.max(destination, 0), next.length)
  for (i = 0; i < moving.length; i++) next.splice(dest + i, 0, moving[i])
  return next
}

function moveOpenItems(lines, sectionTitleName, sourceIndexes, destination) {
  const next = lines.slice()
  const sections = parse(next)
  let section = null
  let s
  for (s = 0; s < sections.length; s++) {
    if (sections[s].title === sectionTitleName) { section = sections[s]; break }
  }
  if (!section) error("notFound")
  let open = []
  for (s = 0; s < section.items.length; s++) {
    if (!section.items[s].isCompleted) open.push(section.items[s])
  }
  if (open.length === 0 || !sourceIndexes || sourceIndexes.length === 0) return { lines: next }
  open = moveItems(open, sourceIndexes, destination)

  const slots = []
  for (s = 0; s < section.items.length; s++) {
    if (!section.items[s].isCompleted) slots.push(section.items[s].lineIndex)
  }
  slots.sort(function (a, b) { return a - b })
  if (slots.length !== open.length) error("invalidLine")

  for (s = 0; s < slots.length; s++) {
    const slot = slots[s]
    if (slot >= next.length || !isTodoLine(next[slot])) error("invalidLine")
    next[slot] = formatTodoLine(leadingWhitespace(next[slot]), open[s].text, false, isOpenCheckboxLine(next[slot]))
  }
  return { lines: next }
}

function moveOpenItem(lines, item, direction) {
  if (!item || item.isCompleted) return { lines: lines.slice() }
  const sections = parse(lines)
  let section = null
  for (let s = 0; s < sections.length; s++) {
    if (sections[s].title === item.section) { section = sections[s]; break }
  }
  if (!section) return { lines: lines.slice() }
  const open = []
  for (let i = 0; i < section.items.length; i++) {
    if (!section.items[i].isCompleted) open.push(section.items[i])
  }
  let idx = -1
  for (let i = 0; i < open.length; i++) if (open[i].id === item.id) { idx = i; break }
  if (idx < 0) return { lines: lines.slice() }
  const dest = idx + direction
  if (dest < 0 || dest >= open.length) return { lines: lines.slice() }
  return moveOpenItems(lines, item.section, [idx], dest)
}

function commitMessage(prefix, text) {
  const oneLine = String(text || "").replace(/\n/g, " ")
  const clipped = oneLine.length > 60 ? oneLine.slice(0, 57) + "..." : oneLine
  return prefix + " " + clipped
}

function todayHeader(date) {
  const d = date || new Date()
  const mm = d.getMonth() + 1
  const dd = d.getDate()
  const yy = d.getFullYear() % 100
  function pad(n) { return n < 10 ? "0" + n : String(n) }
  return pad(mm) + "/" + pad(dd) + "/" + pad(yy)
}

function insertChangelogEntry(content, dateHeader, entryLine) {
  const normalized = String(content || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n")
  const lines = normalized.split("\n")
  let idx = -1
  let i
  for (i = 0; i < lines.length; i++) {
    if (trim(lines[i]) === dateHeader) { idx = i; break }
  }
  if (idx >= 0) {
    let insertAt = idx + 1
    if (insertAt < lines.length && trim(lines[insertAt]).length === 0) insertAt++
    lines.splice(insertAt, 0, entryLine)
    let s = lines.join("\n")
    if (s.charAt(s.length - 1) !== "\n") s += "\n"
    return s
  }
  return [dateHeader, "", entryLine, ""].concat(lines).join("\n")
}

function tabTitle(title) {
  const raw = trim(title)
  if (raw.length === 0) return ""
  const parts = raw.split(/\s+/)
  const out = []
  for (let i = 0; i < parts.length; i++) {
    const w = parts[i]
    out.push(w.charAt(0).toUpperCase() + w.slice(1))
  }
  return out.join(" ")
}

function defaultTitle(path) {
  const cleaned = String(path || "").replace(/\/+$/, "")
  const parts = cleaned.split("/")
  const file = parts.length ? parts[parts.length - 1] : cleaned
  const base = file.replace(/\.md$/i, "")
  const lower = base.toLowerCase()
  if (lower === "todo" || lower === "todos" || lower === "to-do") {
    return parts.length >= 2 ? parts[parts.length - 2] : base
  }
  return base
}

function defaultTodosPath(home, existsFn) {
  const candidates = [home + "/todos.md", home + "/Documents/todos.md"]
  for (let i = 0; i < candidates.length; i++) {
    if (existsFn && existsFn(candidates[i])) return candidates[i]
  }
  return candidates[0]
}

function filterSections(sections, query, showCompleted, keepId) {
  const q = trim(query)
  const keep = trim(keepId)
  const out = []
  for (let s = 0; s < (sections || []).length; s++) {
    const section = sections[s]
    const items = []
    for (let i = 0; i < section.items.length; i++) {
      const item = section.items[i]
      const kept = keep && (item.id === keep || item.uid === keep)
      if (!showCompleted && item.isCompleted && !kept) continue
      if (q.length > 0) {
        const hay = (item.text + " " + section.title).toLowerCase()
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
    isCheckboxLine: isCheckboxLine,
    detectFormat: detectFormat,
    syncTitleCount: syncTitleCount,
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
    tabTitle: tabTitle,
    defaultTitle: defaultTitle,
    defaultTodosPath: defaultTodosPath,
    filterSections: filterSections
  }
}
