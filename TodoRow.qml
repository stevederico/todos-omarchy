import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: row

  property var item: ({})
  property bool canMoveUp: false
  property bool canMoveDown: false
  property bool expanded: false
  property bool editing: false
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

  height: Math.max(Style.space(32), rowInner.implicitHeight + Style.space(6))

  Row {
    id: rowInner
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: Style.space(8) + Math.min(item && item.indent ? item.indent : 0, 8) * 4
    rightPadding: Style.space(8)
    spacing: Style.space(8)

    Text {
      text: item && item.isCompleted ? "󰄲" : "󰄱"
      color: item && item.isCompleted ? Color.accent : dim
      font.family: fontFamily
      font.pixelSize: Style.font.icon
      width: Style.space(28)
      height: Style.space(28)
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: Text.AlignHCenter

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: row.completeClicked()
      }
    }

    Item {
      width: Math.max(40, rowInner.width - Style.space(28) - Style.space(72) - Style.space(32))
      height: row.editing ? editField.implicitHeight : itemLabel.implicitHeight

      Text {
        id: itemLabel
        visible: !row.editing
        width: parent.width
        text: item ? item.text : ""
        color: item && item.isCompleted ? dim : foreground
        font.family: fontFamily
        font.pixelSize: Style.font.body
        font.strikeout: item && item.isCompleted
        wrapMode: row.expanded ? Text.Wrap : Text.NoWrap
        elide: row.expanded ? Text.ElideNone : Text.ElideRight
        maximumLineCount: row.expanded ? 8 : 1
      }

      TextField {
        id: editField
        visible: row.editing
        width: parent.width
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

    Row {
      visible: item && !item.isCompleted
      spacing: Style.space(2)

      PanelActionButton {
        iconText: "󰁝"
        enabled: row.canMoveUp
        foreground: row.foreground
        tooltipText: "Move up"
        onClicked: if (row.canMoveUp) row.moveUp()
      }
      PanelActionButton {
        iconText: "󰁅"
        enabled: row.canMoveDown
        foreground: row.foreground
        tooltipText: "Move down"
        onClicked: if (row.canMoveDown) row.moveDown()
      }
    }
  }
}
