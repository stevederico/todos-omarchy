import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TodoStore.js" as Store

// Checklist count for the bar. Click toggles the window app.
BarWidget {
  id: root
  moduleName: "sd.dottie-todo-omarchy"

  property int openCount: 0
  readonly property bool opened: false
  readonly property string openCountPath: (Quickshell.env("XDG_RUNTIME_DIR") || ((Quickshell.env("HOME") || "") + "/.config/dottie-todo-omarchy")) + "/dottie-todo-omarchy-open-count"

  function applyCountText(raw) {
    var n = parseInt(String(raw || "0"), 10)
    root.openCount = isFinite(n) && n > 0 ? n : 0
  }

  function refresh() {
    Store.requestRefresh()
  }

  property bool clickLock: false

  Timer {
    id: clickLockTimer
    interval: 120
    onTriggered: root.clickLock = false
  }

  function openWindow() {
    Quickshell.execDetached(["omarchy-shell", "-q", "shell", "summon", "sd.dottie-todo-omarchy"])
  }

  function closeWindow() {
    Quickshell.execDetached(["omarchy-shell", "-q", "shell", "hide", "sd.dottie-todo-omarchy"])
  }

  function toggleWindow() {
    if (root.clickLock) return
    root.clickLock = true
    clickLockTimer.restart()
    Quickshell.execDetached(["omarchy-shell", "-q", "shell", "toggle", "sd.dottie-todo-omarchy"])
  }

  function open() { root.openWindow() }
  function close() { root.closeWindow() }
  function toggle() { root.toggleWindow() }
  function togglePanel() { root.toggleWindow() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: Store.subscribeCount(function (n) { root.openCount = n })

  FileView {
    path: root.openCountPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyCountText(text())
    onFileChanged: reload()
  }

  IpcHandler {
    target: "sd.dottie-todo-omarchy"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  IpcHandler {
    target: "sd.dottie-todos-omarchy"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function capture(arg: string): string {
      Quickshell.execDetached(["omarchy-shell", "-q", "shell", "call", "sd.dottie-todo-omarchy", "capture", arg || "{}"])
      return "ok"
    }
  }

  IpcHandler {
    target: "sd.todo-omarchy"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function capture(arg: string): string {
      Quickshell.execDetached(["omarchy-shell", "-q", "shell", "call", "sd.dottie-todo-omarchy", "capture", arg || "{}"])
      return "ok"
    }
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
