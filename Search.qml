import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

// YouTube search embedded in the panel. TextField -> `yt-dlp ytsearchN:` (async,
// ~1.6s) -> navigable results. Enter/click on a row = play now (Service.playUrl,
// best-effort queue+skip); the ⊕ button = enqueue (Service.queueUrl).
// Mirrors the weather panel's search idiom.
Item {
  id: root

  property QtObject bar: null
  property var svc: null
  property bool active: false          // panel sets true when in search mode
  property int resultCount: 12

  readonly property bool typing: field.activeFocus
  signal exitRequested()

  property var results: []
  property int selectedIndex: 0
  property bool searching: false
  property string errorText: ""
  property string pendingQuery: ""
  property string activeQuery: ""

  implicitHeight: layout.implicitHeight

  onActiveChanged: {
    if (active) {
      field.text = ""
      results = []
      activeQuery = ""
      errorText = ""
      selectedIndex = 0
      Qt.callLater(field.forceActiveFocus)
    }
  }

  function startSearch() {
    var q = field.text.trim()
    root.pendingQuery = q
    if (q === "") { root.results = []; root.activeQuery = ""; root.searching = false; return }
    if (searchProc.running) return   // in-flight; onStreamFinished re-launches if the query moved on
    root.activeQuery = q
    root.errorText = ""
    root.searching = true
    searchProc.command = ["yt-dlp", "ytsearch" + Math.max(1, root.resultCount) + ":" + q,
                          "--flat-playlist", "-J", "--no-warnings"]
    searchProc.running = true
  }

  function _onResults(text) {
    root.searching = false
    var parsed = Model.parseYtdlpResults(text)
    if (root.pendingQuery === root.activeQuery) {
      root.results = parsed
      root.selectedIndex = 0
      if (parsed.length === 0 && root.errorText === "" && text.trim() === "")
        root.errorText = "yt-dlp no devolvió nada"
    }
    if (root.pendingQuery !== root.activeQuery) Qt.callLater(root.startSearch)
  }

  function playAt(i) {
    if (!svc || i < 0 || i >= results.length) return
    svc.playUrl(results[i].url)
    root.exitRequested()
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      id: searchOut
      waitForEnd: true
      onStreamFinished: root._onResults(text)
    }
    onExited: function (exitCode) {
      root.searching = false
      if (exitCode !== 0 && root.results.length === 0)
        root.errorText = "Error al buscar (yt-dlp)"
    }
  }

  Column {
    id: layout
    width: parent.width
    spacing: Style.space(8)

    TextField {
      id: field
      width: parent.width
      placeholderText: "Buscar en YouTube…"
      foreground: root.bar ? root.bar.foreground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      verticalPadding: Style.space(6)

      onAccepted: {
        if (text.trim() !== root.activeQuery) root.startSearch()
        else if (root.results.length > 0) root.playAt(root.selectedIndex)
      }
      Keys.onDownPressed: if (root.results.length) root.selectedIndex = Math.min(root.results.length - 1, root.selectedIndex + 1)
      Keys.onUpPressed: if (root.results.length) root.selectedIndex = Math.max(0, root.selectedIndex - 1)
      Keys.onEscapePressed: root.exitRequested()
    }

    PanelSectionHeader {
      visible: root.searching
      foreground: root.bar ? root.bar.foreground : Color.foreground
      text: "BUSCANDO…"
    }

    Text {
      width: parent.width
      visible: !root.searching && root.errorText !== ""
      text: root.errorText
      color: root.bar ? root.bar.urgent : Color.urgent
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Text {
      width: parent.width
      visible: !root.searching && root.errorText === "" && root.activeQuery !== "" && root.results.length === 0
      text: "Sin resultados"
      color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.6)
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
    }

    ListView {
      id: list
      width: parent.width
      visible: root.results.length > 0
      height: Math.min(Style.space(300), contentHeight)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      model: root.results
      currentIndex: root.selectedIndex
      onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      delegate: Item {
        id: rowItem
        required property var modelData
        required property int index
        width: ListView.view.width
        height: Style.space(48)

        CursorSurface {
          anchors.fill: parent
          anchors.rightMargin: Style.space(1)
          foreground: root.bar ? root.bar.foreground : Color.foreground
          hasCursor: rowItem.index === root.selectedIndex

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: root.selectedIndex = rowItem.index
            onEntered: root.selectedIndex = rowItem.index
            onClicked: root.playAt(rowItem.index)
          }

          Row {
            anchors.fill: parent
            anchors.margins: Style.space(4)
            spacing: Style.space(8)

            BorderSurface {
              id: thumb
              width: Style.space(64)
              height: parent.height
              radius: Style.space(3)
              color: Style.normalFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)

              Image {
                id: thumbImg
                anchors.fill: parent
                anchors.margins: 1
                readonly property string primary: "https://i.ytimg.com/vi/" + rowItem.modelData.id + "/mqdefault.jpg"
                source: primary
                onPrimaryChanged: source = primary
                onStatusChanged: {
                  if (status === Image.Error && source === primary)
                    source = "https://i.ytimg.com/vi/" + rowItem.modelData.id + "/default.jpg"
                }
                sourceSize.width: 160
                sourceSize.height: 90
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: status === Image.Ready
              }
              Text {
                anchors.centerIn: parent
                visible: !thumbImg.visible
                text: "󰗃"
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            Column {
              width: parent.width - thumb.width - queueBtn.width - Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: rowItem.modelData.title
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
              }
              Text {
                width: parent.width
                text: Model.resultCaption(rowItem.modelData)
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            PanelActionButton {
              id: queueBtn
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰐎" // nf-md-playlist_plus
              foreground: root.bar ? root.bar.foreground : Color.foreground
              tooltipText: "Encolar"
              onClicked: if (root.svc) root.svc.queueUrl(rowItem.modelData.url)
            }
          }
        }
      }
    }
  }
}
