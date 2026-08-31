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
  readonly property bool showBarThumbnail: setting("showBarThumbnail", true) === true
  readonly property bool showBarSpectrum: setting("showBarSpectrum", true) === true
  readonly property real barSpectrumOpacity: Math.max(0.05, Math.min(0.9, Number(setting("barSpectrumOpacity", 35)) / 100))

  readonly property bool active: !!svc && svc.running
  readonly property bool barSpectrumOn: showBarSpectrum && !!svc && svc.playing && svc.visBands.length > 0

  // Ref-count the shared visstream on the service: hold it whenever the bar
  // spectrum is enabled and cliamp is up (Service gates the actual process on
  // `playing` too). Released when no longer wanted and on destruction.
  property bool visHeld: false
  readonly property bool visWant: showBarSpectrum && !!svc && svc.running
  onVisWantChanged: syncVis()
  function syncVis() {
    if (!svc) return
    if (visWant && !visHeld) { svc.acquireVis(); visHeld = true }
    else if (!visWant && visHeld) { svc.releaseVis(); visHeld = false }
  }

  readonly property string barArtUrl: (svc && svc.running && showBarThumbnail) ? Model.artUrl(svc.snapshot) : ""
  readonly property string barArtFallback: (svc && svc.running && showBarThumbnail) ? Model.artUrlFallback(svc.snapshot) : ""
  // Empty while cliamp isn't running (and until a track has real metadata) —
  // the widget collapses to just the icon.
  readonly property string displayText: (svc && svc.running)
    ? Model.nowPlayingLabel(svc.snapshot, root.showArtist)
    : ""
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
  onSvcChanged: { syncService(); syncVis() }
  onSettingsChanged: syncService()
  Component.onCompleted: { syncService(); syncVis() }

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
      id: lead
      readonly property real artSize: Math.max(12, root.barSize - Style.space(8))
      readonly property bool thumbShown: root.barArtUrl !== "" && thumb.status === Image.Ready
      width: mark.width + (dot.visible ? dot.width + Style.space(3) : 0)
      height: root.barSize
      anchors.verticalCenter: parent.verticalCenter

      Item {
        id: mark
        width: lead.thumbShown ? lead.artSize : glyphText.implicitWidth
        height: root.barSize

        // Cover art: YouTube Music thumbnail or embedded art. Loads while
        // hidden and swaps in once ready; otherwise the glyph stays.
        Rectangle {
          id: thumbBox
          anchors.verticalCenter: parent.verticalCenter
          width: lead.artSize
          height: lead.artSize
          radius: Style.space(3)
          visible: lead.thumbShown
          color: root.bar ? Style.normalFillFor(root.bar.barForeground, Color.accent) : "transparent"

          Image {
            id: thumb
            anchors.fill: parent
            anchors.margins: 1
            readonly property string primary: root.barArtUrl
            source: primary
            // On a track change, re-arm to the primary URL (the imperative
            // assignment in onStatusChanged otherwise sticks on the old value).
            onPrimaryChanged: source = primary
            onStatusChanged: {
              if (status === Image.Error && source === primary && root.barArtFallback)
                source = root.barArtFallback
            }
            sourceSize.width: 96
            sourceSize.height: 96
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
          }
        }

        Text {
          id: glyphText
          visible: !lead.thumbShown
          text: root.glyph
          color: root.active ? (root.bar ? root.bar.barForeground : Color.foreground)
                             : Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.8)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Rectangle {
        id: dot
        visible: root.ytDot
        width: Style.space(6); height: width; radius: width / 2
        color: Color.accent
        anchors.left: mark.right
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
      // Widen to a small floor while the spectrum is behind the text so the
      // bars aren't cramped when the title is short.
      width: Math.min(root.maxLabelWidth,
                      root.barSpectrumOn ? Math.max(label.implicitWidth, Style.space(96))
                                         : label.implicitWidth)
      height: root.barSize
      anchors.verticalCenter: parent.verticalCenter
      clip: true
      // Drop out of the Row entirely (no leftover spacing) when there's no
      // text — inactive state is icon-only.
      visible: !root.vertical && root.displayText !== ""

      // Spectrum sits behind the label (declared first = painted first).
      Spectrum {
        anchors.fill: parent
        anchors.topMargin: Style.space(3)
        anchors.bottomMargin: Style.space(3)
        visible: root.barSpectrumOn
        opacity: root.barSpectrumOpacity
        bands: root.svc ? root.svc.visBands : []
        barColor: root.bar ? root.bar.barForeground : Color.foreground
        gap: Math.max(1, Style.space(2))
        minBar: 0
      }

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

  Component.onDestruction: {
    if (root.bar) root.bar.hideTooltip(root)
    if (root.visHeld && root.svc) root.svc.releaseVis()
  }
}
