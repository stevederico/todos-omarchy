import QtQuick
import qs.Commons
import qs.Ui

// Caption chip. Text fills the box so glyphs center, unlike Button's font-box.
BorderSurface {
  id: root

  property string text: ""
  property string tooltipText: ""
  property bool selected: false
  property bool bordered: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.caption
  property real horizontalPadding: Style.spacing.controlPaddingX

  signal clicked()
  signal rightClicked()

  implicitWidth: label.implicitWidth + horizontalPadding * 2
  implicitHeight: Math.max(Style.space(22), fontSize + Style.spacing.sm * 2)
  radius: Style.cornerRadius

  readonly property bool hot: mouse.containsMouse
  color: mouse.pressed ? Style.pressedFillFor(foreground, Color.accent)
    : hot ? Style.hoverFillFor(foreground, Color.accent)
    : selected ? Style.selectedFillFor(foreground, Color.accent)
    : "transparent"
  borderSpec: bordered
    ? (hot ? Border.controlSpec("hover-cursor", foreground, Color.accent)
           : Border.controlSpec("normal", foreground, Color.accent))
    : Border.none()

  Text {
    id: label
    anchors.fill: parent
    text: root.text
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: root.selected
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function (event) {
      if (event.button === Qt.RightButton) root.rightClicked()
      else root.clicked()
    }
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && mouse.containsMouse
    text: root.tooltipText
    fontFamily: root.fontFamily
  }
}
