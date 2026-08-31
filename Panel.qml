import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Popup for the cliamp bar widget: scrubber, transport, shuffle/repeat,
// volume, and the yt-radio toggle. Loaded by BarWidget's Loader (not a
// manifest kind), same pattern as manuel-artia.eva-deadline.
Panel {
  id: root
  moduleName: "io.github.cache21.cliamp"
  ipcTarget: "" // Service owns the "io.github.cache21.cliamp" IPC target

  property var anchorItem: null
  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("io.github.cache21.cliamp") : null
  readonly property bool active: !!svc && svc.running
  readonly property bool hasDuration: !!svc && svc.durationSec > 0

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(460))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function (t) {
        if (!root.svc) return
        if (t === " ") root.svc.playPause()
        else if (t === "n") root.svc.next()
        else if (t === "p") root.svc.previous()
        else if (t === "s") root.svc.toggleShuffle()
        else if (t === "r") root.svc.cycleRepeat()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        // ---- header ----
        Text {
          width: parent.width
          text: root.active ? (root.svc.title || root.svc.station || "cliamp") : "cliamp no está corriendo"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          visible: root.active && root.svc.artist !== ""
          text: root.svc ? root.svc.artist : ""
          color: Qt.darker(root.bar.foreground, 1.3)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.subtitle
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          visible: root.active && root.svc.themeName !== ""
          text: root.svc ? ("Tema: " + root.svc.themeName) : ""
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---- progress ----
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.active

          PanelSlider {
            id: progress
            width: parent.width
            bar: root.bar
            visible: root.hasDuration
            minimum: 0
            maximum: root.hasDuration ? root.svc.durationSec : 1
            value: root.svc ? root.svc.positionSec : 0
            step: 5
            onReleased: function (v) { if (root.svc) root.svc.seekTo(v) }
          }
          Row {
            width: parent.width
            visible: root.hasDuration
            Text {
              text: Model.fmtTime(root.svc ? root.svc.positionSec : 0)
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
            Item { width: parent.width - 2 * Style.space(48); height: 1 }
            Text {
              horizontalAlignment: Text.AlignRight
              text: Model.fmtTime(root.svc ? root.svc.durationSec : 0)
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Text {
            visible: !root.hasDuration
            text: "En vivo"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---- transport ----
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)
          enabled: root.active

          Button {
            iconText: "󰒮" // nf-md-skip_previous
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: if (root.svc) root.svc.previous()
          }
          Button {
            iconText: root.active && root.svc.state === "playing" ? "󰏤" : "󰐊"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: if (root.svc) root.svc.playPause()
          }
          Button {
            iconText: "󰒭" // nf-md-skip_next
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: if (root.svc) root.svc.next()
          }
          Button {
            iconText: "󰓛" // nf-md-stop
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: if (root.svc) root.svc.stop()
          }
        }

        // ---- modes ----
        Row {
          width: parent.width
          spacing: Style.space(10)
          enabled: root.active

          Text {
            text: "Aleatorio"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          ToggleSwitch {
            anchors.verticalCenter: parent.verticalCenter
            checked: root.active && root.svc.shuffle
            foreground: root.bar.foreground
            onToggled: if (root.svc) root.svc.toggleShuffle()
          }
          Item { width: Style.space(12); height: 1 }
          Text {
            text: "Repetir"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          Button {
            anchors.verticalCenter: parent.verticalCenter
            text: Model.repeatLabel(root.svc ? root.svc.repeat : "off")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: if (root.svc) root.svc.cycleRepeat()
          }
        }

        // ---- volume ----
        Column {
          width: parent.width
          spacing: Style.space(4)
          enabled: root.active

          Row {
            width: parent.width
            Text {
              text: "Volumen"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
            }
            Item { width: parent.width - 2 * Style.space(64); height: 1 }
            Text {
              horizontalAlignment: Text.AlignRight
              text: Model.fmtVolume(root.svc ? root.svc.volumeDb : 0)
              color: Qt.darker(root.bar.foreground, 1.3)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: -30
            maximum: 6
            step: 1
            integer: true
            value: root.svc ? root.svc.volumeDb : 0
            onMoved: function (v) { if (root.svc) root.svc.setVolume(v) }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---- yt-radio ----
        Column {
          width: parent.width
          spacing: Style.space(4)

          Row {
            width: parent.width
            spacing: Style.space(10)
            Text {
              width: parent.width - ytSwitch.width - Style.space(10)
              text: "Radio infinita (yt-radio)"
              color: root.active ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.8)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              anchors.verticalCenter: parent.verticalCenter
            }
            ToggleSwitch {
              id: ytSwitch
              anchors.verticalCenter: parent.verticalCenter
              enabled: root.active
              checked: root.active && root.svc.ytRadioEnabled
              foreground: root.bar.foreground
              onToggled: if (root.svc) root.svc.toggleYtRadio()
            }
          }
          Text {
            width: parent.width
            visible: !root.active
            text: "Requiere la TUI de cliamp abierta (no funciona en --daemon)."
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
