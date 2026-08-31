import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Headless singleton (kind: service). Polls `cliamp status --json`, exposes the
// parsed state as properties, and turns control calls into detached
// `cliamp ...` subcommands. One instance for the whole shell; every BarWidget /
// Panel instance reads it via bar.shell.serviceFor("io.github.cache21.cliamp").
Item {
  id: root

  // Injected by omarchy-shell's service loader for first-party plugins; unused
  // here but declared so the loader has somewhere to write.
  property var shell: null

  // --- config, pushed in by the bar widget from its settings -------------
  property int refreshIntervalSec: 2
  // cliampBin / ytRadioName are read from shell.json by the widget
  // (setting("cliampPath") / setting("ytRadioPlugin")) and mirrored here.
  // Not in the manifest schema on purpose — they're rarely-touched escape
  // hatches, editable by hand in ~/.config/omarchy/shell.json.
  property string cliampBin: "cliamp"
  property string ytRadioName: "yt-radio"

  // --- observed playback state -----------------------------------------
  property bool running: false
  property string state: "stopped"        // playing | paused | stopped
  property string title: ""
  property string artist: ""
  property string album: ""
  property string station: ""
  property string path: ""
  property string albumArtUrl: ""
  property bool isStream: false
  property real positionSec: 0
  property real durationSec: 0
  property real volumeDb: 0
  property bool shuffle: false
  property string repeat: "off"           // off | all | one
  property string themeName: ""
  property int index: 0
  property int total: 0
  // Bumped on every completed status read — lets the "play now" jump loop
  // wait for a fresh snapshot before deciding its next `next`.
  property int _statusSeq: 0

  property bool ytRadioKnown: false
  property bool ytRadioEnabled: false

  // --- spectrum (cliamp visstream) -----------------------------------
  // Latest frame's normalized bands (~0..1, variable length). Consumers
  // resample with Model.sampleBands(). One visstream process for the whole
  // shell — never per BarWidget — so cliamp runs its FFT for a single client.
  property var visBands: []
  readonly property int visFps: 24
  // Ref-counted "someone wants the spectrum" flag: each BarWidget / Panel
  // acquires while it needs frames and releases (also on destruction).
  property int _visRefs: 0
  readonly property bool visWanted: _visRefs > 0
  function acquireVis() { _visRefs++ }
  function releaseVis() { _visRefs = Math.max(0, _visRefs - 1) }

  readonly property bool playing: running && state === "playing"

  // status snapshot in the shape Model.* helpers expect
  readonly property var snapshot: ({
    running: root.running, state: root.state, title: root.title, artist: root.artist,
    album: root.album, station: root.station, path: root.path, albumArtUrl: root.albumArtUrl,
    isStream: root.isStream,
    positionSec: root.positionSec, durationSec: root.durationSec, volumeDb: root.volumeDb,
    shuffle: root.shuffle, repeat: root.repeat, themeName: root.themeName,
    index: root.index, total: root.total
  })

  // ---- polling --------------------------------------------------------

  property int _tick: 0

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  Process {
    id: statusProc
    command: [root.cliampBin, "status", "--json"]
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
      onStreamFinished: {
        root._applyStatus(Model.parseStatus(text))
        root._statusSeq++
      }
    }
    onExited: function (exitCode) {
      // exitCode 1 with empty stdout == "cliamp is not running". The
      // StdioCollector still fires onStreamFinished with "" -> parseStatus
      // returns null -> _applyStatus clears everything. Nothing to do here.
      if (exitCode !== 0 && !statusOut.text) root._applyStatus(null)
    }
  }

  function _applyStatus(s) {
    if (!s) {
      root.running = false
      root.state = "stopped"
      root.title = ""; root.artist = ""; root.album = ""; root.station = ""
      root.path = ""; root.albumArtUrl = ""
      root.isStream = false
      root.positionSec = 0; root.durationSec = 0
      root.volumeDb = 0; root.shuffle = false; root.repeat = "off"
      root.themeName = ""; root.index = 0; root.total = 0
      root.ytRadioKnown = false; root.ytRadioEnabled = false
      root.visBands = []
      return
    }
    root.running = true
    root.state = s.state
    root.title = s.title
    root.artist = s.artist
    root.album = s.album
    root.station = s.station
    root.path = s.path
    root.albumArtUrl = s.albumArtUrl
    root.isStream = s.isStream
    root.positionSec = s.positionSec
    root.durationSec = s.durationSec
    root.volumeDb = s.volumeDb
    root.shuffle = s.shuffle
    root.repeat = s.repeat
    root.themeName = s.themeName
    root.index = s.index
    root.total = s.total
  }

  Timer {
    id: pollTimer
    interval: Math.max(1, root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refresh()
      // yt-radio lives only in the TUI; only probe it while cliamp is up, and
      // at a third of the status cadence — its state changes rarely.
      if (root.running && (root._tick % 3 === 0) && !ytRadioProc.running)
        ytRadioProc.running = true
      root._tick++
    }
  }

  // Advance the position between polls so the panel scrubber moves smoothly at
  // 1s granularity; every real poll resyncs it.
  Timer {
    interval: 1000
    running: root.playing && root.durationSec > 0
    repeat: true
    onTriggered: if (root.positionSec < root.durationSec) root.positionSec += 1
  }

  // Short delay after issuing a control so the follow-up status read reflects it.
  Timer {
    id: bumpTimer
    interval: 300
    repeat: false
    onTriggered: root.refresh()
  }
  function _bump() { bumpTimer.restart() }

  Process {
    id: ytRadioProc
    command: [root.cliampBin, "plugins", "call", root.ytRadioName, "status"]
    stdout: StdioCollector {
      id: ytRadioOut
      waitForEnd: true
      onStreamFinished: {
        var r = Model.parseYtRadioStatus(text)
        root.ytRadioKnown = r.known
        root.ytRadioEnabled = r.enabled
      }
    }
    onExited: function (exitCode) {
      if (exitCode !== 0) { root.ytRadioKnown = false; root.ytRadioEnabled = false }
    }
  }

  // ---- controls ------------------------------------------------------
  // Fire-and-forget: cliamp's subcommands abstract the v1/v2 IPC migration,
  // and execDetached keeps the shell event loop free.

  function _run(args) {
    Quickshell.execDetached([root.cliampBin].concat(args))
    root._bump()
  }

  function playPause() { _run(["toggle"]) }
  function play() { _run(["play"]) }
  function pause() { _run(["pause"]) }
  function next() { _run(["next"]) }
  function previous() { _run(["prev"]) }
  function stop() { _run(["stop"]) }

  // `cliamp seek` help says "seek to position in seconds" -> treated as an
  // absolute target, clamped at 0.
  function seekTo(sec) { _run(["seek", String(Math.max(0, Math.round(sec)))]) }

  // `cliamp volume <dB>` is an absolute set (verified live: -6 -> -6, +2 -> 2),
  // range [-30, +6].
  function setVolume(db) {
    var v = Math.max(-30, Math.min(6, Math.round(db)))
    _run(["volume", String(v)])
  }
  function nudgeVolume(delta) { setVolume((root.volumeDb || 0) + delta) }

  function toggleShuffle() { _run(["shuffle", "toggle"]) }
  function cycleRepeat() { _run(["repeat", "cycle"]) }

  function toggleYtRadio() {
    if (!root.running) return
    Quickshell.execDetached([root.cliampBin, "plugins", "call", root.ytRadioName, "toggle"])
    ytRadioBump.restart()
  }
  Timer {
    id: ytRadioBump
    interval: 400
    repeat: false
    onTriggered: if (root.running && !ytRadioProc.running) ytRadioProc.running = true
  }

  // ---- youtube search: enqueue / play now -------------------------
  // `cliamp queue <url>` appends one entry (no expand, no autoplay), applied to
  // the live TUI/daemon over the socket.

  function queueUrl(url) {
    if (!url) return
    Quickshell.execDetached([root.cliampBin, "queue", String(url)])
    root._bump()
  }

  property string _jumpTarget: ""   // video id we're trying to reach
  property int _jumpBaseTotal: 0
  property int _jumpTries: 0
  property int _jumpSeenSeq: 0

  // Best-effort "play this now": queue the url, then step `next` through the
  // (yt-radio-filled) queue until the current track's video id matches. Each
  // step waits for a fresh status read (_statusSeq) so we don't overshoot.
  // Gives up after ~40 tries — the track stays queued either way.
  function playUrl(url) {
    if (!url) return
    root._jumpTarget = Model.youtubeIdFromPath(url)
    root._jumpBaseTotal = root.total
    root._jumpTries = 0
    root._jumpSeenSeq = root._statusSeq
    Quickshell.execDetached([root.cliampBin, "queue", String(url)])
    if (root._jumpTarget !== "") jumpTimer.start()
    else root._bump()   // not a youtube url we can match — just queued
  }

  function _stopJump() { jumpTimer.stop(); root._jumpTarget = "" }

  Timer {
    id: jumpTimer
    interval: 350
    repeat: true
    onTriggered: {
      if (root._jumpTarget === "" || root._jumpTries > 40) { root._stopJump(); return }
      root._jumpTries++
      root.refresh()
      if (root._statusSeq === root._jumpSeenSeq) return   // no fresh status yet
      root._jumpSeenSeq = root._statusSeq
      if (!root.running) { if (root._jumpTries > 8) root._stopJump(); return }
      if (Model.youtubeIdFromPath(root.path) === root._jumpTarget) {
        if (root.state !== "playing") root.play()
        root._stopJump()
        return
      }
      // Only start stepping once the queued item has actually landed.
      if (root.total > root._jumpBaseTotal)
        Quickshell.execDetached([root.cliampBin, "next"])
    }
  }

  // ---- spectrum stream ---------------------------------------------
  // `cliamp visstream` is an infinite NDJSON stream (one {"ok":..,"bands":[..]}
  // per line). Gate it on visWanted && playing so it only runs when something
  // is on screen and there's audio; the Timer re-arms it after the daemon/TUI
  // restarts (pattern from bjarneo/omarchy-shell-plugins cliamp/BandStream.qml).
  Process {
    id: visProc
    running: root.visWanted && root.playing
    command: [root.cliampBin, "visstream", "--fps", String(root.visFps)]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (line) {
        if (!line) return
        try {
          var f = JSON.parse(line)
          if (f && f.ok && Array.isArray(f.bands) && f.bands.length)
            root.visBands = f.bands
        } catch (e) {}
      }
    }
    onExited: root.visBands = []
  }

  Timer {
    interval: 2000
    running: root.visWanted && root.playing && !visProc.running
    repeat: true
    onTriggered: visProc.running = true
  }

  Component.onCompleted: refresh()

  // ---- IPC for Hyprland keybinds -----------------------------------
  // e.g.  bindd = SUPER, P, cliamp play/pause, exec, omarchy-shell io.github.cache21.cliamp playPause
  IpcHandler {
    target: "io.github.cache21.cliamp"

    function status(): string { return JSON.stringify(root.snapshot) }
    function playPause(): string { root.playPause(); return "ok" }
    function play(): string { root.play(); return "ok" }
    function pause(): string { root.pause(); return "ok" }
    function next(): string { root.next(); return "ok" }
    function previous(): string { root.previous(); return "ok" }
    function stop(): string { root.stop(); return "ok" }
    function shuffle(): string { root.toggleShuffle(); return "ok" }
    function repeat(): string { root.cycleRepeat(); return "ok" }
    function volume(amount: string): string {
      var d = Number(amount)
      if (!isFinite(d)) return "usage: volume <dB delta, e.g. -3>"
      root.nudgeVolume(d)
      return "ok"
    }
    function ytRadio(): string {
      if (!root.running) return "cliamp not running"
      root.toggleYtRadio()
      return "ok"
    }
    function refresh(): void { root.refresh() }
  }
}
