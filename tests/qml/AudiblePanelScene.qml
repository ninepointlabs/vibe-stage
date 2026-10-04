import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib/Model.js" as Model
import "lib/AudibleModel.js" as AM

// The real Panel.qml on the Audiobooks source (test_audible_panel.py), with
// a fake service and a fake Audible source: signed out it is the sign-in
// card, signed in with the library on its way a loading line, then the
// library, the book playing marked and in the hero; the shelves (← →), the
// sort (s, ctrl s), the search (/) and Enter on the row under the cursor. The shell's KeyboardPanel is swapped for tests/qml/stub.
// Logs one "STATE {...}" line; saves a frame of each state to
// SOLFA_SCENE_OUT_<n> when set.
ShellRoot {
  id: scene

  QtObject {
    id: fakeAudible
    property bool probed: true
    property bool available: true
    property string availableError: ""
    property bool authenticated: false
    property string email: ""
    property bool loginRunning: false
    property string loginError: ""
    property string loginNeeds: ""
    property var library: []
    property bool libraryLoaded: false
    property bool libraryLoading: false
    property string libraryError: ""
    property string nowAsin: ""
    property string startingAsin: ""
    property bool playerActive: false
    property bool isPlaying: false
    property real speed: 1
    property int volume: 80
    property bool busy: false
    property int skipBackSeconds: 10
    property int skipForwardSeconds: 30
    property string healthLine: authenticated ? "" : "Not signed in to Audible"
    property string statusLine: healthLine
    property string actionError: ""
    property string lastError: ""
    property var calls: []
    // The real source's sort (AudibleModel.js), on the fake's library.
    property string sortOrder: "recent"
    readonly property var sortedLibrary: AM.sortBooks(library, sortOrder)
    readonly property string sortLabel: AM.sortLabel(sortOrder)
    function cycleSort() { sortOrder = AM.nextSort(sortOrder) }
    function authorsText(list) { return (list || []).join(", ") }
    function refreshIfStale() { calls.push("refreshIfStale") }
    function refresh() { calls.push("refresh") }
    function loadLibrary(force) { calls.push("loadLibrary") }
    function login(e, p, c) { calls.push("login"); return true }
    function resetLogin() {}
    function logout() { calls.push("logout") }
    function play(asin, fromStart) { calls.push("play:" + asin); return true }
    function playPause() { calls.push("playPause"); return true }
    function stop() { calls.push("stop") }
    function seek(v) {}
    function setVolume(v) {}
    function cycleSpeed() { calls.push("cycleSpeed") }
  }

  QtObject {
    id: fakeSvc
    property string activeSource: "audible"
    property string controlSource: "audible"
    property var audible: fakeAudible
    property bool bridgeUp: true
    property bool ready: true
    property bool signingIn: false
    property bool gated: false
    property bool closed: false
    property bool signedIn: true
    property bool hasTrack: false
    property bool isPlaying: false
    property bool isAd: false
    property bool panelOpen: false
    property string lastError: ""
    property var engine: ({ status: "ready", error: "", signedIn: true, host: "music.youtube.com", wantRunning: true })
    property var account: ({ signedIn: true, host: "music.youtube.com" })
    property var player: ({})
    property string engineLine: "Ready"
    property bool nowHasTrack: fakeAudible.playerActive
    property bool nowPlaying: fakeAudible.isPlaying
    property string nowTitle: fakeAudible.playerActive ? "The Long Way Home" : ""
    property string nowSubtitle: fakeAudible.playerActive ? "Ada Example" : ""
    property string nowArt: ""
    property real nowPosition: 600
    property real nowDuration: 36000
    property int nowVolume: 80
    property var settings: ({})
    function setting(name, fallback) { return fallback }
    function healthOf(source) { return fakeAudible.healthLine }
    function setSource(source) { activeSource = source; return true }
    property var calls: []
    function request(op, args, cb) { calls.push(op); if (cb) cb({ ok: false, error: "not-found" }); return 0 }
    function report(code) {}
    function startEngine() {}
    function mediaPlayPause() { return fakeAudible.playPause() }
    function mediaNext() { return true }
    function mediaPrevious() { return true }
    function mediaSkip(dir) { return true }
    function mediaNudgeVolume(steps) { return true }
  }

  FloatingWindow {
    id: win
    implicitWidth: 640
    implicitHeight: 720
    visible: true
    color: "transparent"

    Item {
      id: stage
      anchors.fill: parent
      VibeStagePanel {
        id: panel
        svc: fakeSvc
      }
    }

    TestCase { id: tc; name: "audible-panel"; when: false }

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var f = find(item.children[i], name)
        if (f) return f
      }
      return null
    }
    function shown(name) {
      var it = find(stage, name)
      if (!it) return null
      for (var p = it; p; p = p.parent) if (!p.visible) return false
      return true
    }
    function snapshot() {
      return { signIn: shown("audibleSignIn"), loading: shown("audibleLoading"), view: shown("audibleView"),
               hero: shown("sourceHero"), corner: shown("sourceCorner"), tabs: shown("panelTabs"),
               toolbar: shown("audibleToolbar"),
               inputFocused: find(stage, "audibleView") ? find(stage, "audibleView").inputFocused : null }
    }

    Timer { id: settle; interval: 250; property var pending: null
      onTriggered: { var fn = settle.pending; settle.pending = null; if (fn) fn() } }
    function after(cb) { settle.pending = cb; settle.restart() }
    function grab(n, cb) {
      var out = Quickshell.env("SOLFA_SCENE_OUT_" + n)
      var card = find(stage, "panelCard")
      if (out && card) card.grabToImage(function (r) { r.saveToFile(out); cb() })
      else cb()
    }

    Timer {
      interval: 300
      running: true
      onTriggered: {
        panel.open()
        win.after(function () {
          var signedOut = win.snapshot()
          signedOut.shownCalls = fakeAudible.calls.slice()
          win.grab(1, function () {
            fakeAudible.authenticated = true
            fakeAudible.email = "ada@example.com"
            fakeAudible.libraryLoading = true
            win.after(function () {
              var loading = win.snapshot()
              win.grab(2, function () {
                fakeAudible.library = [
                  { asin: "B0AAAAAAA1", title: "The Long Way Home", authors: ["Ada Example"], narrator: "Sam Reader",
                    cover_url: "", duration_sec: 36000, last_position_sec: 600, status: "in-progress" },
                  { asin: "B0AAAAAAA2", title: "A Short History of Everything", authors: ["Bo Writer", "Cy Writer"], narrator: "",
                    cover_url: "", duration_sec: 7200, last_position_sec: 0, status: "not-started" },
                  { asin: "B0AAAAAAA3", title: "Finished Already", authors: ["Di Author"], narrator: "Ed Voice",
                    cover_url: "", duration_sec: 3600, last_position_sec: 3600, status: "finished" }
                ]
                fakeAudible.libraryLoading = false
                fakeAudible.libraryLoaded = true
                fakeAudible.nowAsin = "B0AAAAAAA1"
                fakeAudible.playerActive = true
                fakeAudible.isPlaying = true
                win.after(function () {
                  var library = win.snapshot()
                  var view = win.find(stage, "audibleView")
                  library.rows = view ? view.rows.length : -1
                  library.firstCurrent = view && view.rows.length ? view.rows[0].current === true : null
                  library.firstSubtitle = view && view.rows.length ? view.rows[0].item.subtitle : ""
                  library.firstItem = view && view.rows.length ? view.rows[0].item : null
                  library.tab = panel.audibleTab
                  library.tabLabels = panel.audibleTabs.map(function (t) { return view.tabLabel(t) })
                  var key = function (k, t, mods) { panel.onKey({ key: k, text: t, modifiers: mods || 0, accepted: false }) }
                  var titles = function () { return view.rows.map(function (r) { return r.item.title }) }
                  win.grab(3, function () {
                    var keys = {}
                    // → : All, the bridge's order.
                    key(Qt.Key_Right, "")
                    keys.allTab = panel.audibleTab
                    keys.allTitles = titles()
                    keys.newBadge = view.rows.length > 1 ? [view.rows[1].item.badge, view.rows[1].item.badgeTone, view.rows[1].item.progress === undefined] : null
                    keys.finishedBadge = view.rows.length > 2 ? [view.rows[2].item.badge, view.rows[2].item.badgeTone] : null
                    // s: by title, s again: by author, ctrl s: back to recent.
                    key(Qt.Key_S, "s")
                    keys.titleSort = [view.sortLabel, titles()]
                    key(Qt.Key_S, "s")
                    keys.authorSort = [view.sortLabel, titles()]
                    key(Qt.Key_S, "\u0013", Qt.ControlModifier)
                    keys.ctrlSort = view.sortLabel
                    // / : into the search field; typing narrows the shelf.
                    key(Qt.Key_Slash, "/")
                    keys.searchFocused = view.searchFocused
                    var field = win.find(stage, "audibleSearch")
                    field.text = "WRITER"
                    keys.searchTitles = titles()
                    field.text = "long home"
                    keys.searchWords = titles()
                    field.text = "nothing like it"
                    keys.noMatch = [view.rows.length, view.emptyText]
                    field.text = "writer"
                    win.after(function () {
                      // Enter in the field: back to the books, the search kept.
                      tc.keyClick(Qt.Key_Return)
                      keys.afterEnter = [view.searchFocused, titles()]
                      win.grab(4, function () {
                        // Esc out of the field: the search is cleared, the panel stays.
                        key(Qt.Key_Escape, "")
                        keys.afterEsc = [field.text, titles().length, panel.opened]
                        // Down to the second book, Enter: it plays.
                        key(Qt.Key_Down, "")
                        key(Qt.Key_Return, "\r")
                        // Space: play / pause on the source the hero shows.
                        key(Qt.Key_Space, " ")
                        // x: speed, S: stop (Audiobooks' own keys).
                        key(Qt.Key_X, "x")
                        key(Qt.Key_S, "S", Qt.ShiftModifier)
                        // → : Finished; ← ← : back round to All, then In Progress.
                        key(Qt.Key_Right, "")
                        keys.finishedTab = [panel.audibleTab, titles(), view.cursor]
                        key(Qt.Key_Left, "")
                        key(Qt.Key_Left, "")
                        keys.backTab = panel.audibleTab
                        library.keys = keys
                        library.calls = fakeAudible.calls.filter(function (c) { return c !== "refreshIfStale" })
                        console.log("STATE " + JSON.stringify({ signedOut: signedOut, loading: loading, library: library }))
                        Qt.quit()
                      })
                    })
                  })
                })
              })
            })
          })
        })
      }
    }
  }
}
