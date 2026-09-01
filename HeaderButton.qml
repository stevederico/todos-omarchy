import QtQuick
import qs.Commons
import qs.Ui

// Caption/icon chip. Ink-centered so nerd-font leading does not lift glyphs.
BorderSurface {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property bool selected: false
  property bool bordered: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real fontSize: iconText !== "" ? Style.font.icon : Style.font.caption
  property real horizontalPadding: Style.spacing.controlPaddingX

  signal clicked()
  signal rightClicked()

  implicitWidth: iconText !== ""
    ? height
    : (label.implicitWidth + horizontalPadding * 2)
  implicitHeight: Style.spacing.controlHeight
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

  CenteredLabel {
    id: label
    visible: root.iconText === ""
    text: root.text
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: root.selected
  }

  CenteredLabel {
    id: iconLabel
    visible: root.iconText !== ""
    text: root.iconText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
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
