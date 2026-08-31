import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TodoDocument.js" as Doc
import "Settings.js" as Settings

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
  readonly property string settingsPath: configDir + "/settings.json"
  readonly property string commitMsgPath: configDir + "/commit-msg"

  property var sources: []
  property string selectedID: ""
  property var lines: []
  property var sections: []
  property int openCount: 0
  property int completedCount: 0
  property string filePath: ""
  property string lastError: ""
  property string lastStatus: ""
  property bool isBusy: false
  property bool fileMissing: false
  property bool changelogPresent: false
  property bool suppressWatch: false
  property int statusToken: 0
  property bool gitCommit: false
  property bool gitPush: false
  property bool updateChangelog: false

  property string query: ""
  property bool showCompleted: false
  property bool showAddField: false
  property bool showAddList: false
  property string newTodoText: ""
  property string addListPath: ""
  property string renameID: ""
  property string renameText: ""
  property string expandedId: ""
  property string editingId: ""
  property string editDraft: ""
  property var ctx: null

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

  function persistSettings() {
    mkdirProc.running = true
    settingsFile.setText(Settings.serializeSettings({
      gitCommit: gitCommit,
      gitPush: gitPush,
      updateChangelog: updateChangelog
    }))
  }

  function applySettings(raw) {
    var next = Settings.parseSettings(raw)
    gitCommit = next.gitCommit
    gitPush = next.gitPush
    updateChangelog = next.updateChangelog
  }

  function cycleGit() {
    if (!gitCommit) {
      gitCommit = true
      gitPush = false
    } else if (!gitPush) {
      gitPush = true
    } else {
      gitCommit = false
      gitPush = false
    }
    persistSettings()
  }

  function toggleChangelog() {
    updateChangelog = !updateChangelog
    persistSettings()
  }

  function gitSyncPath() {
    var url = String(Qt.resolvedUrl("scripts/git-sync.sh") || "")
    if (url.indexOf("file://") === 0) return url.slice(7)
    return url
  }

  readonly property string gitLabel: !gitCommit ? "Git: off" : (gitPush ? "Git: push" : "Git: commit")

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
    expandedId = ""
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
    lastStatus = status
    if (!gitCommit) {
      isBusy = false
      return
    }
    statusToken += 1
    var token = statusToken
    commitMsgFile.setText(String(message || ""))
    var args = [gitSyncPath(), "--dir", dirname(filePath), "--message-file", commitMsgPath]
    if (gitPush) args.push("--push")
    args.push("--")
    args.push(filePath)
    if (extraFiles) {
      for (var i = 0; i < extraFiles.length; i++) args.push(extraFiles[i])
    }
    gitProc.running = false
    gitProc.command = args
    gitProc.token = token
    gitProc.status = status
    gitProc.running = true
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
      if (result.completed && changelogPresent && updateChangelog) {
        var existing = changelogFile.text()
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

  function reload() {
    todoFile.reload()
  }

  function openInEditor() {
    if (filePath !== "") Quickshell.execDetached(["xdg-open", filePath])
  }

  function reveal() {
    if (filePath !== "") Quickshell.execDetached(["xdg-open", dirname(filePath)])
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
      if (!item.isCompleted) {
        out.push("Move Up")
        out.push("Move Down")
      }
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
        Quickshell.execDetached(["xdg-open", dirname(src.path)])
      } else if (action === "Remove Tab") {
        removeSource(src.id)
      }
      return
    }
    if (kind === "item" && item) {
      if (action === "Reopen" || action === "Mark Complete") complete(item)
      else if (action === "Move Up") moveItem(item, -1)
      else if (action === "Move Down") moveItem(item, 1)
      else if (action === "Edit…") {
        editingId = item.id
        editDraft = item.text
        expandedId = item.id
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
    filterField.forceActiveFocus()
  }

  function dismissOverlays() {
    showAddField = false
    showAddList = false
    editingId = ""
    ctx = null
    renameID = ""
  }

  Timer {
    id: suppressTimer
    interval: 1500
    onTriggered: root.suppressWatch = false
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

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applySettings(text())
    onLoadFailed: root.applySettings("")
  }

  FileView {
    id: commitMsgFile
    path: root.commitMsgPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
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
    onFileChanged: if (!root.suppressWatch) reload()
    onLoaded: if (!root.suppressWatch) root.applyText(text())
    onLoadFailed: root.applyMissing()
  }

  FileView {
    id: changelogFile
    path: root.changelogPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.changelogPresent = true
    onLoadFailed: root.changelogPresent = false
  }

  Component.onCompleted: mkdirProc.running = true

  Keys.onPressed: function (event) {
    if (root.fieldFocused) return
    if (event.key === Qt.Key_Escape) {
      if (root.ctx !== null || root.showAddField || root.showAddList || root.renameID !== "") {
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
      root.reload()
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
            width: parent.width
            spacing: Style.space(8)

            Flickable {
              width: Math.max(80, parent.width - countChip.width - addListBtn.width - addBtn.width - Style.space(32))
              height: addBtn.height
              contentWidth: tabRow.implicitWidth
              clip: true
              flickableDirection: Flickable.HorizontalFlick
              boundsBehavior: Flickable.StopAtBounds

              Row {
                id: tabRow
                spacing: Style.space(4)

                Repeater {
                  model: root.sources
                  Button {
                    required property var modelData
                    text: modelData.title
                    selected: modelData.id === root.selectedID
                    fontSize: Style.font.caption
                    tooltipText: modelData.path
                    onClicked: root.selectSource(modelData.id)
                    onRightClicked: root.ctx = { kind: "tab", source: modelData }
                  }
                }
              }
            }

            Rectangle {
              id: countChip
              width: countLabel.implicitWidth + Style.space(12)
              height: addBtn.height
              radius: height / 2
              color: Style.selectedFillFor(root.foreground, Color.accent)
              Text {
                id: countLabel
                anchors.centerIn: parent
                text: String(root.openCount)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Button {
              id: addListBtn
              text: "Add List"
              fontSize: Style.font.caption
              bordered: true
              tooltipText: "Add another markdown todo file"
              onClicked: {
                root.showAddList = !root.showAddList
                root.showAddField = false
                if (root.showAddList) listPathField.forceActiveFocus()
              }
            }

            PanelActionButton {
              id: addBtn
              iconText: "󰐕"
              tooltipText: root.showAddField ? "Hide new to-do" : "Add to-do"
              foreground: root.foreground
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
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
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
                  text: sectionCol.modelData.title
                  foreground: root.foreground
                  leftPadding: Style.space(12)
                  topPadding: Style.space(12)
                  bottomPadding: Style.space(4)
                }

                Repeater {
                  model: root.openItems(sectionCol.modelData)

                  TodoRow {
                    required property var modelData
                    required property int index
                    width: listColumn.width
                    item: modelData
                    canMoveUp: index > 0 && root.trim(root.query).length === 0
                    canMoveDown: index < root.openItems(sectionCol.modelData).length - 1 && root.trim(root.query).length === 0
                    expanded: root.expandedId === modelData.id
                    editing: root.editingId === modelData.id
                    draft: root.editDraft
                    foreground: root.foreground
                    dim: root.dim
                    fontFamily: root.fontFamily
                    onCompleteClicked: root.complete(modelData)
                    onExpandClicked: root.expandedId = root.expandedId === modelData.id ? "" : modelData.id
                    onEditRequested: {
                      root.editingId = modelData.id
                      root.editDraft = modelData.text
                      root.expandedId = modelData.id
                    }
                    onEditAccepted: function (text) {
                      root.editingId = ""
                      root.saveEdit(modelData, text)
                    }
                    onEditCancelled: root.editingId = ""
                    onMenuRequested: root.ctx = { kind: "item", item: modelData }
                    onMoveUp: root.moveItem(modelData, -1)
                    onMoveDown: root.moveItem(modelData, 1)
                  }
                }

                Repeater {
                  model: root.showCompleted ? root.doneItems(sectionCol.modelData) : []

                  TodoRow {
                    required property var modelData
                    width: listColumn.width
                    item: modelData
                    canMoveUp: false
                    canMoveDown: false
                    expanded: root.expandedId === modelData.id
                    editing: root.editingId === modelData.id
                    draft: root.editDraft
                    foreground: root.foreground
                    dim: root.dim
                    fontFamily: root.fontFamily
                    onCompleteClicked: root.complete(modelData)
                    onExpandClicked: root.expandedId = root.expandedId === modelData.id ? "" : modelData.id
                    onEditRequested: {
                      root.editingId = modelData.id
                      root.editDraft = modelData.text
                      root.expandedId = modelData.id
                    }
                    onEditAccepted: function (text) {
                      root.editingId = ""
                      root.saveEdit(modelData, text)
                    }
                    onEditCancelled: root.editingId = ""
                    onMenuRequested: root.ctx = { kind: "item", item: modelData }
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

        Column {
          id: footer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.space(8)

          TextField {
            id: filterField
            width: parent.width
            placeholderText: "Filter"
            text: root.query
            foreground: root.foreground
            onTextChanged: root.query = text
          }

          Flow {
            width: parent.width
            spacing: Style.space(8)
            Button { text: "Refresh"; fontSize: Style.font.caption; onClicked: root.reload() }
            Button { text: "Open File"; fontSize: Style.font.caption; onClicked: root.openInEditor() }
            Button { text: "Reveal"; fontSize: Style.font.caption; onClicked: root.reveal() }
            Button {
              visible: root.compact
              text: "Open Window"
              fontSize: Style.font.caption
              bordered: true
              onClicked: root.openWindowRequested()
            }
            Button {
              visible: root.completedCount > 0
              text: root.showCompleted ? "Hide Completed" : ("Show Completed (" + root.completedCount + ")")
              fontSize: Style.font.caption
              onClicked: root.showCompleted = !root.showCompleted
            }
            Button {
              text: root.gitLabel
              fontSize: Style.font.caption
              tooltipText: "Off writes the file only. Commit stays local. Push sends to the file's upstream."
              onClicked: root.cycleGit()
            }
            Button {
              text: root.updateChangelog ? "Changelog: on" : "Changelog: off"
              fontSize: Style.font.caption
              tooltipText: "When on, completing an item also appends to a sibling CHANGELOG.md"
              onClicked: root.toggleChangelog()
            }
          }

          Text {
            width: parent.width
            text: root.filePath
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }
        }

        Rectangle {
          visible: root.ctx !== null
          anchors.fill: parent
          color: Qt.rgba(0, 0, 0, 0.28)
          MouseArea { anchors.fill: parent; onClicked: root.ctx = null }
        }

        BorderSurface {
          visible: root.ctx !== null
          width: ctxColumn.implicitWidth + Style.space(20)
          height: ctxColumn.implicitHeight + Style.space(20)
          anchors.centerIn: parent
          color: Color.popups.background
          radius: Style.cornerRadius

          Column {
            id: ctxColumn
            anchors.centerIn: parent
            spacing: Style.space(4)

            Repeater {
              model: root.ctxActions()
              Button {
                required property string modelData
                text: modelData
                fontSize: Style.font.caption
                onClicked: root.runCtx(modelData)
              }
            }
          }
        }
      }
}
