"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const path = require("path")

const repoDoc = path.join(__dirname, "..", "TodoDocument.js")
const Doc = require(repoDoc)

function sectionTodoLines(lines, section) {
  let current = "To-Dos"
  const out = []
  for (const line of lines) {
    const t = line.trim()
    if (Doc.isSectionHeader(t)) {
      current = Doc.sectionTitle(t)
      continue
    }
    if (current === section && Doc.isTodoLine(line)) out.push(line)
  }
  return out
}

test("tests require the repo document module", () => {
  assert.equal(require.resolve(repoDoc), path.resolve(repoDoc))
})

test("parse groups sections, strips [x], keeps open before done", () => {
  const lines = Doc.fromText(`# Title

- open one
- [x] done one
## Section A
- alpha
\t- nested
- [X] done A
##video idea
- clip
`)
  const sections = Doc.parse(lines)
  assert.ok(sections.length >= 3)
  const root = sections.find((s) => s.title === "To-Dos")
  assert.equal(root.items.length, 2)
  assert.equal(root.items[0].isCompleted, false)
  assert.equal(root.items[1].isCompleted, true)
  assert.equal(root.items[1].text, "done one")
  assert.ok(sections.some((s) => s.title === "video idea"))
  assert.equal(Doc.formatTodoLine("", "x", false), "- x")
  assert.equal(Doc.formatTodoLine("  ", "x", true), "  - [x] x")
  assert.equal(Doc.openCount(lines), 4)
  assert.equal(Doc.completedCount(lines), 2)
})

test("add prepends to the pre-header To-Dos section", () => {
  let lines = Doc.fromText(`# To-Do 28

- first loose
- second loose
## THOUGHTS
- thought
## Archive
- buried
- [x] archive done
`)
  assert.equal(Doc.defaultAddSection(lines), "To-Dos")
  lines = Doc.addItem(lines, "NEW ITEM").lines
  const openTop = Doc.parse(lines).find((s) => s.title === "To-Dos").items.filter((i) => !i.isCompleted).map((i) => i.text)
  assert.equal(openTop[0], "NEW ITEM")
  const todoLines = lines.filter((l) => Doc.isTodoLine(l))
  assert.equal(Doc.todoText(todoLines[0]), "NEW ITEM")
  assert.equal(Doc.toText(lines).includes("## Archive\n- NEW ITEM"), false)
})

test("add prepends at the top of a section open block", () => {
  let lines = Doc.fromText(`## S
- open
- [x] done1
- [x] done2
`)
  lines = Doc.addItem(lines, "fresh", "S").lines
  const todoLines = lines.filter((l) => Doc.isTodoLine(l))
  assert.equal(Doc.isCompletedTodoLine(todoLines[0]), false)
  assert.equal(Doc.todoText(todoLines[0]), "fresh")
  assert.equal(Doc.todoText(todoLines[1]), "open")
  assert.equal(Doc.isCompletedTodoLine(todoLines[2]), true)
})

test("complete appends the done line at EOF", () => {
  let lines = Doc.fromText(`# Title
- top item
## THOUGHTS
- thought
## Next
- other
## YC
- last open
`)
  const item = Doc.parse(lines).flatMap((s) => s.items).find((i) => i.text === "thought")
  const result = Doc.toggleComplete(lines, item.text, item.section, item.lineIndex, false)
  lines = result.lines
  assert.equal(result.completed, true)
  const beforeLast = lines.slice(0, -1)
  assert.equal(beforeLast.some((l) => Doc.todoText(l) === "thought"), false)
  const last = [...lines].reverse().find((l) => l.trim().length > 0)
  assert.equal(Doc.isCompletedTodoLine(last), true)
  assert.equal(Doc.todoText(last), "thought")
  const text = Doc.toText(lines)
  assert.ok(text.includes("## YC"))
  assert.ok(text.includes("- last open"))
  assert.equal(Doc.openCount(lines), 3)
})

test("complete keeps the id of a unique title", () => {
  let lines = Doc.fromText("## S\n- alpha\n- beta\n")
  const before = Doc.parse(lines).flatMap((s) => s.items).find((i) => i.text === "alpha")
  lines = Doc.toggleComplete(lines, before.text, before.section, before.lineIndex, false).lines
  const after = Doc.parse(lines).flatMap((s) => s.items).find((i) => i.text === "alpha")
  assert.equal(before.isCompleted, false)
  assert.equal(after.isCompleted, true)
  assert.equal(after.id, before.id)
  assert.equal(after.id, "S:1:alpha")
})

test("reopen moves the item to the top of the open list", () => {
  let lines = [
    "## S",
    "- live",
    "- [x] doneB",
    "- [x] doneA"
  ]
  const item = Doc.parse(lines).flatMap((s) => s.items).find((i) => i.text === "doneA" && i.isCompleted)
  lines = Doc.toggleComplete(lines, item.text, item.section, item.lineIndex, true).lines
  const parsed = Doc.parse(lines).flatMap((s) => s.items)
  assert.ok(parsed.some((i) => i.text === "doneA" && !i.isCompleted))
  const openTop = parsed.filter((i) => !i.isCompleted).map((i) => i.text)
  assert.equal(openTop[0], "doneA")
  assert.ok(Doc.toText(lines).includes("- [x] doneB"))
})

test("edit preserves open vs completed state", () => {
  let lines = Doc.fromText(`## S
- hello
- [x] bye
`)
  const open = Doc.parse(lines).flatMap((s) => s.items).find((i) => i.text === "hello")
  lines = Doc.updateItem(lines, "hello", "S", open.lineIndex, false, "hello world").lines
  assert.ok(Doc.toText(lines).includes("- hello world"))
  assert.ok(Doc.parse(lines).flatMap((s) => s.items).some((i) => i.text === "hello world" && !i.isCompleted))

  const done = Doc.parse(lines).flatMap((s) => s.items).find((i) => i.text === "bye")
  lines = Doc.updateItem(lines, "bye", "S", done.lineIndex, true, "bye now").lines
  assert.ok(lines.some((l) => l.includes("[x]") && l.includes("bye now")))
})

test("delete removes the matching line", () => {
  let lines = Doc.fromText(`## S
- keep
- drop me
- [x] done
`)
  const drop = Doc.parse(lines).flatMap((s) => s.items).find((i) => i.text === "drop me")
  lines = Doc.deleteItem(lines, drop.text, drop.section, drop.lineIndex, false).lines
  assert.equal(Doc.toText(lines).includes("drop me"), false)
  assert.ok(Doc.toText(lines).includes("- keep"))
  assert.ok(Doc.toText(lines).includes("- [x] done"))
  assert.equal(Doc.openCount(lines), 1)

  const done = Doc.parse(lines).flatMap((s) => s.items).find((i) => i.text === "done" && i.isCompleted)
  lines = Doc.deleteItem(lines, done.text, done.section, done.lineIndex, true).lines
  assert.equal(Doc.toText(lines).includes("[x] done"), false)
  assert.equal(Doc.completedCount(lines), 0)
})

test("reorder moves open items only", () => {
  let lines = Doc.fromText(`## S
- a
- b
- c
- [x] z
`)
  lines = Doc.moveOpenItems(lines, "S", [0], 3).lines
  const open = Doc.parse(lines).find((s) => s.title === "S").items.filter((i) => !i.isCompleted).map((i) => i.text)
  assert.deepEqual(open, ["b", "c", "a"])
  assert.equal(Doc.parse(lines).find((s) => s.title === "S").items.at(-1).text, "z")
})

test("insertIndex prepends open items in Mid before completed", () => {
  const lines = Doc.fromText(`- loose
## Mid
- m1
- [x] md
## End
- e1
`)
  assert.equal(Doc.insertIndex(lines, "Mid", false, false), 3)
  const added = Doc.addItem(lines, "x", "Mid").lines
  assert.deepEqual(sectionTodoLines(added, "Mid").map(Doc.todoText), ["x", "m1", "md"])
})

test("empty add throws", () => {
  assert.throws(() => Doc.addItem([], "   "), (err) => err.code === "emptyText")
})

test("commitMessage clips to 60 and stays one line", () => {
  assert.equal(Doc.commitMessage("Add", "short"), "Add short")
  assert.equal(Doc.commitMessage("Edit", "a\nb"), "Edit a b")
  const long = "x".repeat(80)
  const msg = Doc.commitMessage("Complete", long)
  assert.ok(msg.length <= "Complete ".length + 60)
  assert.ok(msg.endsWith("..."))
})

test("changelog inserts under today's header or prepends a block", () => {
  const withHeader = Doc.insertChangelogEntry("01/02/26\n\n  old\n", "01/02/26", "  new")
  assert.ok(withHeader.indexOf("  new") < withHeader.indexOf("  old"))
  const fresh = Doc.insertChangelogEntry("# Log\n", "08/30/26", "  shipped")
  assert.ok(fresh.startsWith("08/30/26\n\n  shipped\n"))
})

test("tabTitle capitalizes each word", () => {
  assert.equal(Doc.tabTitle("books"), "Books")
  assert.equal(Doc.tabTitle("Todos"), "Todos")
  assert.equal(Doc.tabTitle("my list"), "My List")
  assert.equal(Doc.tabTitle("  deals  "), "Deals")
})

test("defaultTitle uses parent folder for todos.md", () => {
  assert.equal(Doc.defaultTitle("/home/user/todos.md"), "user")
  assert.equal(Doc.defaultTitle("/home/user/marketing/todo.md"), "marketing")
  assert.equal(Doc.defaultTitle("/home/user/books.md"), "books")
})

test("defaultTodosPath prefers an existing ~/todos.md", () => {
  const home = "/home/user"
  assert.equal(Doc.defaultTodosPath(home, (p) => p === home + "/todos.md"), home + "/todos.md")
  assert.equal(Doc.defaultTodosPath(home, (p) => p === home + "/Documents/todos.md"), home + "/Documents/todos.md")
  assert.equal(Doc.defaultTodosPath(home, () => false), home + "/todos.md")
})

test("filterSections hides completed and matches query", () => {
  const sections = Doc.parse(Doc.fromText(`## S
- alpha
- [x] done
## Other
- beta
`))
  const open = Doc.filterSections(sections, "", false)
  assert.equal(open.length, 2)
  assert.equal(open[0].items.length, 1)
  const shown = Doc.filterSections(sections, "", true)
  assert.equal(shown[0].items.length, 2)
  const q = Doc.filterSections(sections, "oth", false)
  assert.equal(q.length, 1)
  assert.equal(q[0].title, "Other")
  const kept = Doc.filterSections(sections, "", false, shown[0].items[1].id)
  assert.equal(kept[0].items.length, 2)
})

const STATUS_DOC = `# To-Do 4



# TODAY
- [ ] Ship it #1 [now] due:2026-11-12
  - [ ] Sub task #2



# IN PROGRESS



# LATER
- [ ] Later one #3
- [ ] Later two #4



# DETAILS: IN PROGRESS

- [ ] Ship it #1 [now] due:2026-11-12
  - Notes line
  - [ ] Sub task #2
    - Deeper note

# DETAILS: LATER

- [ ] Later one #3
  - Why it matters
## Money first
- plain bullet note

# Revenue picture
- Net: down
`

test("status layout: # headers are sections, DETAILS and plain bullets hidden", () => {
  const lines = Doc.fromText(STATUS_DOC)
  assert.equal(Doc.detectFormat(lines).status, true)
  const sections = Doc.parse(lines)
  assert.deepEqual(sections.map((s) => s.title), ["TODAY", "LATER"])
  assert.deepEqual(sections[0].items.map((i) => [i.text, i.indent]), [
    ["Ship it #1 [now] due:2026-11-12", 0],
    ["Sub task #2", 2]
  ])
  assert.deepEqual(sections[1].items.map((i) => i.text), ["Later one #3", "Later two #4"])
  assert.equal(Doc.openCount(lines), 4)
})

test("status layout: add goes to top of LATER as a checkbox and bumps the title count", () => {
  const lines = Doc.fromText(STATUS_DOC)
  assert.equal(Doc.defaultAddSection(lines), "LATER")
  const out = Doc.addItem(lines, "Fresh idea").lines
  assert.equal(out[0], "# To-Do 5")
  assert.equal(out[out.indexOf("# LATER") + 1], "- [ ] Fresh idea")
})

test("status layout: complete marks in place, syncs the DETAILS copy, reopen restores", () => {
  const lines = Doc.fromText(STATUS_DOC)
  const done = Doc.toggleComplete(lines, "Later one #3", "LATER", -1, false)
  assert.equal(done.completed, true)
  assert.equal(done.lines[0], "# To-Do 3")
  assert.equal(done.lines.filter((l) => l === "- [x] Later one #3").length, 2)
  assert.equal(done.lines.length, lines.length)
  const back = Doc.toggleComplete(done.lines, "Later one #3", "LATER", -1, true)
  assert.equal(Doc.toText(back.lines), Doc.toText(lines))
})

test("status layout: edit renames both copies and keeps the checkbox", () => {
  const lines = Doc.fromText(STATUS_DOC)
  const out = Doc.updateItem(lines, "Sub task #2", "TODAY", -1, false, "Sub task renamed #2").lines
  assert.equal(out.filter((l) => l === "  - [ ] Sub task renamed #2").length, 2)
  assert.equal(out.includes("    - Deeper note"), true)
})

test("status layout: delete removes the list line only and bumps the count", () => {
  const lines = Doc.fromText(STATUS_DOC)
  const out = Doc.deleteItem(lines, "Later two #4", "LATER", -1, false).lines
  assert.equal(out[0], "# To-Do 3")
  assert.equal(out.some((l) => l.includes("Later two")), false)
  assert.equal(out.includes("  - Why it matters"), true)
})

test("status layout: reorder keeps checkboxes", () => {
  const lines = Doc.fromText(STATUS_DOC)
  const out = Doc.moveOpenItems(lines, "LATER", [1], 0).lines
  const i = out.indexOf("# LATER")
  assert.deepEqual(out.slice(i + 1, i + 3), ["- [ ] Later two #4", "- [ ] Later one #3"])
})

test("plain layout keeps a single # title out of sections and edits keep [ ]", () => {
  const lines = Doc.fromText("# Title\n\n## A\n- [ ] boxed\n- plain\n")
  assert.equal(Doc.detectFormat(lines).status, false)
  assert.deepEqual(Doc.parse(lines).map((s) => s.title), ["A"])
  const out = Doc.updateItem(lines, "boxed", "A", -1, false, "boxed 2").lines
  assert.equal(out[3], "- [ ] boxed 2")
})
