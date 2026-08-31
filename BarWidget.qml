import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar item: transport glyph + scrolling now-playing label, with a popup panel.
//   left   = play/pause
//   middle = next track
//   right  = open/close the panel
//   wheel  = volume +/- 1 dB
BarWidget {
  id: root
  moduleName: "io.github.cache21.cliamp"

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("io.github.cache21.cliamp") : null

  readonly property int maxLabelWidth: Math.max(80, Number(setting("maxLabelWidth", 220)))
  readonly property bool showArtist: setting("showArtist", true) === true
  readonly property bool showYtRadioDot: setting("showYtRadioDot", true) === true
  readonly property bool hideWhenStopped: setting("hideWhenStopped", false) === true

  readonly property bool active: !!svc && svc.running
  readonly property string displayText: {
    if (!svc || !svc.running) return "cliamp"
    return Model.nowPlayingLabel(svc.snapshot, root.showArtist) || "cliamp"
  }
  readonly property string glyph: svc && svc.running ? Model.stateGlyph(svc.state) : "󰝛" // nf-md-music_note_off
  readonly property bool ytDot: root.showYtRadioDot && !!svc && svc.ytRadioEnabled

  // Push the widget's settings into the shared service (idempotent across the
  // per-monitor widget instances).
  function syncService() {
    if (!svc) return
    svc.refreshIntervalSec = Math.max(1, Number(setting("refreshIntervalSec", 2)))
    var bin = setting("cliampPath", "")
    if (bin) svc.cliampBin = String(bin)
    var yt = setting("ytRadioPlugin", "")
    if (yt) svc.ytRadioName = String(yt)
  }
  onSvcChanged: syncService()
  onSettingsChanged: syncService()
  Component.onCompleted: syncService()

  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("settings" in t) t.settings = root.settings
    if ("anchorItem" in t) t.anchorItem = root
  }
  onBarChanged: injectPanel()

  visible: !(root.hideWhenStopped && !root.active)
  implicitWidth: visible ? (vertical ? barSize : contents.implicitWidth + Style.space(12)) : 0
  implicitHeight: barSize

  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  Row {
    id: contents
    anchors.centerIn: parent
    spacing: Style.space(6)

    Item {
      width: glyphText.implicitWidth + (dot.visible ? dot.width + Style.space(3) : 0)
      height: glyphText.implicitHeight
      anchors.verticalCenter: parent.verticalCenter

      Text {
        id: glyphText
        text: root.glyph
        color: root.active ? (root.bar ? root.bar.barForeground : Color.foreground)
                           : Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.8)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }
      Rectangle {
        id: dot
        visible: root.ytDot
        width: Style.space(6); height: width; radius: width / 2
        color: Color.accent
        anchors.left: glyphText.right
        anchors.leftMargin: Style.space(3)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // Scrolling label — clip window + marquee animation. Same approach as
    // manuel-artia.eva-deadline/BarWidget.qml: the Text keeps its natural
    // width and the parent Item does the visual crop, avoiding a width<->width
    // binding cycle.
    Item {
      id: labelClip
      readonly property bool overflow: label.implicitWidth > root.maxLabelWidth
      width: Math.min(root.maxLabelWidth, label.implicitWidth)
      height: label.implicitHeight
      anchors.verticalCenter: parent.verticalCenter
      clip: true
      visible: !root.vertical

      Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: root.displayText
        color: root.active ? (root.bar ? root.bar.barForeground : Color.foreground)
                           : Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.8)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        width: implicitWidth
        onTextChanged: x = 0

        SequentialAnimation {
          running: labelClip.overflow
          loops: Animation.Infinite
          onRunningChanged: if (!running) label.x = 0

          PauseAnimation { duration: 1500 }
          NumberAnimation {
            target: label; property: "x"
            to: labelClip.width - label.implicitWidth
            duration: Math.max(1800, (label.implicitWidth - labelClip.width) * 40)
            easing.type: Easing.Linear
          }
          PauseAnimation { duration: 1200 }
          NumberAnimation {
            target: label; property: "x"; to: 0
            duration: Math.max(1800, (label.implicitWidth - labelClip.width) * 40)
            easing.type: Easing.Linear
          }
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.bar) root.bar.showTooltip(root, Model.tooltipText(root.svc ? root.svc.snapshot : null,
                                                                          root.svc ? { known: root.svc.ytRadioKnown, enabled: root.svc.ytRadioEnabled } : null))
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onWheel: function (wheel) {
      if (!root.svc) return
      root.svc.nudgeVolume(wheel.angleDelta.y > 0 ? 1 : -1)
    }
    onClicked: function (mouse) {
      if (root.bar) root.bar.hideTooltip(root)
      if (!root.svc) return
      if (mouse.button === Qt.RightButton) root.togglePanel()
      else if (mouse.button === Qt.MiddleButton) root.svc.next()
      else root.svc.playPause()
    }
  }

  Component.onDestruction: if (root.bar) root.bar.hideTooltip(root)
}
