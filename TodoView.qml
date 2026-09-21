import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TodoDocument.js" as Doc
import "Almanac.js" as Almanac

Item {
  id: root

  property var bar: null
  property bool compact: true
  focus: true

  signal closeRequested()
  signal openWindowRequested()

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/dottie-todos-omarchy"
  readonly property string sourcesPath: configDir + "/sources.json"
  readonly property string calendarsPath: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/almanac/hosted-calendars.json"
  readonly property string commitMsgPath: (Quickshell.env("XDG_RUNTIME_DIR") || configDir) + "/dottie-todos-omarchy-commit-msg"
  readonly property string almanacBodyPath: (Quickshell.env("XDG_RUNTIME_DIR") || configDir) + "/dottie-todos-omarchy-almanac-body.json"

  property var sources: []
  property string selectedID: ""
  property var lines: []
  property var sections: []
  property int openCount: 0
  property int completedCount: 0
  property string filePath: ""
  property string lastError: ""
  property string lastStatus: ""
  property string appVersion: ""
  property bool isBusy: false
  property bool fileMissing: false
  property bool suppressWatch: false
  property int statusToken: 0
  property bool pullInFlight: false
  property double lastPullAt: 0
  property string lastPullDir: ""
  property var pendingGit: null
  property var lastGitJob: null
  property bool notSynced: false
  property var almanacCalendars: []
  property bool almanacHidden: false
  property bool sourcesReady: false
  property int almanacToken: 0
  property var pendingAlmanac: null
  property bool completeAnimDone: true
  property bool pendingCompleteReload: false

  property string query: ""
  property bool showCompleted: false
  property bool showAddField: false
  property bool showFilter: false
  property bool showAddList: false
  property string newTodoText: ""
  property string addListPath: ""
  property string renameID: ""
  property string renameText: ""
  property string editingId: ""
  property real ctxX: 0
  property real ctxY: 0
  property string editDraft: ""
  property var ctx: null
  property bool rowDragging: false
  property bool animateShift: true
  property var dragItem: null
  property string dragSection: ""
  property int dragFromIndex: -1
  property int dragHoverIndex: -1
  property real dragPointerY: 0
  property real dragGrabOffset: 0
  property real dragGhostH: 40
  property string dragGhostText: ""
  property int edgeScrollDir: 0
  property var dragRepeater: null
  property bool ghostSettling: false
  property real ghostY: 0
  property real ghostOpacity: 0
  property real ghostScale: 1
  property var settleItem: null
  property int settleDest: -1

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property int fontWeight: 700
  readonly property int fontBody: 16
  readonly property int fontCaption: 13
  readonly property int fontIcon: 18
  readonly property int chipHeight: Math.max(Style.spacing.controlHeight, 36)
  property string completingId: ""
  property bool completingDone: true
  readonly property var filtered: Doc.filterSections(sections, query, showCompleted, completingId)
  readonly property bool fieldFocused: addField.activeFocus || listPathField.activeFocus || filterField.activeFocus || renameField.activeFocus || editingId !== ""
  readonly property string changelogPath: filePath !== "" ? dirname(filePath) + "/CHANGELOG.md" : ""
  readonly property bool isAlmanac: {
    var src = null
    for (var i = 0; i < sources.length; i++) if (sources[i].id === selectedID) src = sources[i]
    return !!(src && Almanac.isAlmanacSource(src))
  }

  function trim(s) {
    return String(s || "").replace(/^\s+|\s+$/g, "")
  }

  function dirname(p) {
    var s = String(p || "")
    var i = s.lastIndexOf("/")
    return i <= 0 ? s : s.slice(0, i)
  }

  function expandPath(p) {
    var raw = trim(p)
    if (raw === "~") return home
    if (raw.indexOf("~/") === 0) return home + raw.slice(1)
    return raw
  }

  function newId() {
    return "s" + Date.now().toString(36) + Math.floor(Math.random() * 1e9).toString(36)
  }

  function defaultSource() {
    var path = Doc.defaultTodosPath(home, null)
    return { id: newId(), title: Doc.defaultTitle(path), path: path }
  }

  function selectedSource() {
    for (var i = 0; i < sources.length; i++) if (sources[i].id === selectedID) return sources[i]
    return sources.length ? sources[0] : null
  }

  function publish() {
    sections = Doc.parse(lines)
    openCount = Doc.openCount(lines)
    completedCount = Doc.completedCount(lines)
  }

  function applyText(text) {
    lines = Doc.fromText(text)
    fileMissing = false
    lastError = ""
    publish()
  }

  function applyMissing() {
    lines = []
    fileMissing = true
    lastError = "No todo file yet — add an item to create " + filePath
    publish()
  }

  function persistSources() {
    mkdirProc.running = true
    var stored = []
    for (var i = 0; i < sources.length; i++) stored.push(serializeSource(sources[i]))
    var payload = { sources: stored, selectedID: selectedID, almanacHidden: almanacHidden }
    sourcesFile.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  function serializeSource(src) {
    if (Almanac.isAlmanacSource(src)) {
      return {
        id: src.id,
        kind: "almanac",
        title: src.title || "Almanac",
        calendarId: Almanac.calendarIdOf(src)
      }
    }
    return { id: src.id, title: src.title, path: src.path }
  }

  function sourceTooltip(src) {
    if (!src) return ""
    if (Almanac.isAlmanacSource(src)) return "Almanac · " + Almanac.calendarIdOf(src)
    return src.path || ""
  }

  function maybeInsertAlmanac() {
    if (!sourcesReady || almanacHidden) return
    var next = Almanac.ensureSource(sources, almanacCalendars, newId)
    if (next.length === sources.length) return
    sources = next
    persistSources()
  }

  function pluginFilePath(name) {
    var url = String(Qt.resolvedUrl(name) || "")
    if (url.indexOf("file://") === 0) return url.slice(7)
    return url
  }

  function gitScriptPath(name) {
    return pluginFilePath("scripts/" + name)
  }

  function gitSyncPath() {
    return gitScriptPath("git-sync.sh")
  }

  function gitPullPath() {
    return gitScriptPath("git-pull.sh")
  }

  function schedulePull(force) {
    if (isAlmanac || filePath === "") return
    if (pullInFlight) return
    if (isBusy) return
    var dir = dirname(filePath)
    if (dir === "") return
    var now = Date.now()
    if (!force && lastPullDir === dir && now - lastPullAt < 30000) return
    lastPullDir = dir
    lastPullAt = now
    pullInFlight = true
    gitPullProc.command = [gitPullPath(), "--dir", dir, "--push"]
    gitPullProc.running = true
  }

  function pullRemote(force) {
    schedulePull(force === true)
  }

  function refresh() {
    notSynced = false
    lastError = ""
    if (isAlmanac) {
      almanacReload()
      return
    }
    todoFile.reload()
    schedulePull(true)
  }

  function applySyncOutcome(outcome) {
    if (outcome === "PULLED" || outcome === "REBASED" || outcome === "REBASED_PUSHED") {
      notSynced = false
      lastError = ""
      todoFile.reload()
      changelogFile.reload()
      return
    }
    if (outcome === "DIVERGED") {
      notSynced = true
      lastError = ""
    }
  }

  function loadSources(raw) {
    var parsed = null
    try { parsed = JSON.parse(raw) } catch (e) { parsed = null }
    almanacHidden = !!(parsed && parsed.almanacHidden)
    var next = []
    if (parsed && parsed.sources && parsed.sources.length) {
      for (var i = 0; i < parsed.sources.length; i++) {
        var src = parsed.sources[i]
        if (!src) continue
        if (Almanac.isAlmanacSource(src)) {
          next.push({
            id: src.id || newId(),
            kind: "almanac",
            title: src.title || "Almanac",
            calendarId: Almanac.calendarIdOf(src),
            path: ""
          })
          continue
        }
        if (!src.path) continue
        next.push({
          id: src.id || newId(),
          kind: "file",
          title: src.title || Doc.defaultTitle(src.path),
          path: expandPath(src.path)
        })
      }
    }
    if (next.length === 0) next = [defaultSource()]
    var before = next.length
    if (!almanacHidden) next = Almanac.ensureSource(next, almanacCalendars, newId)
    sources = next
    sourcesReady = true
    var sel = parsed && parsed.selectedID ? String(parsed.selectedID) : ""
    var ok = false
    for (var j = 0; j < sources.length; j++) if (sources[j].id === sel) ok = true
    selectedID = ok ? sel : sources[0].id
    applySelection()
    if (next.length !== before) persistSources()
  }

  function applySelection() {
    var src = selectedSource()
    if (!src) return
    lastError = ""
    lastStatus = ""
    query = ""
    editingId = ""
    ctx = null
    if (Almanac.isAlmanacSource(src)) {
      filePath = ""
      lines = []
      fileMissing = false
      sections = []
      openCount = 0
      completedCount = 0
      almanacReload()
      return
    }
    isBusy = false
    filePath = src.path
    todoFile.reload()
    changelogFile.reload()
  }

  function selectSource(id) {
    if (selectedID === id) return
    selectedID = id
    persistSources()
    applySelection()
  }

  function addSource(path) {
    if (Almanac.isAlmanacPath(path)) {
      addAlmanacSource(path)
      return
    }
    var resolved = expandPath(path)
    if (resolved.length === 0) return
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].path === resolved) {
        selectSource(sources[i].id)
        return
      }
    }
    var src = { id: newId(), kind: "file", title: Doc.defaultTitle(resolved), path: resolved }
    sources = sources.concat([src])
    selectedID = src.id
    persistSources()
    applySelection()
  }

  function addAlmanacSource(path) {
    var cal = Almanac.resolveCalendar(almanacCalendars, Almanac.pathCalendarId(path))
    if (!cal) {
      lastError = "No Almanac calendar"
      return
    }
    almanacHidden = false
    for (var i = 0; i < sources.length; i++) {
      if (Almanac.isAlmanacSource(sources[i]) && Almanac.calendarIdOf(sources[i]) === cal.id) {
        selectSource(sources[i].id)
        persistSources()
        return
      }
    }
    var src = Almanac.makeSource(cal, newId())
    sources = sources.concat([src])
    selectedID = src.id
    persistSources()
    applySelection()
  }

  function removeSource(id) {
    if (sources.length <= 1) return
    var next = []
    var idx = -1
    var removed = null
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].id === id) { idx = i; removed = sources[i]; continue }
      next.push(sources[i])
    }
    if (idx < 0 || next.length === 0) return
    if (removed && Almanac.isAlmanacSource(removed)) almanacHidden = true
    sources = next
    if (selectedID === id) selectedID = next[Math.min(idx, next.length - 1)].id
    persistSources()
    applySelection()
  }

  function renameSource(id, title) {
    var name = trim(title)
    if (name.length === 0) return
    var next = []
    for (var i = 0; i < sources.length; i++) {
      var src = sources[i]
      if (src.id !== id) { next.push(src); continue }
      next.push({
        id: src.id,
        kind: src.kind || (Almanac.isAlmanacSource(src) ? "almanac" : "file"),
        title: name,
        path: src.path || "",
        calendarId: src.calendarId || ""
      })
    }
    sources = next
    persistSources()
  }

  function almanacCalendarId() {
    var src = selectedSource()
    return src ? Almanac.calendarIdOf(src) : ""
  }

  function almanacReload() {
    if (!isAlmanac) return
    var cal = almanacCalendarId()
    if (!cal) {
      lastError = "No Almanac calendar"
      applyAlmanacSections([])
      return
    }
    almanacToken += 1
    isBusy = true
    lastError = ""
    almanacRemote.list(cal, almanacToken)
  }

  function applyAlmanacSections(next) {
    sections = next
    openCount = Almanac.countOpen(next)
    completedCount = Almanac.countCompleted(next)
    fileMissing = false
  }

  function applyAlmanacList(body) {
    applyAlmanacSections(Almanac.parseTodos(body))
  }

  function startAlmanacWrite(op, payload, status) {
    if (isBusy) return
    var cal = almanacCalendarId()
    if (!cal) {
      lastError = "No Almanac calendar"
      return
    }
    isBusy = true
    lastError = ""
    if (status) lastStatus = status
    almanacToken += 1
    pendingAlmanac = { op: op, cal: cal, token: almanacToken, payload: payload || {} }
    if (op === "delete") {
      almanacRemote.remove(cal, payload.uid, almanacToken)
      pendingAlmanac = null
      return
    }
    var body = payload.body || {}
    var wire = { _n: almanacToken }
    if (payload.uid) wire.uid = payload.uid
    if (body.uid !== undefined) wire.uid = body.uid
    if (body.title !== undefined) wire.title = body.title
    if (body.done !== undefined) wire.done = body.done
    almanacBodyFile.setText(JSON.stringify(wire) + "\n")
  }

  function startPendingAlmanac() {
    var job = pendingAlmanac
    pendingAlmanac = null
    if (!job) return
    if (job.op === "post") almanacRemote.post(job.cal, almanacBodyPath, job.token)
    else if (job.op === "patch") almanacRemote.patch(job.cal, job.payload.uid, almanacBodyPath, job.token)
  }

  function failPendingAlmanac(err) {
    pendingAlmanac = null
    lastError = err || "Could not write Almanac request"
    isBusy = false
  }

  function onAlmanacFinished(op, ok, body, token) {
    if (token !== almanacToken) return
    isBusy = false
    if (!ok) {
      lastError = Almanac.errorMessage(body)
      completingId = ""
      pendingCompleteReload = false
      return
    }
    lastError = ""
    if (op === "list") {
      applyAlmanacList(body)
      return
    }
    pendingCompleteReload = true
    finishCompleteAnim()
  }

  function itemKey(item) {
    if (!item) return ""
    return item.uid || item.id || ""
  }

  function beginCompleteAnim(item, willComplete) {
    completingId = itemKey(item)
    completingDone = willComplete
    completeAnimDone = false
    pendingCompleteReload = false
    completeAnimTimer.restart()
  }

  function finishCompleteAnim() {
    if (!completeAnimDone) return
    if (isAlmanac && !pendingCompleteReload && isBusy) return
    completingId = ""
    if (pendingCompleteReload) {
      pendingCompleteReload = false
      almanacReload()
    }
  }

  function save(status, message, extraFiles) {
    if (isBusy) return
    isBusy = true
    lastError = ""
    suppressWatch = true
    suppressTimer.restart()
    var body = Doc.toText(lines)
    todoFile.setText(body)
    publish()
    if (status) lastStatus = status
    statusToken += 1
    var token = statusToken
    var args = [gitSyncPath(), "--dir", dirname(filePath), "--message-file", commitMsgPath, "--push"]
    args.push("--")
    args.push(filePath)
    if (extraFiles) {
      for (var i = 0; i < extraFiles.length; i++) args.push(extraFiles[i])
    }
    pendingGit = { token: token, status: status, args: args }
    lastGitJob = pendingGit
    mkdirProc.running = true
    commitMsgFile.setText(String(message || "") + "\n")
  }

  function startGitJob(job, isRetry) {
    if (!job) return
    gitProc.running = false
    gitProc.command = job.args
    gitProc.token = job.token
    gitProc.status = job.status
    gitProc.retried = isRetry === true
    gitProc.running = true
  }

  function startPendingGit() {
    if (!pendingGit) return
    var job = pendingGit
    pendingGit = null
    startGitJob(job, false)
  }

  function failPendingGit(err) {
    if (!pendingGit) return
    lastStatus = pendingGit.status + " · not committed"
    lastError = err || "Could not write commit message file"
    pendingGit = null
    isBusy = false
  }

  function mutate(fn, status, prefix, label) {
    if (isBusy) return
    try {
      var result = fn()
      lines = result.lines
      save(status, Doc.commitMessage(prefix, label), result.extraFiles || [])
    } catch (e) {
      lastError = e && e.message ? e.message : String(e)
      reload()
    }
  }

  function addTodo(text) {
    if (isAlmanac) {
      startAlmanacWrite("post", { body: { title: trim(text) } }, "Added")
      return
    }
    mutate(function () { return Doc.addItem(lines, text) }, "Added", "Add", text)
  }

  function complete(item) {
    if (isBusy) return
    beginCompleteAnim(item, !item.isCompleted)
    if (isAlmanac) {
      var uid = item.uid || ""
      if (!uid) {
        lastError = "Almanac todo missing uid"
        completingId = ""
        return
      }
      startAlmanacWrite("post", { uid: uid, body: { title: trim(item.text), done: !item.isCompleted } }, item.isCompleted ? "Reopened" : "Completed")
      return
    }
    mutate(function () {
      var result = Doc.toggleComplete(lines, item.text, item.section, item.lineIndex, item.isCompleted)
      var extra = []
      if (result.completed) {
        var existing = ""
        try { existing = changelogFile.text() } catch (e) { existing = "" }
        changelogFile.setText(Doc.insertChangelogEntry(existing, Doc.todayHeader(), "  " + item.text))
        extra.push(changelogPath)
      }
      result.extraFiles = extra
      return result
    }, item.isCompleted ? "Reopened" : "Completed", item.isCompleted ? "Reopen" : "Complete", item.text)
  }

  function saveEdit(item, text) {
    if (isAlmanac) {
      var uid = item.uid || ""
      if (!uid) {
        lastError = "Almanac todo missing uid"
        return
      }
      startAlmanacWrite("post", { uid: uid, body: { title: trim(text), done: !!item.isCompleted } }, "Edited")
      return
    }
    mutate(function () {
      return Doc.updateItem(lines, item.text, item.section, item.lineIndex, item.isCompleted, text)
    }, "Edited", "Edit", text)
  }

  function deleteTodo(item) {
    if (isAlmanac) {
      startAlmanacWrite("delete", { uid: item.uid || item.id }, "Deleted")
      return
    }
    mutate(function () {
      return Doc.deleteItem(lines, item.text, item.section, item.lineIndex, item.isCompleted)
    }, "Deleted", "Delete", item.text)
  }

  function moveItem(item, direction) {
    if (isAlmanac) return
    mutate(function () { return Doc.moveOpenItem(lines, item, direction) }, "Reordered", "Reorder", item.section)
  }

  function reorderOpen(item, destIndex) {
    if (isAlmanac) return
    if (!item || item.isCompleted) return
    if (trim(query).length > 0) return
    var open = []
    for (var s = 0; s < sections.length; s++) {
      if (sections[s].title === item.section) {
        open = openItems(sections[s])
        break
      }
    }
    var from = -1
    for (var i = 0; i < open.length; i++) {
      if (open[i].id === item.id) { from = i; break }
    }
    if (from < 0 || open.length === 0) return
    var dest = Math.max(0, Math.min(Number(destIndex), open.length - 1))
    if (dest === from) return
    mutate(function () {
      return Doc.moveOpenItems(lines, item.section, [from], dest)
    }, "", "Reorder", item.section)
  }

  function hoverIndexForSection(repeater, globalY) {
    if (!repeater || repeater.count <= 0) return 0
    var first = repeater.itemAt(0)
    if (!first || !first.parent) return 0
    var localY = first.parent.mapFromItem(null, 0, globalY).y - first.y
    var acc = 0
    var i
    var child
    for (i = 0; i < repeater.count; i++) {
      child = repeater.itemAt(i)
      if (!child) continue
      if (localY < acc + child.height * 0.5) return i
      acc += child.height
    }
    return repeater.count - 1
  }

  function rowShiftY(sectionTitle, index) {
    if (!rowDragging || dragSection !== sectionTitle || dragFromIndex < 0) return 0
    if (index === dragFromIndex) return 0
    if (dragFromIndex < dragHoverIndex && index > dragFromIndex && index <= dragHoverIndex)
      return -dragGhostH
    if (dragHoverIndex < dragFromIndex && index >= dragHoverIndex && index < dragFromIndex)
      return dragGhostH
    return 0
  }

  function updateEdgeScroll(globalY) {
    var local = listFlick.mapFromItem(null, 0, globalY).y
    var edge = 32
    if (local < edge) edgeScrollDir = -1
    else if (local > listFlick.height - edge) edgeScrollDir = 1
    else edgeScrollDir = 0
  }

  function ghostFollowY(globalY) {
    return listFlick.y + listFlick.mapFromItem(null, 0, globalY).y - dragGrabOffset
  }

  function destSlotY(repeater, dest) {
    var row = repeater && dest >= 0 ? repeater.itemAt(dest) : null
    if (!row || !row.parent || !dragGhost.parent) return ghostY
    return row.parent.mapToItem(dragGhost.parent, 0, row.y).y
  }

  function beginRowDrag(repeater, item, sectionTitle, index, globalY) {
    var row = repeater ? repeater.itemAt(index) : null
    settleTimer.stop()
    ghostFadeTimer.stop()
    dragRepeater = repeater
    rowDragging = true
    ghostSettling = false
    animateShift = true
    dragItem = item
    dragSection = sectionTitle
    dragFromIndex = index
    dragHoverIndex = index
    dragPointerY = globalY
    dragGhostH = row ? row.height : Style.space(40)
    dragGhostText = item && item.text ? item.text : ""
    dragGrabOffset = row ? globalY - row.mapToItem(null, 0, 0).y : dragGhostH / 2
    ghostY = ghostFollowY(globalY)
    ghostOpacity = 0.97
    ghostScale = 1.02
    updateEdgeScroll(globalY)
  }

  function updateRowDrag(repeater, globalY) {
    if (ghostSettling) return
    dragPointerY = globalY
    dragHoverIndex = hoverIndexForSection(repeater, globalY)
    ghostY = ghostFollowY(globalY)
    updateEdgeScroll(globalY)
  }

  function finishRowDrag(repeater, globalY) {
    if (ghostSettling) return
    var dest = hoverIndexForSection(repeater, globalY)
    edgeScrollDir = 0
    settleItem = dragItem
    settleDest = dest
    dragRepeater = repeater
    ghostSettling = true
    ghostY = destSlotY(repeater, dest)
    ghostScale = 1
    settleTimer.restart()
  }

  function commitSettledDrag() {
    var item = settleItem
    var dest = settleDest
    animateShift = false
    reorderOpen(item, dest)
    rowDragging = false
    dragItem = null
    dragSection = ""
    dragFromIndex = -1
    dragHoverIndex = -1
    dragRepeater = null
    settleItem = null
    settleDest = -1
    ghostOpacity = 0
    ghostFadeTimer.restart()
  }

  function clearGhost() {
    ghostSettling = false
    dragGhostText = ""
    ghostScale = 1
    animateShift = true
  }

  function reload() {
    if (isAlmanac) almanacReload()
    else todoFile.reload()
  }

  function openInEditor() {
    if (isAlmanac || filePath === "") return
    Util.execArgv(["omarchy-launch-editor", filePath])
  }

  function reveal() {
    if (isAlmanac || filePath === "") return
    Util.execArgv(["xdg-open", dirname(filePath)])
  }

  function copyText(text) {
    Quickshell.execDetached(["wl-copy", "--", text])
    lastStatus = "Copied"
  }

  function submitNewTodo() {
    var text = trim(newTodoText)
    if (text.length === 0) return
    newTodoText = ""
    addTodo(text)
    showAddField = true
  }

  function submitAddList() {
    var path = expandPath(addListPath)
    if (path.length === 0) return
    addListPath = ""
    showAddList = false
    addSource(path)
  }

  function openItems(section) {
    var out = []
    if (!section || !section.items) return out
    for (var i = 0; i < section.items.length; i++) {
      var it = section.items[i]
      if (!it.isCompleted || itemKey(it) === completingId) out.push(it)
    }
    return out
  }

  function doneItems(section) {
    var out = []
    if (!section || !section.items) return out
    for (var i = 0; i < section.items.length; i++) {
      var it = section.items[i]
      if (it.isCompleted && itemKey(it) !== completingId) out.push(it)
    }
    return out
  }

  function ctxActions() {
    if (!ctx) return []
    if (ctx.kind === "tab") {
      var rows = ["Rename…"]
      if (ctx.source && !Almanac.isAlmanacSource(ctx.source)) rows.push("Reveal")
      if (sources.length > 1) rows.push("Remove Tab")
      return rows
    }
    if (ctx.kind === "item" && ctx.item) {
      var item = ctx.item
      var out = [item.isCompleted ? "Reopen" : "Mark Complete"]
      out.push("Edit…")
      out.push("Copy")
      out.push("Delete")
      return out
    }
    return []
  }

  function runCtx(action) {
    var kind = ctx ? ctx.kind : ""
    var src = ctx ? ctx.source : null
    var item = ctx ? ctx.item : null
    ctx = null
    if (kind === "tab" && src) {
      if (action === "Rename…") {
        renameText = src.title
        renameID = src.id
        renameField.forceActiveFocus()
      } else if (action === "Reveal") {
        Util.execArgv(["xdg-open", dirname(src.path)])
      } else if (action === "Remove Tab") {
        removeSource(src.id)
      }
      return
    }
    if (kind === "item" && item) {
      if (action === "Reopen" || action === "Mark Complete") complete(item)
      else if (action === "Edit…") {
        editingId = item.id
        editDraft = item.text
      } else if (action === "Copy") copyText(item.text)
      else if (action === "Delete") deleteTodo(item)
    }
  }

  function focusAdd() {
    showAddField = true
    showAddList = false
    addField.forceActiveFocus()
  }

  function focusFilter() {
    showFilter = true
    filterField.forceActiveFocus()
  }

  function openCtxAtItem(payload, item) {
    if (item) {
      var p = item.mapToItem(root, 0, item.height)
      ctxX = p.x
      ctxY = p.y
    }
    ctx = payload
  }

  function openCtxAtGlobal(payload, gx, gy) {
    var p = root.mapFromItem(null, gx, gy)
    ctxX = p.x
    ctxY = p.y
    ctx = payload
  }

  function dismissOverlays() {
    if (showFilter) {
      showFilter = false
      query = ""
    }
    showAddList = false
    showAddField = false
    editingId = ""
    ctx = null
    renameID = ""
  }

  Timer {
    id: suppressTimer
    interval: 1500
    onTriggered: root.suppressWatch = false
  }

  Timer {
    id: edgeScrollTimer
    interval: 16
    repeat: true
    running: root.rowDragging && root.edgeScrollDir !== 0 && !root.ghostSettling
    onTriggered: {
      var maxY = Math.max(0, listFlick.contentHeight - listFlick.height)
      listFlick.contentY = Math.max(0, Math.min(maxY, listFlick.contentY + root.edgeScrollDir * 14))
      if (root.dragRepeater)
        root.dragHoverIndex = root.hoverIndexForSection(root.dragRepeater, root.dragPointerY)
    }
  }

  Timer {
    id: settleTimer
    interval: 160
    onTriggered: root.commitSettledDrag()
  }

  Timer {
    id: ghostFadeTimer
    interval: 140
    onTriggered: root.clearGhost()
  }

  Timer {
    id: completeAnimTimer
    interval: 360
    onTriggered: {
      root.completeAnimDone = true
      root.finishCompleteAnim()
    }
  }

  Timer {
    id: busyRetryTimer
    interval: 400
    onTriggered: {
      if (root.lastGitJob && root.lastGitJob.token === root.statusToken)
        root.startGitJob(root.lastGitJob, true)
      else
        root.isBusy = false
    }
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.configDir]
  }

  Process {
    id: gitProc
    property int token: 0
    property string status: ""
    property bool retried: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (gitProc.token !== root.statusToken) return
        var out = String(text || "")
        if (out.indexOf("BUSY") >= 0) {
          if (!gitProc.retried) {
            gitProc.retried = true
            busyRetryTimer.restart()
            return
          }
          root.isBusy = false
          return
        }
        var outcome = "committed"
        if (out.indexOf("FAILED:") >= 0) {
          outcome = "failed"
        } else if (out.indexOf("REBASED_PUSHED") >= 0 || out.indexOf("PUSHED") >= 0) {
          outcome = "pushed"
          root.notSynced = false
          if (out.indexOf("REBASED_PUSHED") >= 0) {
            todoFile.reload()
            changelogFile.reload()
          }
        } else if (out.indexOf("DIVERGED") >= 0) {
          outcome = "committed"
          root.notSynced = true
        } else if (out.indexOf("COMMITTED") >= 0 || out.indexOf("COMMITTED_EMPTY") >= 0) {
          outcome = "committed"
        }
        var allowed = {}
        allowed[gitProc.status] = true
        allowed[gitProc.status + " · not committed"] = true
        allowed[gitProc.status + " · committed"] = true
        allowed[gitProc.status + " · pushed"] = true
        if (allowed[root.lastStatus] === true) {
          if (outcome === "failed") root.lastStatus = gitProc.status + " · not committed"
          else if (outcome === "pushed") root.lastStatus = gitProc.status + " · pushed"
          else root.lastStatus = gitProc.status + " · committed"
        }
        root.lastError = ""
        root.isBusy = false
      }
    }
    onExited: function () {
      Qt.callLater(function () { root.isBusy = false })
    }
  }

  Process {
    id: gitPullProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.pullInFlight = false
        var out = String(text || "")
        var outcome = "ok"
        if (out.indexOf("DIVERGED") >= 0) outcome = "DIVERGED"
        else if (out.indexOf("REBASED_PUSHED") >= 0) outcome = "REBASED_PUSHED"
        else if (out.indexOf("REBASED") >= 0) outcome = "REBASED"
        else if (out.indexOf("PULLED") >= 0) outcome = "PULLED"
        root.applySyncOutcome(outcome)
      }
    }
    onExited: function () {
      Qt.callLater(function () { root.pullInFlight = false })
    }
  }

  FileView {
    id: commitMsgFile
    path: root.commitMsgPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onSaved: root.startPendingGit()
    onSaveFailed: root.failPendingGit("Could not write commit message file")
  }

  FileView {
    id: sourcesFile
    path: root.sourcesPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadSources(text())
    onLoadFailed: root.loadSources("")
  }

  FileView {
    id: todoFile
    path: root.filePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: if (!root.suppressWatch && !root.isAlmanac) todoFile.reload()
    onLoaded: if (!root.suppressWatch && !root.isAlmanac) root.applyText(text())
    onLoadFailed: if (!root.isAlmanac && root.filePath !== "") root.applyMissing()
  }

  FileView {
    id: calendarsFile
    path: root.calendarsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.almanacCalendars = Almanac.parseCalendars(text())
      root.maybeInsertAlmanac()
    }
    onLoadFailed: root.almanacCalendars = []
  }

  FileView {
    id: almanacBodyFile
    path: root.almanacBodyPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onSaved: root.startPendingAlmanac()
    onSaveFailed: root.failPendingAlmanac("Could not write Almanac request")
  }

  AlmanacRemote {
    id: almanacRemote
    onFinished: function (op, ok, body, token) {
      root.onAlmanacFinished(op, ok, body, token)
    }
  }

  FileView {
    id: changelogFile
    path: root.changelogPath
    watchChanges: false
    blockLoading: true
    atomicWrites: true
    printErrors: false
  }

  FileView {
    id: manifestFile
    path: root.pluginFilePath("manifest.json")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.appVersion = parsed && parsed.version ? String(parsed.version) : ""
      } catch (e) {
        root.appVersion = ""
      }
    }
  }

  Component.onCompleted: mkdirProc.running = true

  Keys.onPressed: function (event) {
    if (root.fieldFocused) return
    if (event.key === Qt.Key_Escape) {
      if (root.ctx !== null || root.showFilter || root.showAddList || root.showAddField || root.renameID !== "" || root.editingId !== "") {
        root.dismissOverlays()
        event.accepted = true
      } else if (!root.compact) {
        root.closeRequested()
        event.accepted = true
      }
    } else if (event.key === Qt.Key_N) {
      root.focusAdd()
      event.accepted = true
    } else if (event.key === Qt.Key_Slash) {
      root.focusFilter()
      event.accepted = true
    } else if (event.key === Qt.Key_R) {
      root.refresh()
      event.accepted = true
    }
  }

  Item {
    anchors.fill: parent
    anchors.margins: root.compact ? 0 : Style.space(12)

        Column {
          id: header
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(8)

          Row {
            id: headerRow
            width: parent.width
            height: root.chipHeight
            spacing: Style.space(8)

            Flickable {
              width: Math.max(80, parent.width - addBtn.width - Style.space(8))
              height: parent.height
              contentWidth: tabRow.implicitWidth
              clip: true
              flickableDirection: Flickable.HorizontalFlick
              boundsBehavior: Flickable.StopAtBounds

              Row {
                id: tabRow
                height: headerRow.height
                spacing: Style.space(4)

                Repeater {
                  model: root.sources
                  HeaderButton {
                    id: tabChip
                    required property var modelData
                    height: tabRow.height
                    text: modelData.id === root.selectedID
                      ? (Doc.tabTitle(modelData.title) + " " + root.openCount)
                      : Doc.tabTitle(modelData.title)
                    selected: modelData.id === root.selectedID
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    tooltipText: root.sourceTooltip(modelData)
                    onClicked: root.selectSource(modelData.id)
                    onRightClicked: root.openCtxAtItem({ kind: "tab", source: modelData }, tabChip)
                  }
                }

                HeaderButton {
                  height: tabRow.height
                  text: "+"
                  selected: root.showAddList
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  tooltipText: "Add a markdown file or Almanac"
                  onClicked: {
                    root.showAddList = !root.showAddList
                    root.showAddField = false
                    if (root.showAddList) listPathField.forceActiveFocus()
                  }
                }
              }
            }

            HeaderButton {
              id: addBtn
              height: parent.height
              iconText: "󰐕"
              selected: root.showAddField
              bordered: root.showAddField
              tooltipText: root.showAddField ? "Hide new to-do" : "Add to-do"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                root.showAddField = !root.showAddField
                root.showAddList = false
                if (root.showAddField) addField.forceActiveFocus()
              }
            }
          }

          TextField {
            id: addField
            visible: root.showAddField
            width: parent.width
            placeholderText: "New To-Do"
            text: root.newTodoText
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.fontBody
            font.weight: root.fontWeight
            onTextChanged: root.newTodoText = text
            onAccepted: root.submitNewTodo()
            Keys.onEscapePressed: {
              root.showAddField = false
              root.newTodoText = ""
            }
          }

          TextField {
            id: listPathField
            visible: root.showAddList
            width: parent.width
            placeholderText: "Path to .md or almanac"
            text: root.addListPath
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.fontBody
            font.weight: root.fontWeight
            onTextChanged: root.addListPath = text
            onAccepted: root.submitAddList()
            Keys.onEscapePressed: {
              root.showAddList = false
              root.addListPath = ""
            }
          }

          TextField {
            id: renameField
            visible: root.renameID !== ""
            width: parent.width
            placeholderText: "Tab name"
            text: root.renameText
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.fontBody
            font.weight: root.fontWeight
            onAccepted: {
              root.renameSource(root.renameID, text)
              root.renameID = ""
            }
            Keys.onEscapePressed: root.renameID = ""
          }
        }

        Flickable {
          id: listFlick
          anchors.top: header.bottom
          anchors.bottom: footer.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Style.space(8)
          anchors.bottomMargin: Style.space(8)
          contentWidth: width
          contentHeight: listColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: !root.rowDragging
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: listColumn
            width: listFlick.width
            spacing: 0

            Repeater {
              model: root.filtered

              Column {
                id: sectionCol
                required property var modelData
                width: listColumn.width
                spacing: 0

                PanelSectionHeader {
                  visible: sectionCol.modelData.title !== "To-Dos"
                  text: sectionCol.modelData.title
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: root.fontCaption
                  font.weight: root.fontWeight
                  leftPadding: Style.space(12)
                  topPadding: Style.space(12)
                  bottomPadding: Style.space(4)
                }

                Repeater {
                  id: openRepeater
                  model: root.openItems(sectionCol.modelData)

                  TodoRow {
                    required property var modelData
                    required property int index
                    width: listColumn.width
                    item: modelData
                    openIndex: index
                    striped: index % 2 === 1
                    draggable: !root.isAlmanac && !modelData.isCompleted && root.trim(root.query).length === 0 && !root.isBusy
                    dragging: root.rowDragging && root.dragItem && root.dragItem.id === modelData.id
                    listDragging: root.rowDragging
                    animateShift: root.animateShift
                    shiftY: root.rowShiftY(sectionCol.modelData.title, index)
                    editing: root.editingId === modelData.id
                    draft: root.editDraft
                    foreground: root.foreground
                    dim: root.dim
                    fontFamily: root.fontFamily
                    fontWeight: root.fontWeight
                    fontSize: root.fontBody
                    iconSize: root.fontIcon
                    previewId: root.completingId
                    previewDone: root.completingDone
                    hideWhenDone: !root.showCompleted && root.completingDone && root.itemKey(modelData) === root.completingId
                    onCompleteClicked: root.complete(modelData)
                    onEditRequested: {
                      root.editingId = modelData.id
                      root.editDraft = modelData.text
                    }
                    onEditAccepted: function (text) {
                      root.editingId = ""
                      root.saveEdit(modelData, text)
                    }
                    onEditCancelled: root.editingId = ""
                    onMenuRequested: function (gx, gy) {
                      root.openCtxAtGlobal({ kind: "item", item: modelData }, gx, gy)
                    }
                    onDragBegan: function (globalY) {
                      root.beginRowDrag(openRepeater, modelData, sectionCol.modelData.title, index, globalY)
                    }
                    onDragUpdated: function (globalY) {
                      root.updateRowDrag(openRepeater, globalY)
                    }
                    onDragFinished: function (globalY) {
                      root.finishRowDrag(openRepeater, globalY)
                    }
                  }
                }

                Repeater {
                  model: root.showCompleted ? root.doneItems(sectionCol.modelData) : []

                  TodoRow {
                    required property var modelData
                    required property int index
                    width: listColumn.width
                    item: modelData
                    striped: (openRepeater.count + index) % 2 === 1
                    editing: root.editingId === modelData.id
                    draft: root.editDraft
                    foreground: root.foreground
                    dim: root.dim
                    fontFamily: root.fontFamily
                    fontWeight: root.fontWeight
                    fontSize: root.fontBody
                    iconSize: root.fontIcon
                    previewId: root.completingId
                    previewDone: root.completingDone
                    hideWhenDone: !root.showCompleted && root.completingDone && root.itemKey(modelData) === root.completingId
                    onCompleteClicked: root.complete(modelData)
                    onEditRequested: {
                      root.editingId = modelData.id
                      root.editDraft = modelData.text
                    }
                    onEditAccepted: function (text) {
                      root.editingId = ""
                      root.saveEdit(modelData, text)
                    }
                    onEditCancelled: root.editingId = ""
                    onMenuRequested: function (gx, gy) {
                      root.openCtxAtGlobal({ kind: "item", item: modelData }, gx, gy)
                    }
                  }
                }
              }
            }

            Text {
              visible: root.filtered.length === 0
              width: parent.width
              topPadding: Style.space(40)
              horizontalAlignment: Text.AlignHCenter
              text: root.trim(root.query).length > 0 ? "No matches" : (root.isAlmanac ? "No open Almanac todos" : "No open todos in this file")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: root.fontBody
              font.weight: root.fontWeight
            }
          }
        }

        Item {
          id: dragGhost
          visible: root.ghostOpacity > 0.01 && root.dragGhostText !== ""
          width: listFlick.width
          height: root.dragGhostH
          x: listFlick.x
          y: root.ghostY
          z: 30
          scale: root.ghostScale
          opacity: root.ghostOpacity

          Behavior on y {
            enabled: root.ghostSettling
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
          }
          Behavior on scale {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }
          Behavior on opacity {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
          }

          Rectangle {
            anchors.fill: parent
            anchors.topMargin: 4
            anchors.leftMargin: 1
            color: Qt.rgba(0, 0, 0, 0.32)
            radius: Style.cornerRadius
          }

          Rectangle {
            anchors.fill: parent
            color: Color.popups.background
            radius: Style.cornerRadius
            border.width: 1
            border.color: Color.accent
            opacity: 0.98
          }

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰄱"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: root.fontIcon
              font.weight: root.fontWeight
              width: Style.space(28)
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(44)
              text: root.dragGhostText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.fontBody
              font.weight: root.fontWeight
              wrapMode: Text.Wrap
              maximumLineCount: 8
              elide: Text.ElideNone
            }
          }
        }

        Column {
          id: footer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.space(8)

          TextField {
            id: filterField
            visible: root.showFilter
            width: parent.width
            placeholderText: "Filter"
            text: root.query
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.fontBody
            font.weight: root.fontWeight
            onTextChanged: root.query = text
            Keys.onEscapePressed: {
              root.showFilter = false
              root.query = ""
            }
          }

          Item {
            width: parent.width
            height: root.chipHeight

            Row {
              id: footerActions
              anchors.left: parent.left
              anchors.right: versionSlot.left
              anchors.rightMargin: versionSlot.visible ? Style.space(8) : 0
              anchors.verticalCenter: parent.verticalCenter
              height: parent.height
              spacing: Style.space(8)

              HeaderButton {
                height: parent.height
                iconText: "󰍉"
                foreground: root.foreground
                fontFamily: root.fontFamily
                selected: root.showFilter || root.trim(root.query).length > 0
                bordered: root.showFilter || root.trim(root.query).length > 0
                tooltipText: root.showFilter ? "Hide filter" : (root.trim(root.query).length > 0 ? "Filter on" : "Filter")
                onClicked: {
                  if (root.showFilter) {
                    root.showFilter = false
                    root.query = ""
                  } else {
                    root.focusFilter()
                  }
                }
              }
              HeaderButton {
                height: parent.height
                iconText: "󰑐"
                tooltipText: "Refresh"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.refresh()
              }
              HeaderButton {
                visible: !root.isAlmanac
                height: parent.height
                iconText: "󰈙"
                tooltipText: "Open file"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.openInEditor()
              }
              HeaderButton {
                visible: root.compact
                height: parent.height
                iconText: "󰖯"
                tooltipText: "Open window"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.openWindowRequested()
              }
              HeaderButton {
                visible: root.completedCount > 0
                height: parent.height
                iconText: root.showCompleted ? "󰈉" : "󰈈"
                selected: root.showCompleted
                bordered: root.showCompleted
                tooltipText: root.showCompleted
                  ? ("Hide completed (" + root.completedCount + ")")
                  : ("Show completed (" + root.completedCount + ")")
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.showCompleted = !root.showCompleted
              }
            }

            Item {
              id: versionSlot
              visible: root.appVersion !== "" || root.lastError !== "" || root.lastStatus !== "" || root.notSynced
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: visible ? statusRow.implicitWidth : 0
              height: parent.height

              Row {
                id: statusRow
                anchors.right: parent.right
                height: parent.height
                spacing: Style.space(8)

                HeaderButton {
                  visible: root.notSynced
                  height: parent.height
                  text: "Not synced"
                  tooltipText: "Remote changed the same lines. Local list kept."
                  foreground: root.bar ? root.bar.urgent : Color.urgent
                  fontFamily: root.fontFamily
                  onClicked: root.refresh()
                }

                Text {
                  visible: !root.notSynced && (root.lastError !== "" || root.lastStatus !== "")
                  anchors.verticalCenter: parent.verticalCenter
                  width: visible ? Math.min(implicitWidth, Style.space(180)) : 0
                  text: root.lastError !== "" ? root.lastError : root.lastStatus
                  color: root.lastError !== "" ? (root.bar ? root.bar.urgent : Color.urgent) : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: root.fontCaption
                  font.weight: root.fontWeight
                  font.bold: true
                  wrapMode: Text.NoWrap
                  elide: Text.ElideRight
                }

                Text {
                  visible: root.appVersion !== ""
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.appVersion
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: root.fontCaption
                  font.weight: root.fontWeight
                  font.bold: true
                }
              }
            }
          }

        }

        MouseArea {
          visible: root.ctx !== null
          anchors.fill: parent
          hoverEnabled: true
          onClicked: root.ctx = null
        }

        BorderSurface {
          id: ctxMenu
          visible: root.ctx !== null
          width: ctxColumn.implicitWidth + Style.space(16)
          height: ctxColumn.implicitHeight + Style.space(16)
          x: Math.max(Style.space(8), Math.min(root.ctxX, parent.width - width - Style.space(8)))
          y: Math.max(Style.space(8), Math.min(root.ctxY, parent.height - height - Style.space(8)))
          color: Color.popups.background
          radius: Style.cornerRadius
          z: 10

          Column {
            id: ctxColumn
            anchors.centerIn: parent
            spacing: Style.space(4)

            Repeater {
              model: root.ctxActions()
              HeaderButton {
                required property string modelData
                width: Math.max(Style.space(140), implicitWidth)
                text: modelData
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.runCtx(modelData)
              }
            }
          }
        }
      }
}
