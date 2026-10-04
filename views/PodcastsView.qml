import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/PodcastModel.js" as PM
import "../lib/Icons.js" as Icons

// The Podcasts source in the panel: Up Next, In Progress, New and Podcasts
// (the panel's sub-tabs pick `tab`), and a show's own episode list opened
// from Podcasts. Rows come from PodcastModel.js and draw in the same RowList
// as YouTube Music's views, so the keys are the same: ↑↓ move, ↵ plays an
// episode or opens a show, Esc / ← go back from a show. Signed out, it is
// the Pocket Casts sign-in card instead.
Item {
  id: view

  property var svc: null
  property QtObject bar: null
  property var panel: null
  property string tab: "upnext"
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  // On screen: the panel is open on this view (see QueueView).
  property bool active: false

  readonly property var pc: svc && svc.pc ? svc.pc : null
  readonly property bool authenticated: pc ? pc.authenticated === true : false
  readonly property bool needsSetup: pc ? pc.probed && !pc.authenticated : false
  readonly property bool detailOpen: !!(pc && pc.detail)
  readonly property string nowUuid: pc ? pc.nowUuid : ""

  // The model's rows (header / note / item), and the same rows as RowList
  // draws them. Notes alone (loading, empty, an error) are the list's
  // centred empty text instead of a header line.
  readonly property var modelRows: pc ? PM.tabRows(pc, tab) : []
  readonly property bool onlyNotes: {
    for (var i = 0; i < modelRows.length; i++) if (modelRows[i].kind === "item") return false
    return true
  }
  readonly property var rows: onlyNotes ? [] : PM.displayRows(modelRows, nowUuid, detailOpen)
  readonly property string noteText: {
    if (!onlyNotes) return ""
    var parts = []
    for (var i = 0; i < modelRows.length; i++) if (modelRows[i].text) parts.push(modelRows[i].text)
    return parts.join("\n")
  }

  property alias cursor: list.cursor
  readonly property var current: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  readonly property var currentItem: current && current.item ? current.item.source : null
  readonly property var hints: needsSetup ? [["↵", "sign in"]]
    : detailOpen ? [["↵", "play"], ["q", "up next"], ["esc", "back"]]
    : [["↵", tab === "podcasts" ? "open" : "play"], ["q", "up next"], ["m", "played"]]

  readonly property bool inputFocused: emailField.activeFocus || passwordField.activeFocus

  function move(dy) { list.cursor = Model.moveCursor(rows, list.cursor, dy) }

  // Opening the tab loads it (if stale); Up Next is always kept fresh, the
  // hero's next button reads it.
  function shown() {
    if (!pc) return
    pc.refreshIfStale()
    pc.loadTab(tab, false)
    if (tab !== "upnext") pc.loadUpNext(false)
    list.cursor = Model.firstRow(rows)
    if (needsSetup) Qt.callLater(focusInput)
  }
  onTabChanged: { if (pc) pc.closeDetail(); if (active) shown() }
  onRowsChanged: if (list.cursor < 0 || list.cursor >= rows.length) list.cursor = Model.firstRow(rows)
  onNeedsSetupChanged: if (needsSetup && active) Qt.callLater(focusInput)

  function focusInput() { if (emailField.text === "") emailField.forceActiveFocus(); else passwordField.forceActiveFocus() }

  function actionsFor(row) {
    var it = row && row.item ? row.item.source : null
    if (!it || it.type === "podcast") return []
    var queued = pc && PM.containsUuid(pc.upNext, it.uuid)
    var played = it.status === PM.statusPlayed
    return [
      { name: "mark", icon: played ? Icons.unplayed : Icons.played, tip: played ? "Mark as unplayed (m)" : "Mark as played (m)" },
      { name: "queue", icon: queued ? Icons.close : Icons.queue, tip: queued ? "Remove from Up Next (q)" : "Add to Up Next (q)" }
    ]
  }

  function activateRow(row) {
    var it = row && row.item ? row.item.source : null
    if (!it || !pc) return
    if (it.type === "podcast") { pc.openDetail(it); list.cursor = Model.firstRow(rows); return }
    if (it.uuid === nowUuid) pc.playPause()
    else pc.playItem(it, false)
  }
  function activate() {
    if (needsSetup) { focusInput(); return }
    activateRow(current)
  }

  function runAction(name, row) {
    var it = row && row.item ? row.item.source : null
    if (!it || !pc || it.type === "podcast") return
    if (name === "queue") pc.toggleQueued(it)
    else if (name === "mark") pc.markPlayed(it, it.status !== PM.statusPlayed)
  }

  // Esc / ← / Backspace: out of a show first. False: nothing to go back from.
  function back() {
    if (!detailOpen) return false
    pc.closeDetail()
    list.cursor = Model.firstRow(rows)
    return true
  }

  function refresh() {
    if (!pc) return
    pc.refresh()
    pc.loadTab(tab, true)
    if (pc.detail && pc.detail.item) pc.openDetail(pc.detail.item)
  }

  function signIn() {
    if (pc && pc.login(emailField.text, passwordField.text)) passwordField.text = ""
  }

  // Keys only Podcasts has (the panel handles the shared ones).
  function key(t) {
    if (!pc || !authenticated) return false
    if (t === "q") { runAction("queue", current); return true }
    if (t === "m") { runAction("mark", current); return true }
    if (t === "r") { refresh(); return true }
    if (t === "x") { pc.cycleSpeed(); return true }
    if (t === "s") { if (pc.playerActive) pc.stop(); return true }
    return false
  }

  onActiveChanged: if (!active) passwordField.text = ""

  // ---- a show's header: back, its cover, its name
  Item {
    id: detailHeader
    visible: view.authenticated && view.detailOpen
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: visible ? Style.space(52) : 0

    Row {
      anchors.fill: parent
      spacing: Style.space(10)

      HitButton {
        anchors.verticalCenter: parent.verticalCenter
        iconText: Icons.back
        foreground: view.fg
        fontFamily: view.family
        tooltipText: "Back (esc)"
        onClicked: view.back()
      }
      SquareCover {
        id: detailArt
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(44)
        height: width
        source: view.detailOpen ? PM.artSource(view.pc.detail.item) : ""
        foreground: view.fg
        fill: Util.alpha(view.fg, 0.08)
        fontFamily: view.family
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.space(32) - detailArt.width - parent.spacing * 2
        spacing: Style.space(2)
        Text {
          width: parent.width
          text: view.detailOpen && view.pc.detail.item ? (view.pc.detail.item.name || "") : ""
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: view.fg
          font.family: view.family
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          width: parent.width
          text: view.detailOpen && view.pc.detail.item ? (view.pc.detail.item.author || "") : ""
          textFormat: Text.PlainText
          elide: Text.ElideRight
          visible: text !== ""
          color: Util.alpha(view.fg, 0.6)
          font.family: view.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  RowList {
    id: list
    visible: !view.needsSetup
    anchors.top: detailHeader.bottom
    anchors.topMargin: detailHeader.visible ? Style.space(6) : 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    bar: view.bar
    rows: view.rows
    actionsFor: view.actionsFor
    emptyText: !view.pc ? ""
      : !view.pc.probed ? (view.pc.healthLine || "Starting the Pocket Casts helper")
      : view.noteText
    onActivated: function (i) { view.activateRow(view.rows[i]) }
    onAction: function (name, i) { view.runAction(name, view.rows[i]) }
  }

  // ---- signed out: the sign-in card
  Flickable {
    id: signInCard
    objectName: "podcastsSignIn"
    visible: view.needsSetup
    anchors.fill: parent
    contentWidth: width
    contentHeight: signInColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: signInColumn
      width: signInCard.width
      spacing: Style.space(10)
      topPadding: Style.space(4)

      Text {
        width: parent.width
        text: view.pc && view.pc.needsReauth ? "Your Pocket Casts session expired" : "Sign in to Pocket Casts"
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: view.fg
        font.family: view.family
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      TextField {
        id: emailField
        width: parent.width
        placeholderText: "Email"
        text: view.pc ? view.pc.email : ""
        foreground: view.fg
        font.family: view.family
        enabled: !(view.pc && view.pc.loginRunning)
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
          width: parent.width - signInButton.width - parent.spacing
          placeholderText: "Password"
          password: true
          foreground: view.fg
          font.family: view.family
          enabled: !(view.pc && view.pc.loginRunning)
          Keys.onReturnPressed: view.signIn()
          Keys.onEnterPressed: view.signIn()
          Keys.onEscapePressed: { text = ""; if (view.panel) view.panel.focusKeys() }
          Keys.onBacktabPressed: emailField.forceActiveFocus()
        }

        Button {
          id: signInButton
          anchors.verticalCenter: parent.verticalCenter
          text: view.pc && view.pc.loginRunning ? "Signing in…" : "Sign in"
          bordered: true
          foreground: view.fg
          fontFamily: view.family
          enabled: !(view.pc && view.pc.loginRunning)
          onClicked: view.signIn()
        }
      }

      Text {
        visible: text !== ""
        width: parent.width
        text: view.pc ? view.pc.loginError : ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Color.urgent
        font.family: view.family
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: PM.signInNotes
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

      Text {
        visible: !!(view.pc && !view.pc.mpvInstalled)
        width: parent.width
        text: "Audio plays through mpv, which is not installed. Run: omarchy pkg add mpv"
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Color.urgent
        font.family: view.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}
