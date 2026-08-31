import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: row

  property var item: ({})
  property int openIndex: -1
  property bool canMoveUp: false
  property bool canMoveDown: false
  property bool expanded: false
  property bool editing: false
  property bool draggable: false
  property bool dropTarget: false
  property bool dragging: false
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
  signal moveUp()
  signal moveDown()
  signal dragBegan()
  signal dragUpdated(real globalY)
  signal dragFinished(real globalY)

  readonly property real rowHeight: Math.max(Style.space(36), content.implicitHeight + Style.space(8))
  height: rowHeight
  implicitHeight: rowHeight
  opacity: dragging ? 0.45 : (item && item.isCompleted ? 0.75 : 1)

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Math.max(1, Style.space(2))
    color: Color.accent
    visible: row.dropTarget && !row.dragging
    opacity: 0.9
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
      visible: row.draggable
      text: "󰇘"
      color: dim
      font.family: fontFamily
      font.pixelSize: Style.font.icon
      Layout.preferredWidth: Style.space(22)
      Layout.preferredHeight: Style.space(28)
      Layout.alignment: Qt.AlignVCenter
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter

      MouseArea {
        id: dragHandle
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.SizeVerCursor
        preventStealing: true
        property bool moving: false
        property real originGlobalY: 0

        onPressed: function (mouse) {
          moving = false
          originGlobalY = mapToItem(null, mouse.x, mouse.y).y
        }
        onPositionChanged: function (mouse) {
          if (!pressed) return
          var gy = mapToItem(null, mouse.x, mouse.y).y
          if (!moving && Math.abs(gy - originGlobalY) > 6) {
            moving = true
            row.dragging = true
            row.dragBegan()
          }
          if (moving) row.dragUpdated(gy)
        }
        onReleased: function (mouse) {
          if (moving) row.dragFinished(mapToItem(null, mouse.x, mouse.y).y)
          moving = false
          row.dragging = false
        }
        onCanceled: {
          if (moving) row.dragFinished(originGlobalY)
          moving = false
          row.dragging = false
        }
      }
    }

    Text {
      text: item && item.isCompleted ? "󰄲" : "󰄱"
      color: item && item.isCompleted ? Color.accent : dim
      font.family: fontFamily
      font.pixelSize: Style.font.icon
      Layout.preferredWidth: Style.space(28)
      Layout.preferredHeight: Style.space(28)
      Layout.alignment: Qt.AlignVCenter
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: Text.AlignHCenter

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
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
        wrapMode: row.expanded ? Text.Wrap : Text.NoWrap
        elide: row.expanded ? Text.ElideNone : Text.ElideRight
        maximumLineCount: row.expanded ? 8 : 1
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

      MouseArea {
        anchors.fill: parent
        enabled: !row.editing
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function (mouse) {
          if (mouse.button === Qt.RightButton) {
            row.menuRequested()
            return
          }
          if (mouse.clickCount === 2) row.editRequested()
          else row.expandClicked()
        }
      }
    }
  }
}
