import QtQuick

// Center the ink box (ascent+descent, no line leading) in the parent.
Text {
  id: root

  readonly property real inkHeight: metrics.ascent + metrics.descent

  FontMetrics {
    id: metrics
    font: root.font
  }

  width: implicitWidth
  height: inkHeight
  x: Math.round((parent.width - width) / 2)
  y: Math.round((parent.height - inkHeight) / 2)
  horizontalAlignment: Text.AlignHCenter
  verticalAlignment: Text.AlignVCenter
}
