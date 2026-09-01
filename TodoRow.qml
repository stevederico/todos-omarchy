import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: row

  property var item: ({})
  property int openIndex: -1
  property bool expanded: false
  property bool editing: false
  property bool draggable: false
  property bool dragging: false
  property bool listDragging: false
  property bool animateShift: true
  property real shiftY: 0
  property string draft: ""
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family

  signal completeClicked()
  signal expandClicked()
  signal editRequested()
  signal editAccepted(string text)
  signal editCancelled()
  signal menuRequested()
  signal dragBegan(real globalY)
  signal dragUpdated(real globalY)
  signal dragFinished(real globalY)

  readonly property real rowHeight: Math.max(Style.space(36), content.implicitHeight + Style.space(8))
  height: rowHeight
  implicitHeight: rowHeight
  opacity: dragging ? 0 : (item && item.isCompleted ? 0.75 : 1)
  z: dragging ? 0 : 1

  Behavior on opacity {
    enabled: row.animateShift
    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
  }

  transform: Translate {
    y: row.shiftY
    Behavior on y {
      enabled: row.animateShift
      NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
  }

  function globalYAt(mouse) {
    return dragArea.mapToItem(null, mouse.x, mouse.y).y
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: Style.space(2)
    radius: Style.cornerRadius
    color: row.foreground
    opacity: dragArea.containsMouse && !row.dragging && !row.listDragging ? 0.06 : 0
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
    property real originGlobalY: 0

    onPressed: function (mouse) {
      if (mouse.button === Qt.RightButton) {
        row.menuRequested()
        mouse.accepted = true
        return
      }
      moving = false
      originGlobalY = row.globalYAt(mouse)
    }
    onPositionChanged: function (mouse) {
      if (!pressed || mouse.buttons !== Qt.LeftButton) return
      if (!row.draggable) return
      var gy = row.globalYAt(mouse)
      if (!moving && Math.abs(gy - originGlobalY) > 5) {
        moving = true
        row.dragBegan(gy)
      }
      if (moving) row.dragUpdated(gy)
    }
    onReleased: function (mouse) {
      if (mouse.button === Qt.RightButton) return
      if (moving) {
        row.dragFinished(row.globalYAt(mouse))
        moving = false
        return
      }
      if (mouse.clickCount >= 2) row.editRequested()
      else row.expandClicked()
      moving = false
    }
    onCanceled: {
      if (moving) row.dragFinished(originGlobalY)
      moving = false
    }

    RowLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8) + Math.min(item && item.indent ? item.indent : 0, 8) * 4
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        id: checkIcon
        text: item && item.isCompleted ? "󰄲" : "󰄱"
        color: item && item.isCompleted ? Color.accent : dim
        font.family: fontFamily
        font.pixelSize: Style.font.icon
        Layout.preferredWidth: Style.space(28)
        Layout.preferredHeight: Style.space(28)
        Layout.alignment: Qt.AlignVCenter
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        scale: checkHit.pressed ? 0.82 : 1
        Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }

        MouseArea {
          id: checkHit
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          cursorShape: Qt.PointingHandCursor
          preventStealing: true
          onClicked: row.completeClicked()
        }
      }

      Item {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredHeight: row.editing ? editField.implicitHeight : Math.max(Style.space(28), itemLabel.implicitHeight)

        Text {
          id: itemLabel
          visible: !row.editing
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: item ? item.text : ""
          color: item && item.isCompleted ? dim : foreground
          font.family: fontFamily
          font.pixelSize: Style.font.body
          font.strikeout: item && item.isCompleted
          wrapMode: Text.Wrap
          elide: Text.ElideNone
          maximumLineCount: 8
          verticalAlignment: Text.AlignVCenter
        }

        TextField {
          id: editField
          visible: row.editing
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: row.draft
          foreground: row.foreground
          onAccepted: row.editAccepted(text)
          Keys.onEscapePressed: row.editCancelled()
          onVisibleChanged: if (visible) forceActiveFocus()
        }
      }
    }
  }
}
