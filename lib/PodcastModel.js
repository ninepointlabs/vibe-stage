.pragma library

// PodcastModel.js — the Podcasts source's pure helpers, ported from the
// Pocket Casts plugin's Model.js (ninepointlabs.pocketcasts): formatting, the
// art source, the row lists every podcast tab renders, and the trusted-
// interpreter rules the persistent bridge is started under. No Qt objects,
// so node can test it (tests/podcast-model.test.cjs).

// Pocket Casts' playingStatus values.
var statusUnplayed = 1
var statusInProgress = 2
var statusPlayed = 3

var TAB_KEYS = ["upnext", "progress", "new", "podcasts"]
function tabOr(key) { return TAB_KEYS.indexOf(key) >= 0 ? key : "upnext" }

// ---------------------------------------------------------------- formatting

function pad2(n) { return n < 10 ? "0" + n : String(n) }

// 1:05, 12:34, 1:02:03 — clock style for positions and episode lengths.
function fmtTime(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  if (h > 0) return h + ":" + pad2(m) + ":" + pad2(s)
  return m + ":" + pad2(s)
}

// 42 min, 1 h 05 min — for episode lengths in list rows.
function fmtDuration(seconds) {
  var total = Math.max(0, Math.round((Number(seconds) || 0) / 60))
  if (total < 1) return seconds > 0 ? "<1 min" : ""
  if (total < 60) return total + " min"
  var h = Math.floor(total / 60)
  var m = total % 60
  return m === 0 ? h + " h" : h + " h " + pad2(m) + " min"
}

// "38 min left" for a started episode.
function fmtLeft(item) {
  if (!item || !item.duration || !(item.playedUpTo > 0)) return ""
  var left = Math.max(0, item.duration - item.playedUpTo)
  var label = fmtDuration(left)
  return label === "" ? "" : label + " left"
}

var monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// "2026-03-08T09:46:17Z" -> "Today", "Yesterday", "Mar 8", or "Mar 8, 2024".
function fmtDate(iso, now) {
  var s = String(iso || "")
  var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s)
  if (!m) return ""
  var year = parseInt(m[1], 10)
  var month = parseInt(m[2], 10)
  var day = parseInt(m[3], 10)
  var today = now || new Date()
  var then = new Date(year, month - 1, day)
  var midnight = new Date(today.getFullYear(), today.getMonth(), today.getDate())
  var days = Math.round((midnight - then) / 86400000)
  if (days === 0) return "Today"
  if (days === 1) return "Yesterday"
  var label = monthNames[Math.max(0, Math.min(11, month - 1))] + " " + day
  return today.getFullYear() === year ? label : label + ", " + year
}

function fmtSpeed(speed) {
  var v = Number(speed) || 1
  var s = (Math.round(v * 10) / 10).toFixed(1)
  return s + "×"
}

function fileUrl(path) {
  if (!path) return ""
  return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
}

// Prefer the cached copy on disk; fall back to the CDN URL, which Qt's Image
// element loads over the network on its own.
function artSource(item) {
  if (!item) return ""
  if (item.artPath) return fileUrl(item.artPath)
  return item.art || ""
}

function joinParts(parts) {
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i]
    if (p !== undefined && p !== null && String(p) !== "" && String(p) !== "0") out.push(String(p))
  }
  return out.join("  ·  ")
}

// One-line secondary text under a row title. `inShow` drops the show name
// on a show's own episode list.
function subtitle(item, inShow) {
  if (!item) return ""
  if (item.type === "podcast") return joinParts([item.author, item.lastPublished ? "latest " + fmtDate(item.lastPublished) : ""])
  var timing = item.status === statusPlayed ? "Played"
    : (item.status === statusInProgress && item.playedUpTo > 0 ? fmtLeft(item) : fmtDuration(item.duration))
  return joinParts([inShow ? "" : item.show, fmtDate(item.published), timing])
}

function progressFraction(item) {
  if (!item || !item.duration) return 0
  if (item.status === statusPlayed) return 1
  var f = (Number(item.playedUpTo) || 0) / Number(item.duration)
  return Math.max(0, Math.min(1, f))
}

// ------------------------------------------------------------------- rows
//
// Every podcast tab and the show page render the same flat row list so one
// keyboard cursor can walk it: `header` rows are skipped by the cursor,
// `item` rows activate, and `note` rows are inert copy.

function headerRow(label) { return { kind: "header", label: label } }
function noteRow(text, dim) { return { kind: "note", text: text, dim: dim !== false } }
function itemRow(item, extra) {
  var row = { kind: "item", item: item, key: item.uuid || item.name }
  if (extra) for (var k in extra) row[k] = extra[k]
  return row
}

function listRows(items, loading, error, emptyText) {
  var rows = []
  if (error) rows.push(noteRow(error, false))
  if (loading && (!items || items.length === 0)) {
    rows.push(noteRow("Loading…"))
    return rows
  }
  if (!items || items.length === 0) {
    if (!error) rows.push(noteRow(emptyText))
    return rows
  }
  for (var i = 0; i < items.length; i++) rows.push(itemRow(items[i]))
  return rows
}

// Up Next with the playing episode pulled out: Pocket Casts keeps it at the
// top of the queue, but the hero already shows it.
function upNextRows(items, nowUuid, loading, error) {
  var rest = []
  for (var i = 0; i < (items || []).length; i++) if (items[i].uuid !== nowUuid) rest.push(items[i])
  if ((items || []).length > 0 && rest.length === 0 && !error)
    return [noteRow("Nothing else queued. Add episodes with q from any list.")]
  return listRows(rest, loading, error, "Up Next is empty. Pick an episode from New or Podcasts, or press q on one to queue it.")
}

function detailRows(detail) {
  var rows = []
  if (!detail) return rows
  if (detail.error) rows.push(noteRow(detail.error, false))
  if (detail.loading && (!detail.items || detail.items.length === 0)) {
    rows.push(noteRow("Loading…"))
    return rows
  }
  if (!detail.items || detail.items.length === 0) {
    if (!detail.error) rows.push(noteRow("No episodes."))
    return rows
  }
  for (var i = 0; i < detail.items.length; i++) rows.push(itemRow(detail.items[i], { index: i }))
  if (detail.total > detail.items.length) rows.push(noteRow("Showing the newest " + detail.items.length + " of " + detail.total + "."))
  return rows
}

// The rows of one podcast tab (or the open show), from the source's state.
function tabRows(pc, tab) {
  if (!pc || !pc.authenticated) return []
  if (pc.detail) return detailRows(pc.detail)
  if (tab === "upnext") return upNextRows(pc.upNext, pc.nowUuid, pc.upNextLoading, pc.upNextError)
  if (tab === "progress") return listRows(pc.inProgress, pc.inProgressLoading, pc.inProgressError, "Nothing in progress.")
  if (tab === "new") return listRows(pc.newReleases, pc.newReleasesLoading, pc.newReleasesError, "No new episodes from your shows.")
  if (tab === "podcasts") return listRows(pc.podcasts, pc.podcastsLoading, pc.podcastsError, "You don't follow any shows yet. Subscribe in Pocket Casts and they show up here.")
  return []
}

// The same rows in the shape views/RowList.qml draws (one list component for
// every source): a note becomes an inert header line, an item gets a title,
// a cover, a subtitle and a length; `current` marks the playing episode.
function displayRows(rows, nowUuid, inShow) {
  var out = []
  for (var i = 0; i < (rows || []).length; i++) {
    var r = rows[i]
    if (r.kind === "item") {
      var it = r.item
      out.push({
        item: {
          kind: it.type === "podcast" ? "podcast" : "episode",
          title: it.name || "",
          subtitle: subtitle(it, inShow),
          thumb: artSource(it),
          duration: it.type === "podcast" ? 0 : (Number(it.duration) || 0),
          played: it.status === statusPlayed,
          uuid: it.uuid || "",
          source: it
        },
        current: !!nowUuid && it.uuid === nowUuid
      })
    } else {
      out.push({ header: r.kind === "header" ? r.label : r.text, note: r.kind === "note" })
    }
  }
  return out
}

function containsUuid(items, uuid) {
  for (var i = 0; i < (items || []).length; i++) if (items[i].uuid === uuid) return true
  return false
}

// -------------------------------------------------------------- misc text

function conciseError(text, fallback) {
  var s = String(text || fallback || "Pocket Casts request failed").replace(/\s+/g, " ").trim()
  return s.length > 160 ? s.substring(0, 157) + "…" : s
}

var signInNotes = [
  "Uses your Pocket Casts email and password once; only the session tokens Pocket Casts returns are kept, never the password.",
  "Signed in with Apple or Google? Set a password on your account at pocketcasts.com first.",
  "Pocket Casts has no public API. This talks to the same service the web player uses, so it can break if they change it."
]

// The line under the hero: what the player is doing, or what went wrong.
function statusLine(pc) {
  if (!pc) return ""
  if (pc.actionError) return pc.actionError
  if (pc.actionStatus) return pc.actionStatus
  if (pc.playerError) return pc.playerError
  if (pc.lastError) return pc.lastError
  if (!pc.authenticated) return ""
  if (!pc.mpvInstalled) return "mpv is not installed — run: omarchy pkg add mpv"
  if (pc.buffering) return "Buffering…"
  if (pc.playerActive) return (pc.isPlaying ? "Playing" : "Paused") + (pc.speed !== 1 ? " at " + fmtSpeed(pc.speed) : "")
  if (pc.email) return "Signed in as " + pc.email
  return "Signed in"
}

// What a socket reply's `code` means for the sign-in state.
function authEffect(reply) {
  if (!reply || reply.ok !== false) return ""
  if (reply.code === "signed_out") return "signed_out"
  if (reply.code === "reauth") return "reauth"
  return ""
}

// ---------------------------------------------------------------------------
// Trusted executables and closed environments
//
// The shell never starts a program through the session PATH and never hands
// one the session environment:
//  - the bridge runs as `<absolute python3> -I -B bin/pocketcasts-bridge serve
//    --lifeline --socket <path>`. -I ignores every PYTHON* variable and user
//    site-packages and keeps the script's own directory off sys.path. The
//    interpreter is found by a startup probe over pythonCandidates, never via
//    `#!/usr/bin/env`.
//  - its environment is cleared down to bridgeEnvironmentNames and a fixed
//    PATH. The bridge in turn starts mpv by absolute path with a rebuilt
//    environment of its own.
// ---------------------------------------------------------------------------

// /usr/local/bin and anything under $HOME are deliberately absent: those are
// the usual landing spots for a shadow binary.
var trustedBinaryDirectories = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/run/current-system/sw/bin"]
var trustedPathEnvironment = trustedBinaryDirectories.join(":")

var pythonCandidates = ["/usr/bin/python3", "/bin/python3", "/run/current-system/sw/bin/python3"]
var pythonVersionCheck = "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 3)"

// The bridge keeps its XDG directories (state, cache, and the runtime dir
// where its socket, mpv's socket and PipeWire live) and the session bus
// mpv-mpris uses.
var bridgeEnvironmentNames = [
  "HOME", "USER", "LOGNAME", "LANG",
  "XDG_RUNTIME_DIR", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME",
  "DBUS_SESSION_BUS_ADDRESS"
]

// Clean absolute paths only: every component starts with a letter or digit,
// so no `..`, no hidden component, no whitespace or quoting characters.
var trustedExecutablePattern = /^\/[A-Za-z0-9][A-Za-z0-9._+-]*(?:\/[A-Za-z0-9][A-Za-z0-9._+-]*)*$/

function isObjectMap(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

// `value` when it is a clean absolute path directly inside one of
// `directories` (the system directories by default); "" otherwise.
function trustedExecutable(value, directories) {
  var text = typeof value === "string" ? value : ""
  if (text === "" || text.length > 256 || !trustedExecutablePattern.test(text)) return ""
  var allowed = directories || trustedBinaryDirectories
  return allowed.indexOf(text.substring(0, text.lastIndexOf("/"))) >= 0 ? text : ""
}

// A complete environment for a Process with clearEnvironment: the listed
// names that hold a bounded single-line value, then PATH, which nothing
// inherited can override.
function closedEnvironment(inherited, names, path) {
  var environment = {}
  var source = isObjectMap(inherited) ? inherited : {}
  var list = Array.isArray(names) ? names : []
  for (var i = 0; i < list.length; i++) {
    var value = source[list[i]]
    if (typeof value !== "string" || value === "" || value.length > 4096) continue
    if (/[\x00-\x1f\x7f]/.test(value)) continue
    environment[list[i]] = value
  }
  environment.PATH = String(path || trustedPathEnvironment)
  return environment
}

function pythonProbeCommand(candidate) {
  var python = trustedExecutable(candidate)
  return python === "" ? [] : [python, "-I", "-c", pythonVersionCheck]
}

// Empty (so nothing starts) unless the interpreter is trusted and the script
// path is absolute.
function bridgeCommand(python, bridgePath, args) {
  var interpreter = trustedExecutable(python)
  var script = typeof bridgePath === "string" ? bridgePath : ""
  if (interpreter === "" || script.charAt(0) !== "/" || /[\x00-\x1f\x7f]/.test(script)) return []
  var argv = [interpreter, "-I", "-B", script]
  var rest = Array.isArray(args) ? args : []
  for (var i = 0; i < rest.length; i++) argv.push(String(rest[i]))
  return argv
}

// The persistent bridge's command: `serve`, tied to the shell by --lifeline,
// on the given socket. Empty when the socket path is not a clean absolute path.
function serveCommand(python, bridgePath, socketPath) {
  var sock = typeof socketPath === "string" ? socketPath : ""
  if (sock.charAt(0) !== "/" || /[\x00-\x1f\x7f]/.test(sock)) return []
  return bridgeCommand(python, bridgePath, ["serve", "--lifeline", "--socket", sock])
}
