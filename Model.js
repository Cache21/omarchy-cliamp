// Pure JS helpers for the cliamp Omarchy plugin. No QML imports here so the
// same file is loadable from QML (`import "Model.js" as Model`) and runnable
// under node/deno for the tests in tests/model.test.js.

// ---- status ---------------------------------------------------------------

// Parse the stdout of `cliamp status --json`. Returns a normalized object, or
// null when cliamp is not running / the output is not usable (empty string,
// invalid JSON, or `ok:false`). cliamp omits zero-valued fields
// (position/duration/volume) via `omitempty`, so every read is defensive.
function parseStatus(jsonText) {
  if (!jsonText || !String(jsonText).trim()) return null
  var obj
  try {
    obj = JSON.parse(jsonText)
  } catch (e) {
    return null
  }
  if (!obj || obj.ok === false) return null

  var track = obj.track || {}
  var state = String(obj.state || "stopped").toLowerCase()
  if (state !== "playing" && state !== "paused") state = "stopped"

  return {
    running: true,
    state: state,
    title: String(track.title || track.stream_title || ""),
    artist: String(track.artist || ""),
    album: String(track.album || ""),
    station: String(track.station || ""),
    path: String(track.path || ""),
    albumArtUrl: String(track.album_art_url || ""),
    isStream: !!track.stream,
    positionSec: num(obj.position),
    durationSec: num(obj.duration) || num(track.duration_secs),
    volumeDb: num(obj.volume),
    shuffle: !!obj.shuffle,
    repeat: normalizeRepeat(obj.repeat),
    themeName: obj.theme && obj.theme.name ? String(obj.theme.name) : "",
    total: Math.round(num(obj.total))
  }
}

function num(v) {
  var n = Number(v)
  return isFinite(n) ? n : 0
}

// cliamp reports repeat as "Off" | "All" | "One" in --json (capitalized) but
// the docs/protocol also show lowercase; fold both to off | all | one.
function normalizeRepeat(v) {
  var s = String(v || "off").toLowerCase()
  return (s === "all" || s === "one") ? s : "off"
}

// ---- labels -------------------------------------------------------------

// The single line shown in the bar. Mirrors the ICY/station formatting from
// cliamp's own docs/headless.md Waybar example:
//   station + "artist - title"  for internet radio with ICY metadata
//   "artist — title"            for tracks with a separate artist tag
//   title                       otherwise
function nowPlayingLabel(st, showArtist) {
  if (!st || !st.running) return ""
  var title = st.title || ""
  var artist = st.artist || ""
  var station = st.station || ""

  if (station) {
    var inner = (artist && title) ? (artist + " - " + title) : (title || artist)
    return inner ? (station + ": " + inner) : station
  }
  if (showArtist && artist && title) return artist + " — " + title
  return title || artist || station || ""
}

function tooltipText(st, yt) {
  if (!st || !st.running) return "cliamp no está corriendo"
  var lines = []
  var head = nowPlayingLabel(st, true)
  if (head) lines.push(head)
  lines.push("Estado: " + stateLabel(st.state))
  if (st.themeName) lines.push("Tema: " + st.themeName)
  lines.push("Volumen: " + fmtVolume(st.volumeDb))
  var modes = []
  if (st.shuffle) modes.push("aleatorio")
  if (st.repeat !== "off") modes.push("repetir " + st.repeat)
  if (modes.length) lines.push(modes.join(" · "))
  if (yt && yt.known) lines.push("yt-radio: " + (yt.enabled ? "on" : "off"))
  return lines.join("\n")
}

function stateLabel(state) {
  if (state === "playing") return "reproduciendo"
  if (state === "paused") return "en pausa"
  return "detenido"
}

// mdi nerd-font glyph for the current transport state.
function stateGlyph(state) {
  if (state === "playing") return "󰐊" // nf-md-play  (U+F040A)
  if (state === "paused") return "󰏤"  // nf-md-pause (U+F03E4)
  return "󰓛"                          // nf-md-stop  (U+F04DB)
}

function fmtTime(sec) {
  var s = Math.max(0, Math.floor(Number(sec) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var ss = s % 60
  var mm = h > 0 && m < 10 ? "0" + m : String(m)
  var p = ss < 10 ? "0" + ss : String(ss)
  return (h > 0 ? h + ":" : "") + mm + ":" + p
}

function fmtVolume(db) {
  var n = Math.round(Number(db) || 0)
  return (n > 0 ? "+" : "") + n + " dB"
}

function repeatLabel(mode) {
  if (mode === "all") return "Todo"
  if (mode === "one") return "Una"
  return "Off"
}

// ---- cover art -------------------------------------------------------

// YouTube / YouTube Music video id out of a cliamp track path
// (https://www.youtube.com/watch?v=ID , https://music.youtube.com/watch?v=ID ,
//  https://youtu.be/ID). "" when the path isn't a YouTube URL.
function youtubeIdFromPath(path) {
  var s = String(path || "")
  var m = s.match(/[?&]v=([A-Za-z0-9_-]{6,})/) || s.match(/youtu\.be\/([A-Za-z0-9_-]{6,})/)
  return m ? m[1] : ""
}

// Best-effort cover art URL for the current track:
//   - local files       -> cliamp's own album_art_url (file:// or data:)
//   - YouTube (Music)    -> the video thumbnail from i.ytimg.com
//   - radio / other      -> "" (caller falls back to a glyph)
// size: "panel" (hqdefault 480x360) or "bar" (mqdefault 320x180).
function artUrl(st, size) {
  if (!st || !st.running) return ""
  if (st.albumArtUrl) return st.albumArtUrl
  var id = youtubeIdFromPath(st.path)
  if (!id) return ""
  return "https://i.ytimg.com/vi/" + id + "/" + (size === "panel" ? "hqdefault" : "mqdefault") + ".jpg"
}

// ---- yt-radio ----------------------------------------------------------

// Parse the reply of `cliamp plugins call yt-radio status` (or `toggle`).
// status : "yt-radio: auto=on | min_ahead=3 batch=10 cooldown=0s history=12"
// toggle : "yt-radio: auto-refill on"
// Returns { known, enabled }. `known:false` means the plugin isn't loaded
// (cliamp not in the TUI) or the output was unexpected.
function parseYtRadioStatus(text) {
  var s = String(text || "")
  var m = s.match(/auto(?:-refill)?\s*[=:]?\s*(on|off|true|false|enabled|disabled)/i)
  if (!m) return { known: false, enabled: false }
  var v = m[1].toLowerCase()
  return { known: true, enabled: v === "on" || v === "true" || v === "enabled" }
}

// node/deno test entry point; ignored by QML's JS import.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    parseStatus: parseStatus,
    normalizeRepeat: normalizeRepeat,
    youtubeIdFromPath: youtubeIdFromPath,
    artUrl: artUrl,
    nowPlayingLabel: nowPlayingLabel,
    tooltipText: tooltipText,
    stateLabel: stateLabel,
    stateGlyph: stateGlyph,
    fmtTime: fmtTime,
    fmtVolume: fmtVolume,
    repeatLabel: repeatLabel,
    parseYtRadioStatus: parseYtRadioStatus
  }
}
