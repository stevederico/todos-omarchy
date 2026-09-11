import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Checklist count for the bar. Click toggles the window app (not the
// exclusive KeyboardPanel overlay, which steals all other windows).
BarWidget {
  id: root
  moduleName: "sd.todo-omarchy"

  readonly property int openCount: panelLoader.item ? Number(panelLoader.item.openCount || 0) : 0

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

  function dismissOverlay() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function openWindow() {
    root.dismissOverlay()
    Quickshell.execDetached(["omarchy-shell", "-q", "shell", "summon", "sd.todo-omarchy"])
  }

  function hideWindow() {
    root.dismissOverlay()
    Quickshell.execDetached(["omarchy-shell", "-q", "shell", "hide", "sd.todo-omarchy"])
  }

  function toggleWindow() {
    root.dismissOverlay()
    Quickshell.execDetached(["omarchy-shell", "-q", "shell", "toggle", "sd.todo-omarchy"])
  }

  function togglePanel() { root.toggleWindow() }

  readonly property bool opened: false

  function open() { root.openWindow() }
  function close() { root.hideWindow() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property real openPanelIndicatorWidth: button.glyphPaintedWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

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
    function toggle(): void { root.toggleWindow() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰄬"
    tooltipText: (root.openCount === 1 ? "1 open to-do" : (root.openCount + " open to-dos")) + " · click for window"

    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.toggleWindow()
      }
    }
  }
}
