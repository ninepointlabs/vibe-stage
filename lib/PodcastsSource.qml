import QtQuick
import Quickshell
import Quickshell.Io
import "PodcastModel.js" as PM

// The Podcasts source: Pocket Casts through bin/pocketcasts-bridge, ported
// from the Pocket Casts plugin's Service.qml. Service.qml holds one of these
// (`svc.pc`); every bar widget and the panel read it from there.
//
// The bridge is no longer one short-lived process per call: it runs once, as
// `pocketcasts-bridge serve --lifeline`, a child of the shell (so it never
// outlives it; mpv does, on purpose, as before), and answers JSON lines on
// $XDG_RUNTIME_DIR/ninepointlabs.vibe-stage/pocketcasts.sock, the same line
// protocol as the YouTube Music bridge. The trust rules are unchanged: an
// absolute Python found by a probe, `-I -B`, a cleared environment.
Item {
  id: root

  property var settings: ({})
  property string pluginDir: ""
  property string runtimeDir: ""
  // The panel is open (polls faster).
  property bool panelOpen: false
  // Nothing starts until the service has its settings (the same rule as the
  // YouTube Music bridge).
  property bool wanted: true

  readonly property string bridgePath: pluginDir + "/bin/pocketcasts-bridge"
  readonly property string socketPath: runtimeDir + "/pocketcasts.sock"

  function setting(name, fallback) {
    var value = settings ? settings["podcasts." + name] : undefined
    if (value === undefined || value === null) value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property int skipBackSeconds: Math.max(1, Number(setting("skipBack", 10)) || 10)
  readonly property int skipForwardSeconds: Math.max(1, Number(setting("skipForward", 30)) || 30)
  readonly property bool autoplay: setting("autoplay", true) !== false

  // ---- Trust boundary. Nothing here starts a program through the session
  //      PATH or hands it the session environment.
  function sessionValues(names) {
    var values = {}
    for (var i = 0; i < names.length; i++) values[names[i]] = Quickshell.env(names[i])
    return values
  }
  readonly property var bridgeEnvironment: PM.closedEnvironment(sessionValues(PM.bridgeEnvironmentNames), PM.bridgeEnvironmentNames, PM.trustedPathEnvironment)
  readonly property var pythonProbeEnvironment: PM.closedEnvironment({}, [], PM.trustedPathEnvironment)

  property string python: ""
  property string pythonError: ""
  property bool _pythonProbing: false
  property int _pythonAttempt: 0
  property int _pythonProbeWaits: 0
  property var _pythonProbeObject: null
  property int _pythonCandidate: 0

  // ---- Connection state (from `status`)
  readonly property bool bridgeUp: sock.connected
  property bool probed: false
  property bool probing: false
  property bool authenticated: false
  property bool needsReauth: false
  property string email: ""
  property bool mpvInstalled: true
  property bool mprisInstalled: false
  property string lastError: ""
  // The last episode loaded, remembered by the bridge across restarts so the
  // bar chip has a cover before the first poll.
  property var lastItem: ({})

  // ---- Sign-in
  property bool loginRunning: false
  property string loginError: ""

  // ---- Player
  property var player: ({ active: false })
  property bool playerLoading: false
  property string playerError: ""
  property double playerFetchedAt: 0
  property real localPosition: 0
  readonly property bool playerActive: player && player.active === true
  readonly property bool isPlaying: playerActive && player.playing === true
  readonly property bool buffering: playerActive && player.buffering === true
  readonly property var nowItem: player && player.item ? player.item : null
  readonly property string nowUuid: nowItem && nowItem.uuid ? nowItem.uuid : ""
  readonly property real duration: player && player.duration ? Number(player.duration) : 0
  readonly property int volume: player && player.volume !== undefined ? Number(player.volume) : 100
  readonly property real speed: player && player.speed ? Number(player.speed) : 1
  readonly property real progress: duration > 0 ? Math.max(0, Math.min(1, localPosition / duration)) : 0
  // What the hero and the bar show: the loaded episode, else the last one.
  readonly property var heroItem: nowItem || (lastItem && lastItem.uuid ? lastItem : null)
  readonly property string title: nowItem && nowItem.name ? nowItem.name : ""
  readonly property string show: nowItem && nowItem.show ? nowItem.show : ""
  readonly property string art: PM.artSource(playerActive ? nowItem : null)

  // ---- Lists
  property var upNext: []
  property bool upNextLoading: false
  property string upNextError: ""
  property double upNextLoadedAt: 0

  property var inProgress: []
  property bool inProgressLoading: false
  property string inProgressError: ""
  property double inProgressLoadedAt: 0

  property var newReleases: []
  property bool newReleasesLoading: false
  property string newReleasesError: ""
  property double newReleasesLoadedAt: 0

  property var podcasts: []
  property bool podcastsLoading: false
  property string podcastsError: ""
  property double podcastsLoadedAt: 0

  // ---- Show page (a podcast's episodes)
  property var detail: null
  property int _detailSerial: 0

  // ---- Short-lived action feedback
  property string actionStatus: ""
  property string actionError: ""
  property bool actionRunning: false

  readonly property bool busy: probing || upNextLoading || inProgressLoading || newReleasesLoading || podcastsLoading || (detail && detail.loading === true)
  readonly property int staleMs: 300000

  // Words for the bar and the hero while the helper is not answering.
  readonly property string healthLine: pythonError !== "" ? pythonError
    : !bridgeUp ? "Starting the Pocket Casts helper"
    : !mpvInstalled ? "mpv is not installed — run: omarchy pkg add mpv"
    : probed && !authenticated ? (needsReauth ? "Pocket Casts session expired — sign in again" : "Not signed in to Pocket Casts")
    : ""

  // ------------------------------------------------------------ interpreter --

  function resolvePython() {
    if (python !== "" || pythonError !== "" || _pythonProbing) return
    _pythonCandidate = 0
    probeNextPython()
  }

  // Walk the absolute candidates in order; the first that starts and reports
  // a usable Python 3 is the bridge's interpreter for the life of the shell.
  // Each attempt is its own Process tagged with its number, so a late exit
  // from an abandoned attempt can never settle a later one.
  function probeNextPython() {
    var command = []
    while (command.length === 0 && _pythonCandidate < PM.pythonCandidates.length) {
      command = PM.pythonProbeCommand(PM.pythonCandidates[_pythonCandidate])
      if (command.length === 0) _pythonCandidate++
    }
    if (command.length === 0) {
      _pythonProbing = false
      pythonError = "No Python 3.9+ found in " + PM.trustedBinaryDirectories.join(", ")
        + " — Vibe Stage will not run python3 from your PATH"
      return
    }
    _pythonProbing = true
    _pythonAttempt++
    _pythonProbeWaits = 0
    var probe = pythonProbeProcess.createObject(root, { command: command, attempt: _pythonAttempt })
    if (!probe) { settlePythonProbe(_pythonAttempt, false, -1); return }
    _pythonProbeObject = probe
    pythonProbeWatchdog.restart()
    probe.running = true
  }

  function settlePythonProbe(attempt, started, exitCode) {
    if (!_pythonProbing || attempt !== _pythonAttempt) return
    pythonProbeWatchdog.stop()
    _pythonProbeObject = null
    if (started && exitCode === 0) {
      _pythonProbing = false
      python = PM.pythonCandidates[_pythonCandidate]
      startBridge()
      return
    }
    _pythonCandidate++
    probeNextPython()
  }

  Component {
    id: pythonProbeProcess

    Process {
      id: probeProc
      property int attempt: 0
      property bool started: false
      running: false
      clearEnvironment: true
      environment: root.pythonProbeEnvironment
      onStarted: started = true
      onExited: function (exitCode) {
        root.settlePythonProbe(probeProc.attempt, probeProc.started, exitCode)
        probeProc.destroy()
      }
    }
  }

  // Quickshell emits no exit at all for a candidate that does not exist, so
  // an attempt that has not even started after three seconds is a miss. One
  // that started (a slow first run at login) gets up to half a minute more.
  Timer {
    id: pythonProbeWatchdog
    interval: 3000
    repeat: false
    onTriggered: {
      var probe = root._pythonProbeObject
      if (probe && probe.started && ++root._pythonProbeWaits < 10) { restart(); return }
      root.settlePythonProbe(root._pythonAttempt, false, -1)
      if (probe) { probe.running = false; probe.destroy() }
    }
  }

  // ------------------------------------------------------------ the bridge --

  property int bridgeRestartDelay: 1000

  function startBridge() {
    if (!root.wanted || bridgeProc.running || root.python === "" || root.runtimeDir === "" || root.pluginDir === "") return
    var command = PM.serveCommand(root.python, root.bridgePath, root.socketPath)
    if (command.length === 0) { root.pythonError = "Could not build the pocketcasts-bridge command"; return }
    bridgeProc.command = command
    bridgeProc.running = true
  }

  onWantedChanged: if (wanted) { if (python === "") resolvePython(); else startBridge() }
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
      // 3: another bridge already serves the socket (a shell restart that
      // overlapped); the socket below talks to that one. Either way, try
      // again later, backing off, in case it goes away.
      root.bridgeRestartDelay = exitCode === 3 ? 10000 : Math.min(30000, root.bridgeRestartDelay * 2)
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
          root.finish(Number(id), { ok: false, code: "timeout", error: "Pocket Casts took too long to answer" })
      }
    }
  }

  function call(op, args, cb, timeoutMs) {
    if (!sock.connected) {
      var down = { ok: false, code: "bridge_down", error: root.pythonError || "The Pocket Casts helper is starting" }
      if (cb) Qt.callLater(function () { cb(down) })
      return 0
    }
    var id = root.nextId++
    var p = Object.assign({}, root.pending)
    p[id] = { cb: cb || null, deadline: Date.now() + (timeoutMs || 30000) }
    root.pending = p
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
    if (reply && reply.ok === false && reply.error) reply.error = PM.conciseError(reply.error)
    if (entry.cb) {
      try { entry.cb(reply) } catch (e) { console.warn("[vibe-stage] podcasts callback: " + e) }
    }
  }

  function failAll() {
    var ids = Object.keys(root.pending)
    for (var i = 0; i < ids.length; i++) root.finish(Number(ids[i]), { ok: false, code: "bridge_down", error: "The Pocket Casts helper restarted" })
  }

  function onLine(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (msg.id !== undefined && msg.id !== null) { root.finish(msg.id, msg); return }
    if (msg.event === "player" && msg.data) root.applyPlayer(msg.data)
  }

  // Auth-shaped errors flip the connection state so the panel shows the
  // sign-in card instead of a wall of identical errors.
  function absorbAuthError(result) {
    var effect = PM.authEffect(result)
    if (effect === "signed_out") { authenticated = false; return true }
    if (effect === "reauth") { authenticated = false; needsReauth = true; return true }
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
      root.probed = true
      root.lastError = ""
      var d = result.data
      root.authenticated = d.authenticated === true
      root.needsReauth = d.needsReauth === true
      root.email = d.email || ""
      root.mpvInstalled = d.mpv !== ""
      root.mprisInstalled = d.mpris === true
      root.lastItem = d.last || {}
      if (root.authenticated || d.running === true) root.refreshPlayer()
      if (root.authenticated) root.loadUpNextIfStale()
    })
  }

  function refreshIfStale() {
    if (!probed) { refresh(); return }
    refreshPlayer()
    if (authenticated) loadUpNextIfStale()
    else refresh()
  }

  // ------------------------------------------------------------- sign-in --

  // The password goes over the private socket (0600, in a 0700 directory),
  // never onto a command line; the bridge keeps only the tokens.
  function login(emailText, password) {
    var address = String(emailText || "").trim()
    if (address === "" || String(password || "") === "") {
      loginError = "Enter your Pocket Casts email and password."
      return false
    }
    if (loginRunning) return false
    loginRunning = true
    loginError = ""
    call("login", { email: address, password: String(password) }, function (result) {
      root.loginRunning = false
      if (!result.ok) {
        root.loginError = result.error
        return
      }
      root.loginError = ""
      root.needsReauth = false
      root.authenticated = true
      root.email = result.data.email || address
      root.flash("Signed in as " + root.email, false)
      root.invalidateLists()
      root.refresh()
    }, 45000)
    return true
  }

  function signOut() {
    call("logout", {}, function (result) {
      root.authenticated = false
      root.needsReauth = false
      root.email = ""
      root.player = ({ active: false })
      root.lastItem = ({})
      root.upNext = []
      root.inProgress = []
      root.newReleases = []
      root.podcasts = []
      root.detail = null
      root.invalidateLists()
      root.refresh()
    })
  }

  function invalidateLists() {
    upNextLoadedAt = 0
    inProgressLoadedAt = 0
    newReleasesLoadedAt = 0
    podcastsLoadedAt = 0
  }

  // ------------------------------------------------------------- player --

  function refreshPlayer() {
    if (playerLoading) return
    playerLoading = true
    call("player", { noAutoplay: !autoplay }, function (result) {
      root.playerLoading = false
      if (!result.ok) {
        if (root.absorbAuthError(result)) return
        if (result.code !== "bridge_down") root.playerError = result.error
        return
      }
      root.playerError = ""
      root.applyPlayer(result.data)
    })
  }

  signal episodeChanged(string uuid)

  function applyPlayer(next) {
    var previousUuid = nowUuid
    player = next || { active: false }
    playerFetchedAt = Date.now()
    localPosition = Number(player.position) || 0
    if (nowItem && (nowItem.artPath || nowItem.art)) lastItem = nowItem
    // A new episode started (autoplay, or another device's queue): the queue
    // and the in-progress list have both changed under us.
    if (nowUuid !== "" && nowUuid !== previousUuid) root.episodeChanged(nowUuid)
    if (nowUuid !== "" && previousUuid !== "" && nowUuid !== previousUuid) {
      upNextLoadedAt = 0
      inProgressLoadedAt = 0
      if (panelOpen) loadUpNext()
    }
  }

  // Interpolate the position between polls so the slider moves every second.
  Timer {
    interval: 1000
    repeat: true
    running: root.isPlaying && !root.buffering
    onTriggered: {
      var elapsed = (Date.now() - root.playerFetchedAt) / 1000 * root.speed
      var next = (Number(root.player.position) || 0) + elapsed
      root.localPosition = root.duration > 0 ? Math.min(next, root.duration) : next
      // At the end: the bridge marks it played and moves on; ask soon.
      if (root.duration > 0 && next >= root.duration - 0.5) settleTimer.restart()
    }
  }

  // Poll cadence: brisk while a panel is open, steady while playing (the
  // bridge pushes the position to Pocket Casts from these polls and notices
  // the end of an episode), sleepy when nothing is playing.
  Timer {
    id: pollTimer
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

  function settle() { settleTimer.restart() }

  function optimistic(patch) {
    var next = {}
    for (var k in player) next[k] = player[k]
    for (var p in patch) next[p] = patch[p]
    player = next
    playerFetchedAt = Date.now()
  }

  // A player action: the bridge answers with the new player state, so most
  // need no follow-up poll.
  function action(op, args, label, after, timeoutMs) {
    actionRunning = true
    call(op, args, function (result) {
      root.actionRunning = false
      if (!result.ok) {
        if (root.absorbAuthError(result)) return
        root.flash(result.error, true)
        root.settle()
        return
      }
      if (result.data && result.data.active !== undefined) root.applyPlayer(result.data)
      else root.settle()
      if (label) root.flash(label, false)
      if (after) after(result.data)
    }, timeoutMs)
  }

  function playPause() {
    if (!authenticated && !playerActive) return false
    if (isPlaying) {
      optimistic({ playing: false, position: localPosition })
      action("pause", {})
    } else {
      if (playerActive) optimistic({ playing: true, position: localPosition })
      action("resume", {}, "", null, 60000)
    }
    return true
  }

  // Only ever pauses (another source started playing).
  function pause() {
    if (!isPlaying) return false
    optimistic({ playing: false, position: localPosition })
    action("pause", {})
    return true
  }

  function next() {
    if (!authenticated) return false
    action("next", {}, "", function () { root.upNextLoadedAt = 0; root.loadUpNext() }, 60000)
    return true
  }

  function stop() { action("stop", {}) }

  function seek(seconds) {
    if (!playerActive) return
    var clamped = Math.max(0, Math.min(duration > 0 ? duration : seconds, seconds))
    optimistic({ position: clamped })
    localPosition = clamped
    action("seek", { seconds: Math.round(clamped) })
  }

  function skip(delta) {
    if (!playerActive) return false
    var target = Math.max(0, localPosition + delta)
    if (duration > 0) target = Math.min(target, duration - 1)
    optimistic({ position: target })
    localPosition = target
    action("seek", { seconds: delta, relative: true })
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
    onTriggered: if (pending >= 0) root.call("volume", { percent: pending }, null)
  }

  function nudgeVolume(delta) { setVolume(volume + delta) }

  function cycleSpeed() {
    call("speed", { value: "cycle" }, function (result) {
      if (!result.ok) { root.flash(result.error, true); return }
      root.optimistic({ speed: result.data.speed })
      root.flash("Speed " + PM.fmtSpeed(result.data.speed), false)
    })
  }

  function playItem(item, fromStart) {
    if (!item || !item.uuid) return
    var args = { uuid: item.uuid }
    if (item.podcast) args.podcast = item.podcast
    if (fromStart) args.fromStart = true
    optimistic({ active: true, playing: true, item: item, position: fromStart ? 0 : (item.playedUpTo || 0), duration: item.duration || 0 })
    localPosition = Number(player.position) || 0
    action("play", args, "", function () {
      root.upNextLoadedAt = 0
      root.inProgressLoadedAt = 0
      if (root.panelOpen) root.loadUpNext()
    }, 60000)
  }

  // ------------------------------------------------------- episode actions --

  function queue(item, where) {
    if (!item || !item.uuid) return
    var args = { where: where, uuid: item.uuid }
    if (item.podcast) args.podcast = item.podcast
    var label = where === "remove" ? "Removed from Up Next" : (where === "next" ? "Playing next" : "Added to Up Next")
    call("queue", args, function (result) {
      if (!result.ok) { if (!root.absorbAuthError(result)) root.flash(result.error, true); return }
      root.flash(label, false)
      root.loadUpNext(true)
    })
  }

  function toggleQueued(item) {
    if (!item) return
    queue(item, PM.containsUuid(upNext, item.uuid) ? "remove" : "last")
  }

  function markPlayed(item, played) {
    if (!item || !item.uuid || !item.podcast) return
    call("mark", { state: played ? "played" : "unplayed", uuid: item.uuid, podcast: item.podcast }, function (result) {
      if (!result.ok) { if (!root.absorbAuthError(result)) root.flash(result.error, true); return }
      root.patchItem(item.uuid, { status: played ? PM.statusPlayed : PM.statusUnplayed, playedUpTo: 0 })
      root.flash(played ? "Marked as played" : "Marked as unplayed", false)
      if (played) root.loadUpNext(true)
    })
  }

  // Update one episode wherever it is listed, without a refetch.
  function patchItem(uuid, patch) {
    function patched(list) {
      var out = []
      for (var i = 0; i < (list || []).length; i++) {
        var item = list[i]
        if (item.uuid === uuid) {
          var copy = {}
          for (var k in item) copy[k] = item[k]
          for (var p in patch) copy[p] = patch[p]
          item = copy
        }
        out.push(item)
      }
      return out
    }
    upNext = patched(upNext)
    inProgress = patched(inProgress)
    newReleases = patched(newReleases)
    if (detail && detail.items) {
      var next = {}
      for (var d in detail) next[d] = detail[d]
      next.items = patched(detail.items)
      detail = next
    }
  }

  // ------------------------------------------------------------- lists --

  function loadList(kind, op, args, force) {
    var loadedAt = root[kind + "LoadedAt"]
    if (!authenticated || root[kind + "Loading"]) return
    if (!force && loadedAt > 0 && Date.now() - loadedAt < staleMs) return
    root[kind + "Loading"] = true
    root[kind + "Error"] = ""
    call(op, args, function (result) {
      root[kind + "Loading"] = false
      if (!result.ok) { if (!root.absorbAuthError(result)) root[kind + "Error"] = result.error; return }
      root[kind] = result.data.items || []
      root[kind + "LoadedAt"] = Date.now()
    }, 60000)
  }

  function loadUpNext(force) { loadList("upNext", "up-next", {}, force) }
  function loadUpNextIfStale() { loadUpNext(false) }
  function loadInProgress(force) { loadList("inProgress", "in-progress", {}, force) }
  function loadNewReleases(force) { loadList("newReleases", "new-releases", {}, force) }
  function loadPodcasts(force) { loadList("podcasts", "podcasts", force ? { force: true } : {}, force) }

  function loadTab(tab, force) {
    if (tab === "upnext") loadUpNext(force)
    else if (tab === "progress") loadInProgress(force)
    else if (tab === "new") loadNewReleases(force)
    else if (tab === "podcasts") loadPodcasts(force)
  }

  // ------------------------------------------------------------- detail --

  function openDetail(item) {
    if (!item || item.type !== "podcast") return false
    var serial = ++_detailSerial
    detail = { item: item, items: [], total: 0, loading: true, error: "" }
    call("episodes", { podcast: item.uuid }, function (result) {
      if (serial !== root._detailSerial || !root.detail) return
      var next = {}
      for (var k in root.detail) next[k] = root.detail[k]
      next.loading = false
      if (!result.ok) {
        root.absorbAuthError(result)
        next.error = result.error
      } else {
        next.items = result.data.items || []
        next.total = Number(result.data.total) || next.items.length
        if (result.data.podcast && result.data.podcast.name) next.item = result.data.podcast
      }
      root.detail = next
    }, 60000)
    return true
  }

  function closeDetail() {
    _detailSerial++
    detail = null
  }

  // Every five minutes, and once the helper first answers (onConnectedChanged).
  Timer {
    interval: 300000
    repeat: true
    running: root.bridgeUp
    onTriggered: root.refresh()
  }

  Component.onCompleted: if (root.wanted) resolvePython()
}
