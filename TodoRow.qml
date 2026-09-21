import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: row

  property var item: ({})
  property int openIndex: -1
  property bool editing: false
  property bool draggable: false
  property bool dragging: false
  property bool listDragging: false
  property bool animateShift: true
  property bool striped: false
  property real shiftY: 0
  property string draft: ""
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: "JetBrainsMono Nerd Font"
  property int fontWeight: 700
  property int fontSize: 16
  property int iconSize: 18
  property string previewId: ""
  property bool previewDone: false
  property bool hideWhenDone: false

  signal completeClicked()
  signal editRequested()
  signal editAccepted(string text)
  signal editCancelled()
  signal menuRequested(real globalX, real globalY)
  signal dragBegan(real globalY)
  signal dragUpdated(real globalY)
  signal dragFinished(real globalY)

  readonly property int pad: 10
  readonly property int iconBox: Math.max(iconSize, 22)
  readonly property bool previewMatch: !!(item && previewId && (item.id === previewId || item.uid === previewId))
  readonly property bool doneLook: previewMatch ? previewDone : !!(item && item.isCompleted)
  readonly property real labelHeight: {
    if (row.editing) return Math.max(fontSize, editField.implicitHeight)
    return Math.max(fontSize, itemLabel.implicitHeight)
  }
  readonly property real naturalHeight: Math.max(iconBox, labelHeight) + pad * 2
  property bool allowTuck: false
  readonly property bool tuckAway: hideWhenDone && doneLook && allowTuck && !row.editing

  implicitHeight: tuckAway ? 0 : naturalHeight
  height: implicitHeight
  clip: true
  opacity: dragging ? 0 : (tuckAway ? 0 : (doneLook ? 0.72 : 1))
  z: dragging ? 0 : 1

  Behavior on implicitHeight {
    enabled: row.hideWhenDone
    NumberAnimation { duration: 260; easing.type: Easing.InCubic }
  }
  Behavior on opacity {
    enabled: row.animateShift
    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
  }

  transform: Translate {
    y: row.shiftY
    Behavior on y {
      enabled: row.animateShift
      NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
  }

  onDoneLookChanged: {
    if (doneLook) checkPop.start()
    if (hideWhenDone && doneLook) allowTuck = true
    if (!doneLook) allowTuck = false
  }

  Component.onCompleted: {
    if (hideWhenDone && doneLook) Qt.callLater(function () { row.allowTuck = true })
  }

  function globalYAt(mouse) {
    return dragArea.mapToItem(null, mouse.x, mouse.y).y
  }

  Rectangle {
    anchors.fill: parent
    color: row.foreground
    opacity: row.striped ? Style.normalFillAlpha : 0
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: 2
    radius: Style.cornerRadius
    color: row.foreground
    opacity: dragArea.containsMouse && !row.dragging && !row.listDragging ? Style.hoverFillAlpha : 0
    Behavior on opacity { NumberAnimation { duration: 90 } }
  }

  MouseArea {
    id: dragArea
    anchors.fill: parent
    enabled: !row.editing
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    preventStealing: row.draggable
    cursorShape: {
      if (!row.draggable) return Qt.ArrowCursor
      return row.listDragging || row.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    }
    property bool moving: false
    property bool pressOnCheck: false
    property real originGlobalY: 0

    onPressed: function (mouse) {
      if (mouse.button === Qt.RightButton) {
        var g = dragArea.mapToItem(null, mouse.x, mouse.y)
        row.menuRequested(g.x, g.y)
        mouse.accepted = true
        return
      }
      moving = false
      pressOnCheck = false
      originGlobalY = row.globalYAt(mouse)
    }
    onPositionChanged: function (mouse) {
      if (!pressed || mouse.buttons !== Qt.LeftButton) return
      if (pressOnCheck || !row.draggable) return
      var gy = row.globalYAt(mouse)
      if (!moving && Math.abs(gy - originGlobalY) > 5) {
        moving = true
        row.dragBegan(gy)
      }
      if (moving) row.dragUpdated(gy)
    }
    onReleased: function (mouse) {
      if (mouse.button === Qt.RightButton) return
      if (pressOnCheck) {
        pressOnCheck = false
        moving = false
        return
      }
      if (moving) {
        row.dragFinished(row.globalYAt(mouse))
        moving = false
        return
      }
      row.editRequested()
      moving = false
    }
    onCanceled: {
      if (moving) row.dragFinished(originGlobalY)
      moving = false
    }
  }

  Item {
    id: checkBox
    width: iconBox
    height: iconBox
    anchors.left: parent.left
    anchors.leftMargin: 8 + Math.min(item && item.indent ? item.indent : 0, 8) * 4
    anchors.verticalCenter: parent.verticalCenter

    Text {
      id: checkIcon
      anchors.centerIn: parent
      text: row.doneLook ? "󰄲" : "󰄱"
      color: row.doneLook ? Color.accent : dim
      font.family: fontFamily
      font.pixelSize: iconSize
      font.weight: fontWeight
      font.bold: true
      scale: checkHit.pressed ? 0.82 : 1
      Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }
    }

    SequentialAnimation {
      id: checkPop
      NumberAnimation { target: checkIcon; property: "scale"; to: 1.14; duration: 90; easing.type: Easing.OutCubic }
      NumberAnimation { target: checkIcon; property: "scale"; to: 1; duration: 120; easing.type: Easing.OutCubic }
    }

    MouseArea {
      id: checkHit
      anchors.fill: parent
      anchors.margins: -4
      z: 3
      cursorShape: Qt.PointingHandCursor
      preventStealing: true
      onPressed: dragArea.pressOnCheck = true
      onClicked: row.completeClicked()
    }
  }

  Text {
    id: itemLabel
    visible: !row.editing
    anchors.left: checkBox.right
    anchors.leftMargin: 8
    anchors.right: parent.right
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    text: item ? item.text : ""
    color: row.doneLook ? dim : foreground
    font.family: fontFamily
    font.pixelSize: fontSize
    font.weight: fontWeight
    font.bold: true
    wrapMode: Text.Wrap
    elide: Text.ElideNone
    maximumLineCount: 24
    verticalAlignment: Text.AlignVCenter
    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
  }

  Rectangle {
    id: strike
    visible: !row.editing
    height: 1
    radius: 1
    color: row.dim
    opacity: row.doneLook ? 0.55 : 0
    width: row.doneLook ? Math.min(itemLabel.contentWidth, itemLabel.width) : 0
    anchors.left: itemLabel.left
    anchors.verticalCenter: itemLabel.verticalCenter
    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  }

  TextField {
    id: editField
    visible: row.editing
    anchors.left: checkBox.right
    anchors.leftMargin: 8
    anchors.right: parent.right
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    text: row.draft
    foreground: row.foreground
    font.family: row.fontFamily
    font.pixelSize: row.fontSize
    font.weight: row.fontWeight
    onAccepted: row.editAccepted(text)
    Keys.onEscapePressed: row.editCancelled()
    onVisibleChanged: if (visible) forceActiveFocus()
  }
}
