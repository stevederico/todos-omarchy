import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Checklist count for the bar. Click toggles the window app.
BarWidget {
  id: root
  moduleName: "sd.todo-omarchy"

  readonly property int openCount: panelLoader.item ? Number(panelLoader.item.openCount || 0) : 0
  readonly property bool opened: false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
    else if (panelLoader.item && panelLoader.item.reload) panelLoader.item.reload()
  }

  function syncRemote() {
    remoteSync.skipRebase = panelLoader.item ? panelLoader.item.notSynced === true : false
    remoteSync.enqueueAll()
  }

  property bool clickLock: false

  Timer {
    id: clickLockTimer
    interval: 120
    onTriggered: root.clickLock = false
  }

  function openWindow() {
    Quickshell.execDetached(["omarchy-shell", "-q", "shell", "summon", "sd.todo-omarchy"])
  }

  function closeWindow() {
    Quickshell.execDetached(["omarchy-shell", "-q", "shell", "hide", "sd.todo-omarchy"])
  }

  function toggleWindow() {
    if (root.clickLock) return
    root.clickLock = true
    clickLockTimer.restart()
    Quickshell.execDetached(["omarchy-shell", "-q", "shell", "toggle", "sd.todo-omarchy"])
  }

  function open() { root.openWindow() }
  function close() { root.closeWindow() }
  function toggle() { root.toggleWindow() }
  function togglePanel() { root.toggleWindow() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  GitRemote {
    id: remoteSync
    onSyncFinished: function (outcome) {
      if (panelLoader.item && panelLoader.item.applySyncOutcome)
        panelLoader.item.applySyncOutcome(outcome)
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("TodoPanel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "sd.todo-omarchy"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontFamily: "JetBrainsMono Nerd Font"
    fontSize: 18
    opticalSize: 22
    text: "󰄬"
    tooltipText: "Dottie-Todos · " + (root.openCount === 1 ? "1 open to-do" : (root.openCount + " open to-dos"))

    onPressed: function (b) {
      if (b === Qt.LeftButton || b === Qt.RightButton) root.toggleWindow()
      else if (b === Qt.MiddleButton) root.refresh()
    }
  }
}
