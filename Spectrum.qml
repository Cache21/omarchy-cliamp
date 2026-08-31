import QtQuick
import qs.Commons
import "Model.js" as Model

// Bottom-anchored bar spectrum. Fed `bands` (any length, ~0..1 from
// `cliamp visstream`), resampled to `cols` columns. All-Rectangle +
// `Behavior on height` — no Canvas, matching the omarchy house style
// (plugins/panels/wifiqr/Panel.qml renders its QR the same way).
Item {
  id: root

  property var bands: []
  // Default: the theme accent (Omarchy derives it from the theme's `accent`
  // key or ANSI color4/blue), so the bars pick up e.g. Catppuccin blue. Falls
  // back to `urgent` on the rare theme whose accent equals the foreground, so
  // the spectrum never blends into the white now-playing text in front of it.
  property color barColor: {
    var a = Color.accent, f = Color.foreground
    var d = Math.abs(a.r - f.r) + Math.abs(a.g - f.g) + Math.abs(a.b - f.b)
    return d > 0.22 ? a : Color.urgent
  }
  property real gap: Math.max(1, Math.round(width / 90))
  property real minBar: 1
  // 0 = derive a sensible column count from the available width.
  property int barCount: 0
  // Falling peak caps — nice in the panel, off in the thin bar strip.
  property bool peaks: false
  property real peakDecay: 0.03

  readonly property int cols: barCount > 0
    ? barCount
    : Math.max(6, Math.min(48, Math.round(width / Math.max(4, height * 0.22))))
  readonly property var levels: Model.sampleBands(bands, cols)

  property var peakLevels: []
  function resetPeaks() {
    var p = new Array(cols)
    for (var i = 0; i < cols; i++) p[i] = 0
    peakLevels = p
  }
  onColsChanged: resetPeaks()
  Component.onCompleted: resetPeaks()

  onLevelsChanged: {
    if (!peaks || peakLevels.length !== cols) return
    var p = peakLevels.slice()
    for (var i = 0; i < cols; i++) {
      var lv = levels[i] || 0
      if (lv > (p[i] || 0)) p[i] = lv
    }
    peakLevels = p
  }

  Timer {
    interval: 40
    running: root.peaks && root.visible
    repeat: true
    onTriggered: {
      if (root.peakLevels.length !== root.cols) return
      var p = root.peakLevels.slice()
      for (var i = 0; i < root.cols; i++) p[i] = Math.max(0, (p[i] || 0) - root.peakDecay)
      root.peakLevels = p
    }
  }

  Row {
    anchors.fill: parent
    spacing: root.gap

    Repeater {
      model: root.cols

      Item {
        id: col
        required property int index
        width: (root.width - root.gap * (root.cols - 1)) / root.cols
        height: root.height

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          radius: Math.min(width, 2)
          color: root.barColor
          height: Math.max(root.minBar, (root.levels[col.index] || 0) * root.height)

          Behavior on height {
            NumberAnimation { duration: 70; easing.type: Easing.OutQuad }
          }
        }

        Rectangle {
          readonly property real level: root.peakLevels[col.index] || 0
          visible: root.peaks && level > 0.03
          width: parent.width
          height: Math.max(1, root.minBar)
          radius: height / 2
          color: root.barColor
          opacity: 0.9
          y: parent.height - Math.max(height, level * root.height)

          Behavior on y {
            NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
          }
        }
      }
    }
  }
}
