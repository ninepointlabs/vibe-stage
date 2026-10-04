import QtQuick
import Quickshell
import "lib"

// Drives lib/AudibleSource.qml against the real bin/audible-bridge (signed
// out, in a throwaway XDG tree): it starts the bridge, probes it, and every
// state change and reply it sees goes to the log for
// tests/test_audible_source.py.
ShellRoot {
  id: scene

  AudibleSource {
    id: ab
    pluginDir: Quickshell.env("VIBE_PLUGIN_DIR")
    runtimeDir: Quickshell.env("VIBE_RUNTIME_DIR")
    python: "/usr/bin/python3"
    wanted: true
    onBridgeUpChanged: console.log("STATE bridgeUp " + ab.bridgeUp)
    onProbedChanged: if (ab.probed) {
      console.log("STATE probed authenticated=" + ab.authenticated + " available=" + ab.available + " health=" + ab.healthLine)
      scene.afterProbe()
    }
  }

  function afterProbe() {
    // Signed out, the library is refused with the code that shows the card.
    ab.call("library", {}, function (r) { console.log("REPLY library ok=" + r.ok + " code=" + (r.code || "")) })
    // The player answers signed out too: nothing loaded.
    ab.call("player", {}, function (r) { console.log("REPLY player ok=" + r.ok + " active=" + (r.ok ? r.data.active : "")) })
    // An empty sign-in never reaches the bridge.
    console.log("LOGIN empty " + ab.login("", "", "") + " " + ab.loginError)
    // play() is a no-op while signed out.
    console.log("PLAY signed-out " + ab.play("B000000000", false))
    ab.refreshPlayer()
    // The sort: a copy in the chosen order, `library` left as the bridge sent it.
    ab.library = [
      { asin: "A1", title: "Zebra Days", authors: ["Mo Author"] },
      { asin: "A2", title: "book 10", authors: ["al Writer", "Zed Co"] },
      { asin: "A3", title: "Book 2", authors: ["Mo Author"] },
      { asin: "A4", title: "", authors: [] }
    ]
    var order = function () { return ab.sortedLibrary.map(function (b) { return b.asin }).join(",") }
    var seen = [ab.sortOrder + ":" + ab.sortLabel + ":" + order()]
    for (var i = 0; i < 3; i++) { ab.cycleSort(); seen.push(ab.sortOrder + ":" + ab.sortLabel + ":" + order()) }
    console.log("SORT " + seen.join(" ") + " library=" + ab.library.map(function (b) { return b.asin }).join(","))
    ab.library = []
    doneTimer.start()
  }

  Timer {
    id: doneTimer
    interval: 1500
    onTriggered: {
      console.log("DONE active=" + ab.playerActive + " playing=" + ab.isPlaying + " lastError=" + ab.lastError)
      Qt.quit()
    }
  }

  Timer {
    interval: Number(Quickshell.env("VIBE_SCENE_MS") || "20000")
    running: true
    onTriggered: { console.log("TIMEOUT"); Qt.quit() }
  }
}
