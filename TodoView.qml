import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TodoDocument.js" as Doc

Item {
  id: root

  property var bar: null
  property bool compact: true
  focus: true

  signal closeRequested()
  signal openWindowRequested()

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/todo-omarchy"
  readonly property string sourcesPath: configDir + "/sources.json"
  readonly property string commitMsgPath: (Quickshell.env("XDG_RUNTIME_DIR") || configDir) + "/todo-omarchy-commit-msg"

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
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var filtered: Doc.filterSections(sections, query, showCompleted)
  readonly property bool fieldFocused: addField.activeFocus || listPathField.activeFocus || filterField.activeFocus || renameField.activeFocus || editingId !== ""
  readonly property string changelogPath: filePath !== "" ? dirname(filePath) + "/CHANGELOG.md" : ""

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
    var payload = { sources: sources, selectedID: selectedID }
    sourcesFile.setText(JSON.stringify(payload, null, 2) + "\n")
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

  function isPullStatus(text) {
    return text === "Updated from git" ||
      text === "Remote has updates (kept local changes)" ||
      text === "Git diverged from remote — pull skipped"
  }

  function schedulePull(force) {
    if (filePath === "") return
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
    todoFile.reload()
    schedulePull(true)
  }

  function loadSources(raw) {
    var parsed = null
    try { parsed = JSON.parse(raw) } catch (e) { parsed = null }
    var next = []
    if (parsed && parsed.sources && parsed.sources.length) {
      for (var i = 0; i < parsed.sources.length; i++) {
        var src = parsed.sources[i]
        if (!src || !src.path) continue
        next.push({
          id: src.id || newId(),
          title: src.title || Doc.defaultTitle(src.path),
          path: expandPath(src.path)
        })
      }
    }
    if (next.length === 0) next = [defaultSource()]
    sources = next
    var sel = parsed && parsed.selectedID ? String(parsed.selectedID) : ""
    var ok = false
    for (var j = 0; j < sources.length; j++) if (sources[j].id === sel) ok = true
    selectedID = ok ? sel : sources[0].id
    applySelection()
  }

  function applySelection() {
    var src = selectedSource()
    if (!src) return
    filePath = src.path
    lastError = ""
    lastStatus = ""
    query = ""
    editingId = ""
    ctx = null
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
    var resolved = expandPath(path)
    if (resolved.length === 0) return
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].path === resolved) {
        selectSource(sources[i].id)
        return
      }
    }
    var src = { id: newId(), title: Doc.defaultTitle(resolved), path: resolved }
    sources = sources.concat([src])
    selectedID = src.id
    persistSources()
    applySelection()
  }

  function removeSource(id) {
    if (sources.length <= 1) return
    var next = []
    var idx = -1
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].id === id) { idx = i; continue }
      next.push(sources[i])
    }
    if (idx < 0 || next.length === 0) return
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
      next.push(src.id === id ? { id: src.id, title: name, path: src.path } : src)
    }
    sources = next
    persistSources()
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
    mkdirProc.running = true
    commitMsgFile.setText(String(message || "") + "\n")
  }

  function startPendingGit() {
    if (!pendingGit) return
    var job = pendingGit
    pendingGit = null
    gitProc.running = false
    gitProc.command = job.args
    gitProc.token = job.token
    gitProc.status = job.status
    gitProc.running = true
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
    mutate(function () { return Doc.addItem(lines, text) }, "Added", "Add", text)
  }

  function complete(item) {
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
    mutate(function () {
      return Doc.updateItem(lines, item.text, item.section, item.lineIndex, item.isCompleted, text)
    }, "Edited", "Edit", text)
  }

  function deleteTodo(item) {
    mutate(function () {
      return Doc.deleteItem(lines, item.text, item.section, item.lineIndex, item.isCompleted)
    }, "Deleted", "Delete", item.text)
  }

  function moveItem(item, direction) {
    mutate(function () { return Doc.moveOpenItem(lines, item, direction) }, "Reordered", "Reorder", item.section)
  }

  function reorderOpen(item, destIndex) {
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
    todoFile.reload()
  }

  function openInEditor() {
    if (filePath !== "") Util.execArgv(["omarchy-launch-editor", filePath])
  }

  function reveal() {
    if (filePath !== "") Util.execArgv(["xdg-open", dirname(filePath)])
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
    for (var i = 0; i < section.items.length; i++) if (!section.items[i].isCompleted) out.push(section.items[i])
    return out
  }

  function doneItems(section) {
    var out = []
    if (!section || !section.items) return out
    for (var i = 0; i < section.items.length; i++) if (section.items[i].isCompleted) out.push(section.items[i])
    return out
  }

  function ctxActions() {
    if (!ctx) return []
    if (ctx.kind === "tab") {
      var rows = ["Rename…", "Reveal"]
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

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.configDir]
  }

  Process {
    id: gitProc
    property int token: 0
    property string status: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (gitProc.token !== root.statusToken) return
        var out = String(text || "")
        var outcome = "committed"
        var err = ""
        if (out.indexOf("FAILED:") >= 0) {
          outcome = "failed"
          err = out.replace(/^[\s\S]*FAILED:/, "").split("\n")[0]
        } else if (out.indexOf("PUSHED") >= 0) {
          outcome = "pushed"
        } else if (out.indexOf("COMMITTED") >= 0) {
          outcome = "committed"
        }
        var pushErr = ""
        var match = out.match(/PUSH_ERROR:(.*)/)
        if (match) pushErr = match[1]
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
        if (err !== "" || pushErr !== "") root.lastError = err || pushErr
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
        if (out.indexOf("PULLED") >= 0) {
          root.lastStatus = "Updated from git"
          root.lastError = ""
          todoFile.reload()
          changelogFile.reload()
          return
        }
        var canSet = root.lastStatus === "" || root.isPullStatus(root.lastStatus)
        if (out.indexOf("DIVERGED") >= 0) {
          root.lastError = "Git diverged from remote — pull skipped"
        } else if (out.indexOf("SKIPPED:") >= 0) {
          if (canSet) root.lastStatus = "Remote has updates (kept local changes)"
        } else if (out.indexOf("FAILED:") >= 0) {
          var err = out.replace(/^[\s\S]*FAILED:/, "").split("\n")[0]
          if (err !== "") root.lastError = err
        }
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
    onFileChanged: if (!root.suppressWatch) todoFile.reload()
    onLoaded: if (!root.suppressWatch) root.applyText(text())
    onLoadFailed: root.applyMissing()
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
            height: Style.spacing.controlHeight
            spacing: Style.space(8)

            Flickable {
              width: Math.max(80, parent.width - addBtn.width - Style.space(16))
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
                    tooltipText: modelData.path
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
                  tooltipText: "Add another markdown todo file"
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
            placeholderText: "Path to .md — e.g. ~/books.md"
            text: root.addListPath
            foreground: root.foreground
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
            onAccepted: {
              root.renameSource(root.renameID, text)
              root.renameID = ""
            }
            Keys.onEscapePressed: root.renameID = ""
          }

          Text {
            visible: root.lastError !== "" || root.lastStatus !== ""
            width: parent.width
            text: root.lastError !== "" ? root.lastError : root.lastStatus
            color: root.lastError !== "" ? (root.bar ? root.bar.urgent : Color.urgent) : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
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
          opacity: root.isBusy ? 0.55 : 1
          Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
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
                    draggable: !modelData.isCompleted && root.trim(root.query).length === 0 && !root.isBusy
                    dragging: root.rowDragging && root.dragItem && root.dragItem.id === modelData.id
                    listDragging: root.rowDragging
                    animateShift: root.animateShift
                    shiftY: root.rowShiftY(sectionCol.modelData.title, index)
                    editing: root.editingId === modelData.id
                    draft: root.editDraft
                    foreground: root.foreground
                    dim: root.dim
                    fontFamily: root.fontFamily
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
              text: root.trim(root.query).length > 0 ? "No matches" : "No open todos in this file"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
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
              font.pixelSize: Style.font.icon
              width: Style.space(28)
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(44)
              text: root.dragGhostText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
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
            onTextChanged: root.query = text
            Keys.onEscapePressed: {
              root.showFilter = false
              root.query = ""
            }
          }

          Item {
            width: parent.width
            height: Style.spacing.controlHeight

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
              visible: root.appVersion !== ""
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: visible ? versionLabel.implicitWidth : 0
              height: parent.height

              CenteredLabel {
                id: versionLabel
                text: root.appVersion
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
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
