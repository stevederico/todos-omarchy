import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "sd.todo-omarchy"
  ipcTarget: "sd.todo-omarchy"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property int openCount: view.openCount

  function reload() { view.reload() }
  function openInEditor() { view.openInEditor() }
  function openWindow() {
    root.close()
    Quickshell.execDetached(["omarchy-shell", "-q", "shell", "summon", "sd.todo-omarchy"])
  }

  function open() {
    view.reload()
    root.controller.show()
    Qt.callLater(function () {
      if (root.opened) setCenterHoverRevealSuppressed(true)
      keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    view.dismissOverlays()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  onOpenedChanged: if (opened) {
    view.reload()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(Style.space(580))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: view.fieldFocused
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onActivateRequested: view.focusAdd()
      onTextKey: function (t) {
        if (t === "n" || t === "N") view.focusAdd()
        else if (t === "/") view.focusFilter()
        else if (t === "r" || t === "R") view.reload()
        else if (t === "w" || t === "W") root.openWindow()
      }

      TodoView {
        id: view
        anchors.fill: parent
        bar: root.bar
        compact: true
        onOpenWindowRequested: root.openWindow()
        onCloseRequested: root.close()
      }
    }
  }
}
