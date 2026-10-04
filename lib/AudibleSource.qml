import QtQuick
import Quickshell
import Quickshell.Io
import "PodcastModel.js" as PM
import "AudibleModel.js" as AM

// The Audiobooks source: Audible through bin/audible-bridge. Service.qml holds
// one of these (`svc.audible`); every bar widget and the panel read it from
// there.
//
// The bridge runs once, as `audible-bridge serve --lifeline`, a child of the
// shell (so it never outlives it; mpv does, on purpose, and a new bridge picks
// the book back up), and answers JSON lines on
// $XDG_RUNTIME_DIR/ninepointlabs.vibe-stage/audible.sock, the same line
// protocol as the other two bridges. It pushes nothing: the player is polled.
// The trust rules are the Pocket Casts bridge's: the interpreter that
// source's probe found (`python`, handed in by the service), `-I -B`, a
// cleared environment.
//
// The bridge answers one connection's requests in order, and a sign-in (an
// approval on the phone can take two minutes) or a play (a license, then mpv
// opening the stream) holds that line for a while: polls wait while one runs.
Item {
  id: root

  property var settings: ({})
  property string pluginDir: ""
  property string runtimeDir: ""
  // The interpreter found by the Pocket Casts source's probe ("" until then),
  // and why there is none.
  property string python: ""
  property string pythonError: ""
  // The panel is open (polls faster).
  property bool panelOpen: false
  // Nothing starts until the service has its settings.
  property bool wanted: true

  readonly property string bridgePath: pluginDir + "/bin/audible-bridge"
  readonly property string socketPath: runtimeDir + "/audible.sock"

  readonly property int skipBackSeconds: 10
  readonly property int skipForwardSeconds: 30
  readonly property var speeds: [0.8, 1, 1.1, 1.2, 1.3, 1.5, 1.75, 2]

  function sessionValues(names) {
    var values = {}
    for (var i = 0; i < names.length; i++) values[names[i]] = Quickshell.env(names[i])
    return values
  }
  readonly property var bridgeEnvironment: PM.closedEnvironment(sessionValues(PM.bridgeEnvironmentNames), PM.bridgeEnvironmentNames, PM.trustedPathEnvironment)

  // ---- Connection state (from `status`)
  readonly property bool bridgeUp: sock.connected
  property bool probed: false
  property bool probing: false
  // False when the bridge has no `audible` package: `availableError` says how to add it.
  property bool available: true
  property string availableError: ""
  property bool authenticated: false
  property string email: ""
  property string lastError: ""

  // ---- Sign-in
  property bool loginRunning: false
  property string loginError: ""
  // "otp" or "cvf": Amazon asked for a code; the next login sends it.
  property string loginNeeds: ""

  // ---- Library
  property var library: []
  property bool libraryLoaded: false
  property bool libraryLoading: false
  property string libraryError: ""

  // ---- Sort (the panel's "s"): "recent" (the bridge's own order), "title"
  // or "author" (AudibleModel.js). `library` itself keeps the bridge's order
  // (playPause with nothing open picks its first book).
  readonly property var sortOrders: AM.SORT_ORDERS
  property string sortOrder: "recent"
  readonly property var sortedLibrary: AM.sortBooks(library, sortOrder)
  readonly property string sortLabel: AM.sortLabel(sortOrder)

  function cycleSort() { sortOrder = AM.nextSort(sortOrder) }

  // ---- Player
  property var player: ({ active: false })
  property bool playerLoading: false
  property double playerFetchedAt: 0
  property real localPosition: 0
  // The book a play is opening (a license, then mpv): "" when none is.
  property string startingAsin: ""
  readonly property bool playerActive: player && player.active === true
  readonly property bool isPlaying: playerActive && player.playing === true
  readonly property var nowItem: player && player.item ? player.item : null
  readonly property string nowAsin: nowItem && nowItem.asin ? nowItem.asin : ""
  readonly property real duration: player && player.duration ? Number(player.duration) : 0
  readonly property int volume: player && player.volume !== undefined ? Number(player.volume) : 100
  readonly property real speed: player && player.speed ? Number(player.speed) : 1
  readonly property real progress: duration > 0 ? Math.max(0, Math.min(1, localPosition / duration)) : 0
  readonly property string title: nowItem && nowItem.title ? nowItem.title : ""
  readonly property string author: nowItem ? authorsText(nowItem.authors) : ""
  readonly property string narrator: nowItem && nowItem.narrator ? nowItem.narrator : ""
  readonly property string art: nowItem && nowItem.cover_url ? nowItem.cover_url : ""

  // ---- Short-lived action feedback
  property string actionStatus: ""
  property string actionError: ""
  property int longRunning: 0

  readonly property bool busy: probing || libraryLoading || startingAsin !== ""

  // Words for the bar and the hero while the helper is not answering.
  readonly property string healthLine: pythonError !== "" ? pythonError
    : !bridgeUp ? "Starting the Audible helper"
    : !available ? "The Audible helper needs the audible Python package"
    : probed && !authenticated ? "Not signed in to Audible"
    : ""

  // A short line under the hero's title: what is happening right now.
  readonly property string statusLine: actionError !== "" ? actionError
    : startingAsin !== "" ? "Opening the book…"
    : actionStatus !== "" ? actionStatus
    : lastError !== "" ? lastError
    : healthLine

  function authorsText(list) {
    if (!list) return ""
    if (typeof list === "string") return list
    var out = []
    for (var i = 0; i < list.length; i++) if (list[i]) out.push(String(list[i]))
    return out.join(", ")
  }

  // ------------------------------------------------------------ the bridge --

  property int bridgeRestartDelay: 1000

  function startBridge() {
    if (!root.wanted || bridgeProc.running || root.python === "" || root.runtimeDir === "" || root.pluginDir === "") return
    var command = PM.serveCommand(root.python, root.bridgePath, root.socketPath)
    if (command.length === 0) { root.lastError = "Could not build the audible-bridge command"; return }
    bridgeProc.command = command
    bridgeProc.running = true
  }

  onWantedChanged: startBridge()
  onPythonChanged: startBridge()
  onRuntimeDirChanged: startBridge()
  onPluginDirChanged: startBridge()

  Process {
    id: bridgeProc
    running: false
    clearEnvironment: true
    environment: root.bridgeEnvironment
    // The lifeline: the bridge exits when this pipe closes (the shell went).
    stdinEnabled: true
    stderr: SplitParser { onRead: data => console.info("[vibe-stage] " + data) }
    onExited: function (exitCode) {
      root.bridgeRestartDelay = Math.min(30000, root.bridgeRestartDelay * 2)
      bridgeRestart.interval = root.bridgeRestartDelay
      bridgeRestart.restart()
    }
  }

  Timer { id: bridgeRestart; repeat: false; onTriggered: root.startBridge() }

  property int nextId: 1
  property var pending: ({})

  BridgeSocket {
    id: sock
    path: root.wanted && root.runtimeDir !== "" ? root.socketPath : ""
    onRead: data => root.onLine(data)
    onConnectedChanged: {
      if (sock.connected) {
        root.bridgeRestartDelay = 1000
        root.refresh()
      } else {
        root.failAll()
      }
    }
  }

  // Replies that never come: give up on them so views do not wait forever.
  Timer {
    interval: 1000
    repeat: true
    running: Object.keys(root.pending).length > 0
    onTriggered: {
      var now = Date.now()
      for (var id in root.pending) {
        if (root.pending[id] && root.pending[id].deadline <= now)
          root.finish(Number(id), { ok: false, code: "timeout", error: "Audible took too long to answer" })
      }
    }
  }

  // `long`: a sign-in, a play, a stop or a sign-out, which hold the bridge's
  // line; polls wait until it is answered.
  function call(op, args, cb, timeoutMs, long) {
    if (!sock.connected) {
      var down = { ok: false, code: "bridge_down", error: root.pythonError || "The Audible helper is starting" }
      if (cb) Qt.callLater(function () { cb(down) })
      return 0
    }
    var id = root.nextId++
    var p = Object.assign({}, root.pending)
    p[id] = { cb: cb || null, deadline: Date.now() + (timeoutMs || 30000), long: !!long }
    root.pending = p
    if (long) root.longRunning++
    sock.write(JSON.stringify({ id: id, op: op, args: args || {} }) + "\n")
    sock.flush()
    return id
  }

  function finish(id, reply) {
    var entry = root.pending[id]
    if (!entry) return
    var p = Object.assign({}, root.pending)
    delete p[id]
    root.pending = p
    if (entry.long) root.longRunning = Math.max(0, root.longRunning - 1)
    if (reply && reply.ok === false) reply.error = PM.conciseError(reply.error, "Audible request failed")
    if (entry.cb) {
      try { entry.cb(reply) } catch (e) { console.warn("[vibe-stage] audible callback: " + e) }
    }
  }

  function failAll() {
    var ids = Object.keys(root.pending)
    for (var i = 0; i < ids.length; i++) root.finish(Number(ids[i]), { ok: false, code: "bridge_down", error: "The Audible helper restarted" })
  }

  function onLine(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (msg.id !== undefined && msg.id !== null) root.finish(msg.id, msg)
  }

  // Errors that say the sign-in is gone flip the state, so the panel shows
  // the sign-in card instead of a wall of identical errors.
  function absorbAuthError(result) {
    if (!result || result.ok) return false
    if (result.code === "not_authenticated" || result.code === "unauthorized") {
      root.authenticated = false
      root.libraryLoaded = false
      root.library = []
      if (result.code === "unauthorized") root.loginError = result.error
      return true
    }
    if (result.code === "missing_dependency") {
      root.available = false
      root.availableError = result.error
      return true
    }
    return false
  }

  function flash(text, isError) {
    if (isError) { actionError = text; actionStatus = "" }
    else { actionStatus = text; actionError = "" }
    actionStatusTimer.restart()
  }

  Timer {
    id: actionStatusTimer
    interval: 3500
    repeat: false
    onTriggered: { root.actionStatus = ""; root.actionError = "" }
  }

  // ------------------------------------------------------------- status --

  function refresh() {
    if (probing) return
    probing = true
    call("status", {}, function (result) {
      root.probing = false
      if (!result.ok) {
        if (result.code !== "bridge_down") { root.probed = true; root.lastError = result.error }
        return
      }
      root.lastError = ""
      var d = result.data || {}
      root.available = d.available !== false
      root.availableError = d.error || ""
      root.authenticated = d.authenticated === true
      root.email = d.email || ""
      if (d.player) root.applyPlayer(d.player)
      // Last: what reacts to it (the sign-in card) sees the state above.
      root.probed = true
      if (!root.authenticated) {
        root.library = []
        root.libraryLoaded = false
      } else if (!root.libraryLoaded) {
        root.loadLibrary(false)
      }
    })
  }

  function refreshIfStale() {
    if (!probed) refresh()
    else if (authenticated && !libraryLoaded) loadLibrary(false)
    else refreshPlayer()
  }

  // ------------------------------------------------------------- sign-in --

  // The password goes over the private socket (0600, in a 0700 directory),
  // never onto a command line; the bridge keeps only the device's tokens.
  // `code`: the one-time or verification code Amazon asked for, if it did.
  function login(emailText, password, code) {
    var address = String(emailText || "").trim()
    // The code goes with the password, which is gone if the panel closed
    // in between: back to the plain form.
    if (loginNeeds !== "" && String(password || "") === "") {
      loginNeeds = ""
      loginError = "Enter your password again; Amazon will ask for a new code."
      return false
    }
    if (address === "" || String(password || "") === "") {
      loginError = "Enter your Amazon email and password."
      return false
    }
    if (loginRunning) return false
    var args = { email: address, password: String(password) }
    var extra = String(code || "").trim()
    if (loginNeeds !== "" && extra === "") {
      loginError = loginNeeds === "otp" ? "Enter the one-time code from your authenticator app." : "Enter the code Amazon sent you."
      return false
    }
    if (loginNeeds === "otp") args.otp = extra
    else if (loginNeeds === "cvf") args.cvf = extra
    loginRunning = true
    loginError = ""
    // Up to two minutes waiting for an approval on the phone, then the
    // device registration.
    call("login", args, function (result) {
      root.loginRunning = false
      if (!result.ok) {
        if (result.code === "otp_required") { root.loginNeeds = "otp"; root.loginError = "Amazon asks for the one-time code from your authenticator app." }
        else if (result.code === "cvf_required") { root.loginNeeds = "cvf"; root.loginError = "Amazon sent you a verification code. Enter it below." }
        else root.loginError = result.error
        if (result.code === "missing_dependency") root.absorbAuthError(result)
        return
      }
      root.loginError = ""
      root.loginNeeds = ""
      root.authenticated = true
      root.email = (result.data && result.data.email) || address
      root.flash("Signed in as " + root.email, false)
      root.libraryLoaded = false
      root.loadLibrary(false)
    }, 200000, true)
    return true
  }

  // Back to the plain form (a wrong address, a code that will not come).
  function resetLogin() {
    loginNeeds = ""
    loginError = ""
  }

  function logout() {
    call("logout", {}, function (result) {
      root.authenticated = false
      root.email = ""
      root.player = ({ active: false })
      root.localPosition = 0
      root.library = []
      root.libraryLoaded = false
      root.libraryError = ""
      root.resetLogin()
      if (!result.ok && result.code !== "bridge_down") root.flash(result.error, true)
      root.refresh()
    }, 60000, true)
  }

  // ------------------------------------------------------------- library --

  // `force`: ask Audible again; otherwise the bridge's copy (kept current
  // with the positions it saves) is enough.
  function loadLibrary(force) {
    if (!authenticated || libraryLoading) return
    libraryLoading = true
    libraryError = ""
    call("library", force ? { refresh: true } : {}, function (result) {
      root.libraryLoading = false
      if (!result.ok) {
        if (!root.absorbAuthError(result)) root.libraryError = result.error
        return
      }
      root.library = (result.data && result.data.items) || []
      root.libraryLoaded = true
    }, 180000)
  }

  function findBook(asin) {
    for (var i = 0; i < library.length; i++) if (library[i].asin === asin) return library[i]
    return null
  }

  // ------------------------------------------------------------- player --

  function refreshPlayer() {
    if (playerLoading || longRunning > 0) return
    playerLoading = true
    call("player", {}, function (result) {
      root.playerLoading = false
      if (!result.ok) {
        if (!root.absorbAuthError(result) && result.code !== "bridge_down" && result.code !== "timeout") root.lastError = result.error
        return
      }
      root.lastError = ""
      root.applyPlayer(result.data)
    })
  }

  function applyPlayer(next) {
    var wasActive = playerActive
    player = next || { active: false }
    playerFetchedAt = Date.now()
    localPosition = Number(player.position) || 0
    // A book closed (stopped, or mpv quit): the library has its new position.
    if (wasActive && !playerActive && authenticated) loadLibrary(false)
  }

  // Interpolate the position between polls so the slider moves every second.
  Timer {
    interval: 1000
    repeat: true
    running: root.isPlaying
    onTriggered: {
      var elapsed = (Date.now() - root.playerFetchedAt) / 1000 * root.speed
      var next = (Number(root.player.position) || 0) + elapsed
      root.localPosition = root.duration > 0 ? Math.min(next, root.duration) : next
    }
  }

  // Poll cadence: brisk while a panel is open, steady while playing (the end
  // of a book is only seen here), sleepy when nothing is playing.
  Timer {
    interval: root.panelOpen ? 3000 : (root.isPlaying ? 5000 : 60000)
    repeat: true
    running: root.bridgeUp && (root.authenticated || root.playerActive)
    onTriggered: root.refreshPlayer()
  }

  Timer {
    id: settleTimer
    interval: 600
    repeat: false
    onTriggered: root.refreshPlayer()
  }

  function optimistic(patch) {
    var next = {}
    for (var k in player) next[k] = player[k]
    for (var p in patch) next[p] = patch[p]
    player = next
    playerFetchedAt = Date.now()
  }

  // A player action: the bridge answers with the new player state.
  function action(op, args, label, after, timeoutMs, long) {
    call(op, args, function (result) {
      if (!result.ok) {
        if (!root.absorbAuthError(result)) root.flash(result.error, true)
        settleTimer.restart()
        return
      }
      if (result.data && result.data.active !== undefined) root.applyPlayer(result.data)
      else settleTimer.restart()
      if (label) root.flash(label, false)
      if (after) after(result.data)
    }, timeoutMs, long)
  }

  function play(asin, fromStart) {
    if (!asin || !authenticated || startingAsin !== "") return false
    var book = findBook(asin)
    startingAsin = asin
    var args = { asin: asin }
    if (fromStart) args.from_position = 0
    // License, mpv starting, the stream opening: give it time.
    call("play", args, function (result) {
      root.startingAsin = ""
      if (!result.ok) {
        if (!root.absorbAuthError(result)) root.flash(result.error, true)
        settleTimer.restart()
        return
      }
      root.applyPlayer(result.data)
      if (result.data && result.data.loading) {
        root.flash("Still opening " + (book ? book.title : "the book") + "…", false)
        settleTimer.restart()
      }
    }, 120000, true)
    return true
  }

  function pause() {
    if (!isPlaying) return false
    optimistic({ playing: false, position: localPosition })
    action("pause", {})
    return true
  }

  function resume() {
    if (!playerActive) return false
    optimistic({ playing: true, position: localPosition })
    action("resume", {})
    return true
  }

  // Play or pause the book in mpv; with none, the one listened to last.
  function playPause() {
    if (isPlaying) return pause()
    if (playerActive) return resume()
    if (!authenticated || library.length === 0) return false
    return play(library[0].asin, false)
  }

  function stop() {
    if (!playerActive) return false
    action("stop", {}, "", null, 60000, true)
    return true
  }

  function seek(position) {
    if (!playerActive) return
    var clamped = Math.max(0, Math.min(duration > 0 ? duration : position, position))
    optimistic({ position: clamped })
    localPosition = clamped
    action("seek", { position: clamped })
  }

  function skip(delta) {
    if (!playerActive) return false
    seek(localPosition + delta)
    return true
  }

  function skipBack() { return skip(-skipBackSeconds) }
  function skipForward() { return skip(skipForwardSeconds) }

  function setVolume(pct) {
    var v = Math.max(0, Math.min(100, Math.round(pct)))
    optimistic({ volume: v })
    volumeDebounce.pending = v
    volumeDebounce.restart()
  }

  Timer {
    id: volumeDebounce
    property int pending: -1
    interval: 180
    repeat: false
    onTriggered: if (pending >= 0) root.call("volume", { volume: pending }, null)
  }

  function nudgeVolume(delta) { setVolume(volume + delta) }

  function setSpeed(value) {
    var s = Math.max(0.5, Math.min(3.5, Number(value) || 1))
    optimistic({ speed: s })
    action("speed", { speed: s }, "Speed " + PM.fmtSpeed(s))
  }

  function cycleSpeed() {
    var i = 0
    while (i < speeds.length && speeds[i] <= speed + 0.001) i++
    setSpeed(i < speeds.length ? speeds[i] : speeds[0])
  }

  // Every five minutes, and once the helper first answers (onConnectedChanged).
  Timer {
    interval: 300000
    repeat: true
    running: root.bridgeUp && root.longRunning === 0
    onTriggered: root.refresh()
  }

  Component.onCompleted: startBridge()
}
