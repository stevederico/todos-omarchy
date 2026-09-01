import QtQuick
import Quickshell
import qs.Commons

// Normal Hyprland-tiled window. Summon with:
//   omarchy-shell shell summon sd.todo-omarchy
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool closingFromHost: false
  readonly property bool opened: window.visible
  readonly property var view: viewLoader.item

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    if (view && view.reload) view.reload()
    if (view && view.pullRemote) view.pullRemote()
    Qt.callLater(function () { if (view && view.focusAdd) view.focusAdd() })
  }

  function close() {
    closingFromHost = true
    window.visible = false
    if (view && view.dismissOverlays) view.dismissOverlays()
    closingFromHost = false
  }

  function requestClose() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "sd.todo-omarchy")
    else
      root.close()
  }

  function injectView() {
    if (!view) return
    view.compact = false
    view.closeRequested.connect(root.requestClose)
  }

  FloatingWindow {
    id: window
    title: "Todos"
    visible: false
    color: Color.background
    implicitWidth: Style.space(520)
    implicitHeight: Style.space(640)
    minimumSize: Qt.size(Style.space(400), Style.space(480))

    onVisibleChanged: {
      if (visible) {
        if (view && view.reload) view.reload()
        if (view && view.pullRemote) view.pullRemote()
        Qt.callLater(function () { if (view) view.forceActiveFocus() })
      } else if (!root.closingFromHost && root.shell && typeof root.shell.hide === "function") {
        root.shell.hide((root.manifest && root.manifest.id) || "sd.todo-omarchy")
      }
    }

    Loader {
      id: viewLoader
      anchors.fill: parent
      source: Qt.resolvedUrl("../TodoView.qml")
      onLoaded: root.injectView()
    }
  }
}
