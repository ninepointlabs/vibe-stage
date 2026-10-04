import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/PodcastModel.js" as PM
import "../lib/Icons.js" as Icons

// The Audiobooks source in the panel: the Audible library on three shelves
// (In Progress, All, Finished: the panel's sub-tabs pick `tab`), sorted by
// the source's `sortOrder` (s), narrowed by the search field (/), in the
// same RowList as the other views (↑↓ move, ↵ plays a book or pauses the one
// playing). Signed out, it is the Audible sign-in card instead; signed in
// with the library still on its way, a loading line.
Item {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null
  property string tab: "progress"
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  // On screen: the panel is open on this view (see QueueView).
  property bool active: false

  readonly property var ab: svc && svc.audible ? svc.audible : null
  readonly property bool authenticated: ab ? ab.authenticated === true : false
  readonly property bool needsSetup: ab ? ab.probed && !ab.authenticated : false
  readonly property bool loading: !!ab && authenticated && !ab.libraryLoaded
  readonly property bool listShown: !needsSetup && !loading
  readonly property string nowAsin: ab ? ab.nowAsin : ""
  readonly property string startingAsin: ab ? ab.startingAsin : ""
  readonly property string query: searchField.text.trim()
  readonly property string sortLabel: ab && ab.sortLabel ? ab.sortLabel : "Recent"

  readonly property var statusTab: ({ "in-progress": "progress", "finished": "finished" })

  function onShelf(b, key) { return key === "all" || statusTab[b.status] === key }

  // How many books each shelf holds, whatever the search.
  readonly property var counts: {
    var c = { progress: 0, all: 0, finished: 0 }
    var books = ab && authenticated ? (ab.library || []) : []
    for (var i = 0; i < books.length; i++) {
      c.all++
      var key = statusTab[books[i].status]
      if (key) c[key]++
    }
    return c
  }

  // "In Progress (27)" for the panel's sub-tab, once the library is here.
  function tabLabel(t) {
    if (!t) return ""
    return ab && ab.libraryLoaded && counts[t.key] !== undefined ? t.label + " (" + counts[t.key] + ")" : t.label
  }

  // Every word typed must be in the title or an author's name.
  function matches(b, words) {
    if (words.length === 0) return true
    var hay = ((b.title || "") + " " + (ab ? ab.authorsText(b.authors) : "")).toLowerCase()
    for (var i = 0; i < words.length; i++) if (hay.indexOf(words[i]) < 0) return false
    return true
  }

  readonly property var rows: {
    if (!ab || !authenticated) return []
    var books = ab.sortedLibrary || ab.library || []
    var words = query === "" ? [] : query.toLowerCase().split(/\s+/)
    var out = []
    for (var i = 0; i < books.length; i++) {
      var b = books[i]
      if (!onShelf(b, tab) || !matches(b, words)) continue
      out.push({ item: view.bookItem(b), current: (!!nowAsin && b.asin === nowAsin) || (!!startingAsin && b.asin === startingAsin) })
    }
    return out
  }

  function bookItem(b) {
    var duration = Number(b.duration_sec) || 0
    var position = Math.max(0, Math.min(duration, Number(b.last_position_sec) || 0))
    var it = {
      kind: "book",
      title: b.title || "",
      subtitle: view.subtitle(b),
      thumb: b.cover_url || "",
      duration: duration,
      durationText: PM.fmtDuration(duration),
      played: b.status === "finished",
      asin: b.asin || "",
      badge: b.status === "in-progress" ? "In Progress" : b.status === "finished" ? "Finished" : "New",
      badgeTone: b.status === "in-progress" ? "accent" : b.status === "finished" ? "muted" : "faint",
      source: b
    }
    if (b.status === "in-progress" && duration > 0) {
      it.progress = position / duration
      var left = PM.fmtDuration(duration - position)
      it.progressText = Math.floor(it.progress * 100) + "%" + (left ? " · " + left + " left" : "")
    }
    return it
  }

  // Author · narrator, and a book that is opening says so.
  function subtitle(b) {
    var parts = []
    var author = ab ? ab.authorsText(b.authors) : ""
    if (author) parts.push(author)
    if (b.narrator) parts.push("read by " + b.narrator)
    if (b.asin === startingAsin) parts.push("opening…")
    return parts.join(" · ")
  }

  readonly property string emptyText: !ab ? ""
    : !ab.probed ? (ab.healthLine || "Starting the Audible helper")
    : ab.libraryError !== "" ? ab.libraryError
    : !ab.libraryLoaded || rows.length > 0 ? ""
    : query !== "" ? "No books match “" + query + "”."
    : counts.all === 0 ? "Your Audible library is empty."
    : tab === "progress" ? "Nothing in progress. Pick a book from All."
    : tab === "finished" ? "No finished books yet."
    : ""

  property alias cursor: list.cursor
  readonly property var current: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  readonly property var hints: needsSetup ? [["↵", "sign in"]]
    : searchFocused ? [["↵", "to the books"], ["↓", "books"], ["esc", "leave the field"]]
    : [["↵", "play"], ["← →", "shelf"], ["/", "search"], ["s", "sort"], ["space", "play/pause"]]

  readonly property bool signInFocused: emailField.activeFocus || passwordField.activeFocus || codeField.activeFocus
  readonly property bool searchFocused: searchField.activeFocus
  readonly property bool inputFocused: signInFocused || searchFocused

  function move(dy) { list.cursor = Model.moveCursor(rows, list.cursor, dy) }

  // Back to the first book, scrolled to the top.
  function toTop() {
    list.cursor = Model.firstRow(rows)
    list.positionViewAtBeginning()
  }

  function shown() {
    if (!ab) return
    ab.refreshIfStale()
    toTop()
    if (needsSetup) Qt.callLater(focusInput)
  }
  onTabChanged: toTop()
  onQueryChanged: toTop()
  onRowsChanged: if (list.cursor < 0 || list.cursor >= rows.length) list.cursor = Model.firstRow(rows)
  // A hidden field keeps the keyboard: once the card goes, the keys go back
  // to the panel (the list's ↑↓ and ↵).
  onNeedsSetupChanged: {
    if (needsSetup && active) Qt.callLater(focusInput)
    else if (!needsSetup && signInFocused && panel) panel.focusKeys()
  }
  onListShownChanged: if (!listShown && searchFocused && panel) panel.focusKeys()

  function focusSearch() {
    if (!listShown) return
    searchField.forceActiveFocus()
    searchField.selectAll()
  }

  // Out of the field, onto the books (Enter, ↓).
  function leaveSearch() {
    if (panel) panel.focusKeys()
    if (list.cursor < 0) list.cursor = Model.firstRow(rows)
  }

  function clearSearch() { searchField.text = "" }

  function cycleSort() {
    if (!ab || !ab.cycleSort) return
    ab.cycleSort()
    toTop()
  }

  // Esc / Backspace: a search is cleared first. False: nothing to go back from.
  function back() {
    if (searchField.text === "") return false
    clearSearch()
    return true
  }

  function focusInput() {
    if (ab && ab.loginNeeds !== "") codeField.forceActiveFocus()
    else if (emailField.text === "") emailField.forceActiveFocus()
    else passwordField.forceActiveFocus()
  }

  function activateRow(row) {
    var it = row && row.item ? row.item : null
    if (!it || !ab || !it.asin) return
    if (it.asin === nowAsin) ab.playPause()
    else ab.play(it.asin, false)
  }
  function activate() {
    if (needsSetup) { focusInput(); return }
    activateRow(current)
  }

  function refresh() {
    if (!ab) return
    if (authenticated) ab.loadLibrary(true)
    else ab.refresh()
  }

  function signIn() {
    if (ab && ab.login(emailField.text, passwordField.text, codeField.text)) codeField.text = ""
  }

  // Keys only Audiobooks has (the panel handles the shared ones).
  function key(t) {
    if (!ab || !authenticated) return false
    if (t === "/") { focusSearch(); return true }
    if (t === "s") { cycleSort(); return true }
    if (t === "S") { ab.stop(); return true }
    if (t === "r") { refresh(); return true }
    if (t === "x") { ab.cycleSpeed(); return true }
    return false
  }

  // The password stays in the field across a code round trip (the code is
  // sent with it), and is gone once signed in or the panel closes. So is a
  // search: the next open shows the whole shelf.
  onActiveChanged: if (!active) { passwordField.text = ""; codeField.text = ""; searchField.text = "" }
  onAuthenticatedChanged: if (authenticated) { passwordField.text = ""; codeField.text = "" }

  // ---- the search field, and the sort to its right
  Item {
    id: toolbar
    objectName: "audibleToolbar"
    visible: view.listShown
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: visible ? Math.max(searchField.implicitHeight, sortButton.height) : 0

    TextField {
      id: searchField
      objectName: "audibleSearch"
      anchors.left: parent.left
      anchors.right: sortButton.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      placeholderText: "Search books by title or author"
      foreground: view.fg
      font.family: view.family
      leftPadding: Style.space(28)
      rightPadding: Style.space(30)
      Keys.onEscapePressed: function (e) { view.leaveSearch(); e.accepted = true }
      Keys.onReturnPressed: function (e) { view.leaveSearch(); e.accepted = true }
      Keys.onEnterPressed: function (e) { view.leaveSearch(); e.accepted = true }
      Keys.onDownPressed: function (e) { view.leaveSearch(); e.accepted = true }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(9)
        anchors.verticalCenter: parent.verticalCenter
        text: Icons.search
        textFormat: Text.PlainText
        color: Util.alpha(view.fg, searchField.activeFocus ? 0.8 : 0.45)
        font.family: view.family
        font.pixelSize: Style.font.body
      }

      HitButton {
        objectName: "audibleSearchClear"
        anchors.right: parent.right
        anchors.rightMargin: Style.space(2)
        anchors.verticalCenter: parent.verticalCenter
        minSize: Style.space(24)
        visible: searchField.text !== ""
        iconText: Icons.close
        iconSize: Style.font.body
        foreground: view.fg
        fontFamily: view.family
        opacity: hot ? 1 : 0.55
        tooltipText: "Clear (esc)"
        onClicked: view.clearSearch()
      }
    }

    HitButton {
      id: sortButton
      objectName: "audibleSort"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      minSize: Style.space(28)
      iconText: Icons.sort
      iconSize: Style.font.body
      text: view.sortLabel
      fontFamily: view.family
      fontSize: Style.font.caption
      foreground: view.fg
      tooltipText: "Sort: recent, title, author (s)"
      onClicked: view.cycleSort()
    }
  }

  RowList {
    id: list
    visible: view.listShown
    anchors.top: toolbar.bottom
    anchors.topMargin: toolbar.visible ? Style.space(8) : 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    bar: view.bar
    rows: view.rows
    emptyText: view.emptyText
    onActivated: function (i) { view.activateRow(view.rows[i]) }
  }

  // ---- signed in, the library on its way
  Column {
    objectName: "audibleLoading"
    visible: view.loading
    anchors.centerIn: parent
    width: parent.width - Style.space(40)
    spacing: Style.space(10)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Icons.refresh
      textFormat: Text.PlainText
      color: Color.accent
      font.family: view.family
      font.pixelSize: Style.font.iconLarge
      visible: !!view.ab && view.ab.libraryLoading
      RotationAnimation on rotation {
        running: parent.visible
        loops: Animation.Infinite
        from: 0
        to: 360
        duration: 1100
      }
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: view.ab && view.ab.libraryError !== "" ? view.ab.libraryError + "\nPress r to try again."
        : "Loading your library…"
      textFormat: Text.PlainText
      color: view.ab && view.ab.libraryError !== "" ? Color.urgent : Util.alpha(view.fg, 0.6)
      font.family: view.family
      font.pixelSize: Style.font.body
    }
  }

  // ---- signed out: the sign-in card
  Flickable {
    id: signInCard
    objectName: "audibleSignIn"
    visible: view.needsSetup
    anchors.fill: parent
    contentWidth: width
    contentHeight: signInColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    readonly property bool running: !!(view.ab && view.ab.loginRunning)
    readonly property bool usable: !!(view.ab && view.ab.available)
    readonly property string needs: view.ab ? view.ab.loginNeeds : ""

    Column {
      id: signInColumn
      width: signInCard.width
      spacing: Style.space(10)
      topPadding: Style.space(4)

      Row {
        spacing: Style.space(8)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: Icons.audible
          textFormat: Text.PlainText
          color: Color.accent
          font.family: view.family
          font.pixelSize: Style.font.heading
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Sign in to Audible"
          textFormat: Text.PlainText
          color: view.fg
          font.family: view.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }
      }

      // Without the audible package there is nothing to sign in with.
      Text {
        visible: !signInCard.usable
        width: parent.width
        text: view.ab ? (view.ab.availableError || view.ab.healthLine) : ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Color.urgent
        font.family: view.family
        font.pixelSize: Style.font.caption
      }

      TextField {
        id: emailField
        width: parent.width
        placeholderText: "Amazon email"
        text: view.ab ? view.ab.email : ""
        foreground: view.fg
        font.family: view.family
        enabled: signInCard.usable && !signInCard.running && signInCard.needs === ""
        Keys.onReturnPressed: passwordField.forceActiveFocus()
        Keys.onEnterPressed: passwordField.forceActiveFocus()
        Keys.onEscapePressed: if (view.panel) view.panel.focusKeys()
        Keys.onTabPressed: passwordField.forceActiveFocus()
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        TextField {
          id: passwordField
          width: parent.width - (signInCard.needs === "" ? signInButton.width + parent.spacing : 0)
          placeholderText: "Password"
          password: true
          foreground: view.fg
          font.family: view.family
          enabled: signInCard.usable && !signInCard.running && signInCard.needs === ""
          Keys.onReturnPressed: view.signIn()
          Keys.onEnterPressed: view.signIn()
          Keys.onEscapePressed: { text = ""; if (view.panel) view.panel.focusKeys() }
          Keys.onBacktabPressed: emailField.forceActiveFocus()
        }

        Button {
          id: signInButton
          visible: signInCard.needs === ""
          anchors.verticalCenter: parent.verticalCenter
          text: signInCard.running ? "Signing in…" : "Sign in"
          bordered: true
          foreground: view.fg
          fontFamily: view.family
          enabled: signInCard.usable && !signInCard.running
          onClicked: view.signIn()
        }
      }

      // Amazon asked for a code: the same sign-in again, with it.
      Row {
        visible: signInCard.needs !== ""
        width: parent.width
        spacing: Style.space(8)

        TextField {
          id: codeField
          width: parent.width - codeButton.width - startOver.width - parent.spacing * 2
          placeholderText: signInCard.needs === "otp" ? "One-time code" : "Verification code"
          foreground: view.fg
          font.family: view.family
          enabled: !signInCard.running
          Keys.onReturnPressed: view.signIn()
          Keys.onEnterPressed: view.signIn()
          Keys.onEscapePressed: if (view.panel) view.panel.focusKeys()
        }

        Button {
          id: codeButton
          anchors.verticalCenter: parent.verticalCenter
          text: signInCard.running ? "Signing in…" : "Continue"
          bordered: true
          foreground: view.fg
          fontFamily: view.family
          enabled: !signInCard.running
          onClicked: view.signIn()
        }

        Button {
          id: startOver
          anchors.verticalCenter: parent.verticalCenter
          text: "Start over"
          foreground: view.fg
          fontFamily: view.family
          enabled: !signInCard.running
          onClicked: { codeField.text = ""; if (view.ab) view.ab.resetLogin(); emailField.forceActiveFocus() }
        }
      }

      Text {
        visible: text !== ""
        width: parent.width
        text: view.ab ? view.ab.loginError : ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Color.urgent
        font.family: view.family
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: signInCard.running
        width: parent.width
        text: "If Amazon asks you to approve this sign-in (an email or a notification on your phone), approve it there; this waits for up to two minutes."
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Color.accent
        font.family: view.family
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: [
          "Uses your Amazon email and password once, to register Vibe Stage as a device on your Audible account; only that device's tokens are kept, never the password.",
          "Signing out removes the device from your account again.",
          "Books play through mpv, and where you stop is saved back to Audible."
        ]
        delegate: Text {
          required property var modelData
          width: signInColumn.width
          text: modelData
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: Util.alpha(view.fg, 0.6)
          font.family: view.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
