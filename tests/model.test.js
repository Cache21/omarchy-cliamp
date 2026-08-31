// Run: node tests/model.test.js   (or: deno run --allow-read tests/model.test.js)
const M = require("../Model.js")

let failed = 0
function eq(actual, expected, msg) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a === e) {
    console.log("  ok   " + msg)
  } else {
    failed++
    console.log("  FAIL " + msg + "\n       expected " + e + "\n       got      " + a)
  }
}

// ---- parseStatus ----
console.log("parseStatus")
eq(M.parseStatus(""), null, "empty -> null (cliamp not running)")
eq(M.parseStatus("not json"), null, "garbage -> null")
eq(M.parseStatus('{"ok":false}'), null, "ok:false -> null")

const playing = M.parseStatus(JSON.stringify({
  ok: true, state: "playing", position: 42.5, duration: 183, volume: -3,
  shuffle: true, repeat: "All", total: 11,
  track: { title: "Numb", artist: "Linkin Park", stream: false, duration_secs: 183 },
  theme: { name: "Tokyo Night" }
}))
eq(playing.running, true, "playing.running")
eq(playing.state, "playing", "playing.state")
eq(playing.title, "Numb", "playing.title")
eq(playing.artist, "Linkin Park", "playing.artist")
eq(playing.positionSec, 42.5, "playing.positionSec")
eq(playing.durationSec, 183, "playing.durationSec")
eq(playing.volumeDb, -3, "playing.volumeDb")
eq(playing.shuffle, true, "playing.shuffle")
eq(playing.repeat, "all", "playing.repeat normalized to lowercase")
eq(playing.themeName, "Tokyo Night", "playing.themeName")

// stopped snapshot as captured live from `cliamp status --json` (zero fields omitted)
const stopped = M.parseStatus(JSON.stringify({
  ok: true, state: "stopped", total: 11, shuffle: false, repeat: "Off",
  track: { title: "Lofi Stream", path: "http://radio.cliamp.stream/lofi/stream", stream: true }
}))
eq(stopped.state, "stopped", "stopped.state")
eq(stopped.isStream, true, "stopped.isStream")
eq(stopped.positionSec, 0, "stopped.positionSec defaults to 0 (field omitted)")
eq(stopped.durationSec, 0, "stopped.durationSec defaults to 0")
eq(stopped.volumeDb, 0, "stopped.volumeDb defaults to 0")
eq(stopped.repeat, "off", "stopped.repeat")

const paused = M.parseStatus('{"ok":true,"state":"paused","track":{"title":"x"}}')
eq(paused.state, "paused", "paused.state")

// ---- nowPlayingLabel ----
console.log("nowPlayingLabel")
eq(M.nowPlayingLabel(null, true), "", "null -> empty")
eq(M.nowPlayingLabel({ running: false }, true), "", "not running -> empty")
eq(M.nowPlayingLabel({ running: true, title: "Numb", artist: "Linkin Park" }, true),
  "Linkin Park — Numb", "artist + title when showArtist")
eq(M.nowPlayingLabel({ running: true, title: "Numb", artist: "Linkin Park" }, false),
  "Numb", "title only when !showArtist")
eq(M.nowPlayingLabel({ running: true, title: "Song", station: "SomaFM", artist: "DJ" }, true),
  "SomaFM: DJ - Song", "station + artist - title for radio")
eq(M.nowPlayingLabel({ running: true, station: "SomaFM" }, true),
  "SomaFM", "station only")

// ---- fmtTime / fmtVolume / repeatLabel ----
console.log("fmtTime / fmtVolume / repeatLabel")
eq(M.fmtTime(0), "0:00", "0 -> 0:00")
eq(M.fmtTime(42), "0:42", "42 -> 0:42")
eq(M.fmtTime(183), "3:03", "183 -> 3:03")
eq(M.fmtTime(3661), "1:01:01", "3661 -> 1:01:01")
eq(M.fmtTime(-5), "0:00", "negative -> 0:00")
eq(M.fmtVolume(0), "0 dB", "0 -> 0 dB")
eq(M.fmtVolume(-3), "-3 dB", "-3 -> -3 dB")
eq(M.fmtVolume(2), "+2 dB", "2 -> +2 dB")
eq(M.repeatLabel("all"), "Todo", "repeatLabel all")
eq(M.repeatLabel("one"), "Una", "repeatLabel one")
eq(M.repeatLabel("off"), "Off", "repeatLabel off")

// ---- youtubeIdFromPath / artUrl ----
console.log("youtubeIdFromPath / artUrl")
eq(M.youtubeIdFromPath("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), "dQw4w9WgXcQ", "youtube.com watch?v")
eq(M.youtubeIdFromPath("https://music.youtube.com/watch?v=abc123_-XY&list=RDwhatever"), "abc123_-XY", "music.youtube.com with &list")
eq(M.youtubeIdFromPath("https://youtu.be/dQw4w9WgXcQ"), "dQw4w9WgXcQ", "youtu.be short link")
eq(M.youtubeIdFromPath("http://radio.cliamp.stream/lofi/stream"), "", "radio stream -> no id")
eq(M.youtubeIdFromPath(""), "", "empty -> no id")
eq(M.artUrl(null), "", "null -> no art")
eq(M.artUrl({ running: true, path: "https://www.youtube.com/watch?v=dQw4w9WgXcQ" }),
  "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg", "youtube -> hqdefault")
eq(M.artUrlFallback({ running: true, path: "https://www.youtube.com/watch?v=dQw4w9WgXcQ" }),
  "https://i.ytimg.com/vi/dQw4w9WgXcQ/default.jpg", "fallback -> default.jpg")
eq(M.artUrl({ running: true, albumArtUrl: "file:///home/x/cover.jpg", path: "/home/x/song.flac" }),
  "file:///home/x/cover.jpg", "local file -> cliamp's album_art_url wins")
eq(M.artUrlFallback({ running: true, albumArtUrl: "file:///home/x/cover.jpg", path: "/home/x/song.flac" }),
  "", "no ytimg fallback when a local album_art_url is used")
eq(M.artUrl({ running: true, path: "http://radio.cliamp.stream/lofi/stream" }),
  "", "radio -> no art")

// ---- sampleBands ----
console.log("sampleBands")
eq(M.sampleBands([], 4), [0, 0, 0, 0], "empty src -> zeros of length n")
eq(M.sampleBands(null, 3), [0, 0, 0], "non-array src -> zeros")
eq(M.sampleBands([0.5, 0.5], 0), [], "n=0 -> empty array")
eq(M.sampleBands([0.2, 0.4, 0.6, 0.8], 4), [0.2, 0.4, 0.6, 0.8], "same length -> passthrough")
eq(M.sampleBands([0, 1, 0, 1], 2), [0.5, 0.5], "downsample 4->2 averages pairs")
eq(M.sampleBands([0.1, 0.9], 4), [0.1, 0.1, 0.9, 0.9], "upsample 2->4 repeats")
eq(M.sampleBands([2, -1, 0.5], 3), [1, 0, 0.5], "clamps out-of-range values to [0,1]")
eq(M.sampleBands([0.6, 0.47, 0.34, 0.43, 0.36, 0.17, 0.12, 0.06, 0, 0], 5).length, 5,
  "10 real bands -> exactly 5 buckets")

// ---- fmtViews ----
console.log("fmtViews")
eq(M.fmtViews(420), "420", "hundreds -> plain")
eq(M.fmtViews(830219), "830K", "830K")
eq(M.fmtViews(1250000), "1.2M", "1.2M")
eq(M.fmtViews(288389622), "288M", "288M (no decimal >= 10M)")
eq(M.fmtViews(0), "0", "0")
eq(M.fmtViews(null), "0", "null -> 0")

// ---- parseYtdlpResults / resultCaption ----
console.log("parseYtdlpResults / resultCaption")
const ytdlpJson = JSON.stringify({
  _type: "playlist", id: "ytsearch3", title: "x",
  entries: [
    { id: "2SUwOgmvzK4", title: "Tame Impala - The Less I Know The Better (Audio)",
      channel: "Tame Impala", uploader: "Tame Impala", duration: 218, view_count: 288389622,
      url: "https://www.youtube.com/watch?v=2SUwOgmvzK4" },
    { id: "noDur", title: "no duration", uploader: "Someone", duration: null },
    { title: "no id, skipped", id: "" }
  ]
})
const rs = M.parseYtdlpResults(ytdlpJson)
eq(rs.length, 2, "skips entries without id")
eq(rs[0], { id: "2SUwOgmvzK4", title: "Tame Impala - The Less I Know The Better (Audio)",
  channel: "Tame Impala", durationSec: 218, views: 288389622,
  url: "https://www.youtube.com/watch?v=2SUwOgmvzK4" }, "full entry mapped")
eq(rs[1].channel, "Someone", "channel falls back to uploader")
eq(rs[1].durationSec, 0, "null duration -> 0")
eq(rs[1].url, "https://www.youtube.com/watch?v=noDur", "url derived from id when missing")
eq(M.parseYtdlpResults("not json"), [], "invalid json -> []")
eq(M.parseYtdlpResults('{"entries":[]}'), [], "no entries -> []")
eq(M.resultCaption(rs[0]), "Tame Impala · 3:38 · 288M", "caption joins channel/duration/views")
eq(M.resultCaption(rs[1]), "Someone", "caption skips empty duration/views")

// ---- parseYtRadioStatus ----
console.log("parseYtRadioStatus")
eq(M.parseYtRadioStatus(""), { known: false, enabled: false }, "empty -> unknown")
eq(M.parseYtRadioStatus("cliamp: unknown plugin"), { known: false, enabled: false }, "error -> unknown")
eq(M.parseYtRadioStatus("yt-radio: auto=on | min_ahead=3 batch=10 cooldown=0s history=12"),
  { known: true, enabled: true }, "status auto=on")
eq(M.parseYtRadioStatus("yt-radio: auto=off | min_ahead=3 batch=10 cooldown=0s history=0"),
  { known: true, enabled: false }, "status auto=off")
eq(M.parseYtRadioStatus("yt-radio: auto-refill on"), { known: true, enabled: true }, "toggle reply on")
eq(M.parseYtRadioStatus("yt-radio: auto-refill off"), { known: true, enabled: false }, "toggle reply off")

console.log(failed === 0 ? "\nALL PASS" : "\n" + failed + " FAILED")
process.exit(failed === 0 ? 0 : 1)
