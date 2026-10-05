import QtQuick
import qs.Ui
import qs.Commons
import "lib/Model.js" as Model
import "lib/PodcastModel.js" as PM
import "lib/Icons.js" as Icons
import "views" as Views

// The panel: what plays at the top (for the source the bar shows), then the
// three sources (YouTube Music, Podcasts, Audiobooks) and, under the chosen
// one, its own tabs. YouTube Music is Solfa's panel as it was: Queue,
// Search, Library, Lyrics and History, and pages (album, artist, playlist)
// opened from any list. Podcasts is Pocket Casts: Up Next, In Progress, New
// and Podcasts, and a show's episodes opened from Podcasts. Audiobooks is
// the Audible library: In Progress, All and Finished. Everything works from
// the keyboard; the hint line says how.
Panel {
  id: root
  moduleName: "ninepointlabs.vibe-stage"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var svc: null

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  // ---- sources: the one picked lives in the service (IPC setSource, the
  //      bar and this panel all agree on it)
  readonly property string source: svc && Model.isSource(svc.activeSource) ? svc.activeSource : "ytmusic"
  readonly property bool isMusic: source === "ytmusic"
  readonly property bool isPodcasts: source === "podcasts"
  readonly property bool isBooks: source === "audible"
  // The hero follows the bar (controlSource): a podcast playing while the
  // panel looks at music is still what the hero shows and space pauses.
  readonly property string heroSource: svc && Model.isSource(svc.controlSource) ? svc.controlSource : source
  readonly property bool heroIsMusic: heroSource === "ytmusic"

  // YouTube Music's tabs (Solfa's keys, unchanged).
  readonly property var tabs: Model.subTabs("ytmusic")
  property string tab: "queue"
  property var pages: []
  // Podcasts' tabs.
  readonly property var podcastTabs: Model.subTabs("podcasts")
  property string podcastTab: "upnext"
  property bool podcastTabPicked: false
  // Audiobooks' shelves; none over the sign-in card.
  readonly property var audibleTabs: Model.subTabs("audible")
  property string audibleTab: "progress"
  readonly property var subTabs: isMusic ? tabs : isPodcasts ? podcastTabs : audibleView.needsSetup ? [] : audibleTabs
  readonly property string subTab: isMusic ? tab : isPodcasts ? podcastTab : audibleTab

  readonly property var musicView: pages.length > 0 ? detailView
    : tab === "queue" ? queueView : tab === "search" ? searchView : tab === "library" ? libraryView : tab === "history" ? historyView : lyricsView
  readonly property var view: isMusic ? musicView : isPodcasts ? podcastsView : audibleView
  property bool allKeys: false
  property string flash: ""
  // Settings replaces the panel body; the gear (top right) and Ctrl+, open
  // it, Esc closes it.
  property bool settingsOpen: false
  function toggleSettings() { root.settingsOpen = !root.settingsOpen }
  function closeSettings() { root.settingsOpen = false }

  onOpenedChanged: {
    if (svc) svc.panelOpen = opened
    if (!opened) { allKeys = false; settingsOpen = false; return }
    if (svc) svc.lastError = ""  // old news from while it was closed
    if (svc && !svc.hasTrack && tab === "queue") tab = "search"
    if (!podcastTabPicked && svc) {
      podcastTabPicked = true
      podcastTab = PM.tabOr(svc.setting("podcasts.defaultTab", "upnext"))
    }
    root.wakeSource()
    Qt.callLater(function () {
      root.focusKeys()
      if (root.view && root.view.shown) root.view.shown()
    })
  }

  // With autostart off, opening the panel on YouTube Music (or switching to
  // it) is what starts it.
  function wakeSource() {
    if (svc && isMusic && svc.bridgeUp && svc.engine.status === "stopped") svc.startEngine()
  }

  function focusKeys() { keys.forceActiveFocus() }

  // ---- source tabs

  function showSource(key) {
    if (!svc || !Model.isSource(key)) return
    root.settingsOpen = false
    root.allKeys = false
    if (key === root.source) { root.focusKeys(); return }
    svc.setSource(key)  // onActiveSourceChanged below does the rest
  }

  // ---- sub-tabs

  function showTab(key) {
    if (isPodcasts) { showPodcastTab(key); return }
    if (isBooks) { showAudibleTab(key); return }
    pages = []
    tab = key
    Qt.callLater(function () {
      if (root.view.shown) root.view.shown()
      if (key === "search") searchView.focusInput()
      else root.focusKeys()
    })
  }

  function showPodcastTab(key) {
    if (!Model.hasSubTab("podcasts", key)) return
    if (podcastTab === key) { podcastsView.back(); podcastsView.shown() }
    else podcastTab = key  // the view reloads on its own tab change
    root.focusKeys()
  }

  // The view goes back to the top of the shelf on its own tab change.
  function showAudibleTab(key) {
    if (!Model.hasSubTab("audible", key)) return
    if (audibleTab === key) audibleView.toTop()
    else audibleTab = key
    root.focusKeys()
  }

  function cycleTab(d) {
    if (subTabs.length === 0) return
    showTab(Model.cycleSubTab(source, subTab, d))
  }

  function openPage(item, params) {
    if (!item || !item.browseId) return
    var p = { id: item.browseId, title: item.title || "", params: params || "" }
    pages = pages.concat([p])
    detailView.open(p)
    focusKeys()
  }

  function back() {
    if (isPodcasts && podcastsView.back()) { focusKeys(); return }
    if (isBooks && audibleView.back()) { focusKeys(); return }
    if (!isMusic || pages.length === 0) { root.close(); return }
    var rest = pages.slice(0, -1)
    pages = rest
    if (rest.length) detailView.open(rest[rest.length - 1])
    focusKeys()
  }

  function say(text) { root.flash = text; flashTimer.restart() }
  Timer { id: flashTimer; interval: 2600; onTriggered: root.flash = "" }

  Connections {
    target: root.svc
    // Only the open panel shows an error (there is one panel per bar, and a
    // closed one would swallow it).
    function onLastErrorChanged() { if (root.opened && root.svc.lastError) { root.say(root.svc.lastError); root.svc.lastError = "" } }
    // From the tabs here, IPC or a script: show the new source's view.
    function onActiveSourceChanged() {
      if (!root.opened) return
      root.wakeSource()
      Qt.callLater(function () {
        root.focusKeys()
        if (root.view && root.view.shown) root.view.shown()
      })
    }
  }

  // The bar matches panels by the widget that hosts them, not by this item.
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function") return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // ---- rows: what Enter and the row buttons do, the same everywhere

  function itemActions(row) {
    var it = row && row.item
    if (!it) return []
    if (it.videoId) return [
      { name: "next", icon: Icons.playNext, tip: "Play next (e)" },
      { name: "queue", icon: Icons.plus, tip: "Add to queue (a)" },
      { name: "radio", icon: Icons.radio, tip: "Start radio (R)" }
    ]
    if (it.kind === "artist") return [{ name: "play", icon: Icons.shuffle, tip: "Shuffle this artist" }]
    if (it.playlistId) return [{ name: "play", icon: Icons.play, tip: "Play" }]
    return []
  }

  function activateRow(row, contextList) {
    var it = row && row.item
    if (!it || !svc) return
    if (it.videoId) {
      var args = { videoId: it.videoId }
      if (contextList) args.playlistId = contextList
      else if (it.playlistId) args.playlistId = it.playlistId
      svc.request("play", args, function (r) { if (r.ok) root.say("Playing " + it.title); else svc.report(r.error) })
    } else if (it.browseId) {
      openPage(it)
    }
  }

  function runAction(name, row) {
    var it = row && row.item
    if (!it || !svc) return
    if (name === "next" || name === "queue") {
      svc.enqueue(it, name === "next", function (r) {
        if (r.ok) root.say(name === "next" ? "Plays next: " + it.title : "Added to the queue: " + it.title)
        else svc.report(r.error)
      })
    } else if (name === "radio") {
      svc.radioFor(it)
      root.say("Radio from " + it.title)
    } else if (name === "play") {
      svc.playItem(it, function (r) { if (r.ok) root.say("Playing " + it.title); else svc.report(r.error) })
    }
  }

  // ---- keys

  // Every key, on "?": the shared ones, then the source's own.
  readonly property var allKeyHints: {
    var shared = [["1 2 3", "YouTube Music / Podcasts / Audiobooks"], ["← →", "tabs"], ["ctrl ,", "settings"]]
    if (isMusic) {
      var music = Model.ALL_KEY_HINTS.filter(function (h) { return h[0] !== "1-5 or ← →" })
      return shared.concat(music)
    }
    if (isPodcasts) return shared.concat([
      ["space", "play or pause"], ["n", "next in Up Next"], ["p / ,", "back " + (svc && svc.pc ? svc.pc.skipBackSeconds : 10) + " s"],
      [".", "forward " + (svc && svc.pc ? svc.pc.skipForwardSeconds : 30) + " s"], ["- / =", "volume"], ["x", "speed"], ["s", "stop"],
      ["↵", "play or open a show"], ["q", "add to / remove from Up Next"], ["m", "mark played / unplayed"], ["r", "refresh"],
      ["/", "search YouTube Music"], ["esc", "back / close"], ["?", "show or hide this list"]
    ])
    return shared.concat([
      ["space", "play or pause"], ["p / ,", "back " + (svc && svc.audible ? svc.audible.skipBackSeconds : 10) + " s"],
      ["n / .", "forward " + (svc && svc.audible ? svc.audible.skipForwardSeconds : 30) + " s"], ["- / =", "volume"],
      ["x", "speed"], ["S", "stop"], ["↵", "play a book"], ["/", "search the books"],
      ["s / ctrl s", "sort: recent, title, author"], ["r", "refresh the library"],
      ["esc", "clear the search / close"], ["?", "show or hide this list"]
    ])
  }

  function onKey(event) {
    var t = event.text
    var k = event.key
    var inField = isMusic ? (root.pages.length === 0 && root.tab === "search" && searchView.inputFocused)
      : isPodcasts ? podcastsView.inputFocused : audibleView.inputFocused
    if (k === Qt.Key_Escape) {
      if (root.allKeys) root.allKeys = false
      else if (root.settingsOpen) root.closeSettings()
      else root.back()
      event.accepted = true
      return
    }
    // Signing in to YouTube Music: the keyboard may fall back here while
    // Google's window is open or hidden (saving). A stray key must not
    // cancel it or start another; the card's Cancel button is the way out.
    if (isMusic && root.svc && root.svc.signingIn) {
      event.accepted = true
      return
    }
    // Ctrl+1/2/3: the sources, from anywhere (a text field included).
    if ((event.modifiers & Qt.ControlModifier) && (k === Qt.Key_1 || k === Qt.Key_2 || k === Qt.Key_3)) {
      root.showSource(Model.SOURCE_KEYS[k - Qt.Key_1])
      event.accepted = true
      return
    }
    // Ctrl+S: Audiobooks' sort, the search field included.
    if ((event.modifiers & Qt.ControlModifier) && k === Qt.Key_S && isBooks && !root.settingsOpen) {
      if (audibleView.authenticated) audibleView.cycleSort()
      event.accepted = true
      return
    }
    if ((event.modifiers & Qt.ControlModifier) && k === Qt.Key_Comma) {
      root.toggleSettings()
      event.accepted = true
      return
    }
    if (root.settingsOpen) {
      if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { settingsView.switchColumn(); event.accepted = true; return }
      if (k === Qt.Key_Down) { settingsView.move(1); event.accepted = true; return }
      if (k === Qt.Key_Up) { settingsView.move(-1); event.accepted = true; return }
      if (k === Qt.Key_Left) { settingsView.change(-1); event.accepted = true; return }
      if (k === Qt.Key_Right) { settingsView.change(1); event.accepted = true; return }
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { settingsView.act(); event.accepted = true; return }
      event.accepted = true
      return
    }
    if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
      root.switchPanel((event.modifiers & Qt.ShiftModifier) || k === Qt.Key_Backtab ? -1 : 1)
      event.accepted = true
      return
    }
    if (inField) {
      if (k === Qt.Key_Up) { event.accepted = true }
      return
    }
    var v = root.view
    var cur = v && v.current ? v.current : null
    var blocked = isMusic && keys.blocked
    if (k === Qt.Key_Down || t === "j") { if (v.move) v.move(1); event.accepted = true; return }
    if (k === Qt.Key_Up || t === "k") { if (v.move) v.move(-1); event.accepted = true; return }
    if (k === Qt.Key_Left || t === "h") {
      if (isMusic && root.pages.length) root.back()
      else if (isPodcasts && podcastsView.detailOpen) root.back()
      else if (!blocked) root.cycleTab(-1)
      event.accepted = true
      return
    }
    if (k === Qt.Key_Right || t === "l") {
      if (!(isMusic && root.pages.length) && !(isPodcasts && podcastsView.detailOpen) && !blocked) root.cycleTab(1)
      event.accepted = true
      return
    }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (isPodcasts) podcastsView.activate()
      else if (isBooks) audibleView.activate()
      else if (svc.closed) svc.startEngine()
      else if (v === queueView) queueView.activate()
      else if (v === libraryView && !libraryView.signedIn) svc.signIn()
      else if (cur) root.activateRow(cur, v === detailView ? detailView.contextList() : "")
      event.accepted = true
      return
    }
    if (k === Qt.Key_Space) { svc.mediaPlayPause(); event.accepted = true; return }
    if (k === Qt.Key_Backspace) { root.back(); event.accepted = true; return }
    if (k === Qt.Key_Delete) { if (isMusic && v === queueView) queueView.key("x"); event.accepted = true; return }
    if (!t) return
    if (v && v.key && v.key(t)) { event.accepted = true; return }
    var handled = true
    // Shared by every source: the sources, transport (on what the hero
    // shows), search, the key list.
    switch (t) {
      case "1": root.showSource("ytmusic"); event.accepted = true; return
      case "2": root.showSource("podcasts"); event.accepted = true; return
      case "3": root.showSource("audible"); event.accepted = true; return
      case "/": if (!isMusic) root.showSource("ytmusic"); root.showTab("search"); event.accepted = true; return
      case "n": svc.mediaNext(); event.accepted = true; return
      case "p": svc.mediaPrevious(); event.accepted = true; return
      case ",": svc.mediaSkip(-1); event.accepted = true; return
      case ".": svc.mediaSkip(1); event.accepted = true; return
      case "-": svc.mediaNudgeVolume(-1); event.accepted = true; return
      case "=": case "+": svc.mediaNudgeVolume(1); event.accepted = true; return
      case "?": root.allKeys = !root.allKeys; event.accepted = true; return
    }
    if (!isMusic) { event.accepted = false; return }
    switch (t) {
      case "m": svc.toggleMute(); break
      case "f": svc.toggleLike(); break
      case "d": svc.dislike(); break
      case "r": svc.cycleRepeat(); break
      case "s": svc.shuffle(); root.say("Queue shuffled"); break
      case "a": if (cur) root.runAction("queue", cur); break
      case "e": if (cur) root.runAction("next", cur); break
      case "R": if (cur && cur.item && cur.item.videoId) root.runAction("radio", cur); else if (svc.hasTrack) { svc.radioFor(svc.player); root.say("Radio from " + svc.title) } break
      case "g": root.openArtist(cur); break
      case "o": root.openAlbum(cur); break
      case "[": if (v === searchView) searchView.cycleFilter(-1); else if (v === libraryView) libraryView.cycleSection(-1); break
      case "]": if (v === searchView) searchView.cycleFilter(1); else if (v === libraryView) libraryView.cycleSection(1); break
      case "w": if (svc.gated) svc.signIn(); else svc.showWindow(); break
      case "W": svc.hideWindow(); break
      case "i": if (brand.showSignIn) svc.signIn(); else handled = false; break
      default: handled = false
    }
    event.accepted = handled
  }

  // g / o: the artist or album of the row under the cursor, else of the song.
  function openArtist(row) {
    var it = row && row.item && row.item.videoId ? row.item : (svc.hasTrack ? svc.player : null)
    var a = it && it.artists && it.artists.length && it.artists[0].id ? it.artists[0] : null
    if (a) openPage({ browseId: a.id, title: a.name })
  }
  function openAlbum(row) {
    var it = row && row.item && row.item.videoId ? row.item : (svc.hasTrack ? svc.player : null)
    if (it && it.album && it.album.id) openPage({ browseId: it.album.id, title: it.album.name })
  }


  // ---- surface

  Item { id: anchorDummy; visible: false }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem || anchorDummy
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(560))
    // Gated or off, the card is all there is: no empty stage under it.
    contentHeight: root.isMusic && root.svc && root.svc.gated && !root.settingsOpen
      ? panel.fittedContentHeight(heroSlot.height + sourceRow.height + gate.implicitHeight + Style.space(34))
      : root.isMusic && root.svc && root.svc.closed && !root.settingsOpen
      ? panel.fittedContentHeight(heroSlot.height + sourceRow.height + offCard.implicitHeight + Style.space(42))
      : panel.cappedContentHeight(Style.space(720))

    // A plain Item, not a FocusScope: a scope hands focus back to the child
    // that had it, so the search field would keep the keys after Enter.
    // Keys the field does not take still bubble up to here.
    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function (event) { root.onKey(event) }

      // While YouTube Music waits on Google (cookies, sign-in) there is one
      // thing to do there: the card. Off, the same: only the way back on.
      // Only on YouTube Music's tab: the other sources do not wait on it.
      readonly property bool gated: root.isMusic && root.svc ? root.svc.gated : false
      readonly property bool off: root.isMusic && root.svc ? root.svc.closed === true : false
      readonly property bool blocked: gated || off

      // ---- hero: YouTube Music's own (adverts, like, repeat), or the
      //      shared one for an episode or a book
      Item {
        id: heroSlot
        objectName: "panelHero"
        visible: !root.settingsOpen
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.heroIsMusic ? musicHero.implicitHeight : sourceHero.implicitHeight

        Views.NowPlaying {
          id: musicHero
          visible: root.heroIsMusic
          anchors.left: parent.left
          anchors.right: parent.right
          svc: root.svc
          bar: root.bar
          reserveRight: corner.width
        }

        Views.SourceHero {
          id: sourceHero
          objectName: "sourceHero"
          visible: !root.heroIsMusic
          anchors.left: parent.left
          anchors.right: parent.right
          svc: root.svc
          bar: root.bar
          reserveRight: corner.width
        }
      }

      // Top right, far from play: on YouTube Music, Solfa's corner (sign
      // in, Premium, the gear, power); elsewhere the source's own (refresh
      // and sign out for Podcasts) and the gear.
      Item {
        id: corner
        anchors.top: parent.top
        anchors.right: parent.right
        // The buttons' boxes reach into the card's padding, like "?".
        anchors.rightMargin: -Math.min(Style.space(8), Math.max(0, Style.spacing.popupPadding - Style.space(2)))
        width: root.isMusic ? brand.width : sourceCorner.width
        height: root.isMusic ? brand.height : sourceCorner.height

        Views.BrandCorner {
          id: brand
          objectName: "panelBrand"
          anchors.top: parent.top
          anchors.right: parent.right
          visible: root.isMusic
          svc: root.svc
          foreground: root.fg
          fontFamily: root.family
          settingsOpen: root.settingsOpen
          onGearClicked: root.toggleSettings()
        }

        Row {
          id: sourceCorner
          objectName: "sourceCorner"
          anchors.top: parent.top
          anchors.right: parent.right
          visible: !root.isMusic
          spacing: Style.space(4)

          readonly property var pc: root.svc && root.svc.pc ? root.svc.pc : null
          readonly property bool podcastsIn: root.isPodcasts && !!pc && pc.authenticated && !root.settingsOpen
          readonly property var ab: root.svc && root.svc.audible ? root.svc.audible : null
          readonly property bool booksIn: root.isBooks && !!ab && ab.authenticated && !root.settingsOpen

          Views.HitButton {
            anchors.verticalCenter: parent.verticalCenter
            minSize: Style.space(28)
            visible: sourceCorner.podcastsIn
            iconText: Icons.refresh
            iconSize: Style.font.body
            iconSpinning: !!sourceCorner.pc && sourceCorner.pc.busy
            foreground: root.fg
            opacity: hot ? 1 : 0.45
            tooltipText: "Refresh (r)"
            onClicked: podcastsView.refresh()
          }
          Views.HitButton {
            anchors.verticalCenter: parent.verticalCenter
            minSize: Style.space(28)
            visible: sourceCorner.booksIn
            iconText: Icons.refresh
            iconSize: Style.font.body
            iconSpinning: !!sourceCorner.ab && sourceCorner.ab.busy
            foreground: root.fg
            opacity: hot ? 1 : 0.45
            tooltipText: "Refresh the library (r)"
            onClicked: audibleView.refresh()
          }
          Views.HitButton {
            anchors.verticalCenter: parent.verticalCenter
            minSize: Style.space(28)
            visible: sourceCorner.booksIn
            iconText: Icons.signOut
            iconSize: Style.font.body
            foreground: root.fg
            opacity: hot ? 1 : 0.45
            tooltipText: sourceCorner.ab && sourceCorner.ab.email ? "Sign out " + sourceCorner.ab.email : "Sign out of Audible"
            onClicked: if (sourceCorner.ab) sourceCorner.ab.logout()
          }
          Views.HitButton {
            anchors.verticalCenter: parent.verticalCenter
            minSize: Style.space(28)
            visible: sourceCorner.podcastsIn
            iconText: Icons.signOut
            iconSize: Style.font.body
            foreground: root.fg
            opacity: hot ? 1 : 0.45
            tooltipText: sourceCorner.pc && sourceCorner.pc.email ? "Sign out " + sourceCorner.pc.email : "Sign out of Pocket Casts"
            onClicked: if (sourceCorner.pc) sourceCorner.pc.signOut()
          }
          Views.HitButton {
            objectName: "sourceGearButton"
            anchors.verticalCenter: parent.verticalCenter
            minSize: Style.space(28)
            iconText: Icons.gear
            iconSize: Style.font.body
            foreground: root.settingsOpen ? Color.accent : root.fg
            selected: root.settingsOpen
            opacity: root.settingsOpen || hot ? 1 : 0.45
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            tooltipText: "Settings (ctrl ,)"
            onClicked: root.toggleSettings()
          }
        }
      }

      // ---- the sources: 1, 2, 3
      Row {
        id: sourceRow
        objectName: "sourceTabs"
        visible: !root.settingsOpen
        anchors.top: heroSlot.bottom
        anchors.topMargin: Style.space(14)
        anchors.left: parent.left
        spacing: Style.space(4)

        Repeater {
          model: Model.SOURCES
          delegate: Views.HitButton {
            required property var modelData
            required property int index
            readonly property bool current: root.source === modelData.key
            iconText: Icons.sourceIcon(modelData.key)
            text: modelData.label
            fontFamily: root.family
            foreground: current ? Color.accent : root.fg
            selected: current
            bordered: current
            tooltipText: String(index + 1)
            onClicked: root.showSource(modelData.key)
          }
        }
      }

      Views.SignInCard {
        id: gate
        anchors.top: sourceRow.bottom
        anchors.topMargin: Style.space(12)
        width: parent.width
        visible: keys.gated && !root.settingsOpen
        svc: root.svc
        bar: root.bar
      }

      Views.OffCard {
        id: offCard
        objectName: "offCard"
        anchors.top: sourceRow.bottom
        anchors.topMargin: Style.space(18)
        width: parent.width
        visible: keys.off && !root.settingsOpen
        svc: root.svc
        bar: root.bar
      }

      // ---- the chosen source's tabs: ← →
      Row {
        id: tabRow
        objectName: "panelTabs"
        visible: !keys.blocked && !root.settingsOpen && root.subTabs.length > 0
        anchors.top: sourceRow.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        height: visible ? implicitHeight : 0
        spacing: Style.space(4)

        Repeater {
          model: root.subTabs
          delegate: Views.HitButton {
            required property var modelData
            required property int index
            text: root.isBooks ? audibleView.tabLabel(modelData) : modelData.label
            fontFamily: root.family
            foreground: root.fg
            fontSize: Style.font.caption
            selected: root.isMusic ? root.pages.length === 0 && root.tab === modelData.key
              : root.isBooks ? root.audibleTab === modelData.key
              : root.podcastTab === modelData.key && !podcastsView.detailOpen
            tooltipText: "← →"
            onClicked: root.showTab(modelData.key)
          }
        }
      }

      Row {
        anchors.verticalCenter: tabRow.verticalCenter
        anchors.right: parent.right
        spacing: Style.space(6)
        visible: root.isMusic && root.pages.length > 0 && !root.settingsOpen && tabRow.visible
        Views.HitButton {
          iconText: Icons.back
          text: "Back"
          fontFamily: root.family
          foreground: root.fg
          fontSize: Style.font.caption
          onClicked: root.back()
        }
      }

      // Settings takes it all, from the top row down: its "‹ Settings" back
      // row sits level with the corner, which stays (gear, power).
      Item {
        id: stage
        visible: root.settingsOpen || !keys.blocked
        anchors.top: root.settingsOpen ? parent.top : tabRow.visible ? tabRow.bottom : sourceRow.bottom
        anchors.topMargin: root.settingsOpen ? 0 : Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(8)

        // YouTube Music, exactly as in Solfa (root.view is one of these
        // only while YouTube Music is the source).
        Views.QueueView { id: queueView; anchors.fill: parent; visible: !root.settingsOpen && root.view === queueView; active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root }
        Views.SearchView { id: searchView; anchors.fill: parent; visible: !root.settingsOpen && root.view === searchView; active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root }
        Views.LibraryView { id: libraryView; anchors.fill: parent; visible: !root.settingsOpen && root.view === libraryView; active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root }
        Views.LyricsView { id: lyricsView; anchors.fill: parent; visible: !root.settingsOpen && root.view === lyricsView; active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root }
        Views.HistoryView { id: historyView; anchors.fill: parent; visible: !root.settingsOpen && root.view === historyView; active: root.opened && visible; svc: root.svc; bar: root.bar; panel: root }
        Views.DetailView { id: detailView; anchors.fill: parent; visible: !root.settingsOpen && root.view === detailView; svc: root.svc; bar: root.bar; panel: root }

        // Podcasts.
        Views.PodcastsView {
          id: podcastsView
          objectName: "podcastsView"
          anchors.fill: parent
          visible: !root.settingsOpen && root.view === podcastsView
          active: root.opened && visible
          svc: root.svc
          bar: root.bar
          panel: root
          tab: root.podcastTab
        }

        // Audiobooks.
        Views.AudibleView {
          id: audibleView
          objectName: "audibleView"
          anchors.fill: parent
          visible: !root.settingsOpen && root.view === audibleView
          active: root.opened && visible
          svc: root.svc
          bar: root.bar
          panel: root
          tab: root.audibleTab
        }

        Views.SettingsView {
          id: settingsView
          objectName: "settingsView"
          anchors.fill: parent
          visible: root.settingsOpen
          svc: root.svc
          fg: root.fg
          family: root.family
          onBackRequested: root.closeSettings()
          onShowAllKeys: { root.settingsOpen = false; root.allKeys = true }
        }

        // Every key, on "?".
        Rectangle {
          anchors.fill: parent
          visible: root.allKeys
          clip: true
          color: Color.popups.background
          radius: Style.spacing.labelGap
          Flow {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(10)
            Repeater {
              model: root.allKeyHints
              delegate: Views.KeyHint { required property var modelData; keys: modelData[0]; label: modelData[1]; bar: root.bar; maxWidth: (parent.width - Style.space(10)) / 2 }
            }
          }
        }
      }

      Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(32)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - allKeysButton.width - Style.space(4)
          visible: root.flash !== ""
          text: root.flash
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Color.accent
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        Row {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - (root.settingsOpen ? 0 : allKeysButton.width + Style.space(4))
          clip: true
          visible: root.flash === "" && !keys.blocked && !root.settingsOpen
          spacing: Style.space(12)
          Repeater {
            model: root.isMusic
              ? Model.footerHints(root.view ? root.view.hints : null,
                                  !!(root.svc && root.svc.hasTrack && !root.svc.isAd && root.svc.signedIn),
                                  root.pages.length === 0 && root.view === searchView && searchView.inputFocused)
              : root.isPodcasts
              ? (podcastsView.inputFocused ? [["↵", "next / sign in"], ["esc", "leave the field"]]
                : Model.footerHints(podcastsView.hints, false, false).concat([["1 2 3", "source"]]).slice(0, 4))
              : audibleView.signInFocused ? [["↵", "next / sign in"], ["esc", "leave the field"]]
              : audibleView.needsSetup ? Model.footerHints(audibleView.hints, false, false).concat([["1 2 3", "source"]]).slice(0, 4)
              : audibleView.hints
            delegate: Views.KeyHint { required property var modelData; keys: modelData[0]; label: modelData[1]; bar: root.bar }
          }
        }

        // Settings has its own, fixed hints: movement, not song controls.
        Row {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.settingsOpen && root.flash === ""
          spacing: Style.space(12)
          Repeater {
            model: [["↑↓", "move"], ["←→", "change"], ["Tab", "sections"], ["Esc", "back"]]
            delegate: Views.KeyHint { required property var modelData; keys: modelData[0]; label: modelData[1]; bar: root.bar }
          }
        }

        // Every key is one "?" away: typed, or clicked here.
        Views.HitButton {
          id: allKeysButton
          anchors.right: parent.right
          // "all keys" lines up with the edge: the box reaches into the card's
          // padding, never past it.
          anchors.rightMargin: -Math.min(Style.space(8), Math.max(0, Style.spacing.popupPadding - Style.space(2)))
          anchors.verticalCenter: parent.verticalCenter
          // Sized for the longer label: "close" does not shrink the box.
          width: allKeysSizer.implicitWidth + Style.space(16)
          visible: !keys.blocked && !root.settingsOpen
          foreground: root.fg
          onClicked: root.allKeys = !root.allKeys
          Views.KeyHint {
            id: allKeysHint
            anchors.centerIn: parent
            keys: "?"
            label: root.allKeys ? "close" : "all keys"
            bar: root.bar
          }
        }
        Views.KeyHint { id: allKeysSizer; visible: false; keys: "?"; label: "all keys"; bar: root.bar }
      }
    }
  }
}
