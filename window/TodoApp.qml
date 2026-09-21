import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons

// Normal Hyprland-tiled window. Summon with:
//   omarchy-shell shell summon sd.dottie-todos-omarchy
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool closingFromHost: false
  property string captureHint: "Enter adds · Esc closes"
  readonly property bool opened: window.visible
  readonly property var view: viewLoader.item

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    if (view && view.reload) view.reload()
    Qt.callLater(function () { if (view) view.forceActiveFocus() })
  }

  function close() {
    closingFromHost = true
    window.visible = false
    if (view && view.dismissOverlays) view.dismissOverlays()
    closingFromHost = false
  }

  function requestClose() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "sd.dottie-todos-omarchy")
    else
      root.close()
  }

  function injectView() {
    if (!view) return
    view.compact = false
  }

  function syncRemote() {
    if (!remoteLoader.item || !remoteLoader.item.enqueueAll) return
    remoteLoader.item.skipRebase = view && view.notSynced === true
    remoteLoader.item.enqueueAll()
  }

  function capture(_arg) {
    if (captureWindow.visible) {
      captureWindow.visible = false
      return "closed"
    }
    captureHint = "Enter adds · Esc closes"
    captureField.text = ""
    captureWindow.visible = true
    return "ok"
  }

  function submitCapture() {
    if (!view || !view.addTodo) return
    var text = captureField.text.replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "")
    if (text.length === 0) return
    if (view.isBusy) {
      captureHint = "Busy — try again"
      return
    }
    view.addTodo(text)
    captureField.text = ""
    captureWindow.visible = false
  }

  Loader {
    id: remoteLoader
    source: Qt.resolvedUrl("../GitRemote.qml")
  }

  Connections {
    target: remoteLoader.item
    function onSyncFinished(outcome) {
      if (view && view.applySyncOutcome) view.applySyncOutcome(outcome)
    }
  }

  FloatingWindow {
    id: window
    title: "Dottie-Todos"
    visible: false
    color: Color.background
    implicitWidth: Style.space(520)
    implicitHeight: Style.space(640)
    minimumSize: Qt.size(Style.space(400), Style.space(480))

    onVisibleChanged: {
      root.syncRemote()
      if (visible) {
        if (view && view.reload) view.reload()
        Qt.callLater(function () { if (view) view.forceActiveFocus() })
      } else if (!root.closingFromHost && root.shell && typeof root.shell.hide === "function") {
        root.shell.hide((root.manifest && root.manifest.id) || "sd.dottie-todos-omarchy")
      }
    }

    Loader {
      id: viewLoader
      anchors.fill: parent
      source: Qt.resolvedUrl("../TodoView.qml")
      onLoaded: root.injectView()
    }
  }

  Connections {
    target: viewLoader.item
    function onCloseRequested() { root.requestClose() }
  }

  FloatingWindow {
    id: captureWindow
    title: "New todo"
    visible: false
    color: Color.background
    implicitWidth: 1280
    implicitHeight: 720
    minimumSize: Qt.size(720, 420)

    onVisibleChanged: if (visible) captureFocus.restart()

    Timer {
      id: captureFocus
      interval: 80
      onTriggered: {
        captureField.forceActiveFocus()
        Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "title:^New todo$"])
      }
    }

    TextArea {
      id: captureField
      anchors.fill: parent
      anchors.margins: 36
      anchors.bottomMargin: 64
      placeholderText: "New to-do"
      wrapMode: TextEdit.Wrap
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 32
      font.weight: 700
      color: Color.foreground
      selectionColor: Color.accent
      selectedTextColor: Color.foreground
      placeholderTextColor: Qt.darker(Color.foreground, 1.6)
      background: null
      selectByMouse: true

      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
          captureWindow.visible = false
          event.accepted = true
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
          root.submitCapture()
          event.accepted = true
        }
      }
    }

    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 28
      text: captureHint
      color: Qt.darker(Color.foreground, 1.55)
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 16
      font.weight: 700
    }
  }

}
