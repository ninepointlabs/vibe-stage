import QtQuick
import qs.Ui
import qs.Commons
import "lib/Model.js" as Model
import "lib/PodcastModel.js" as PM
import "lib/Icons.js" as Icons
import "views" as Views

// The bar pill, one for every source: the cover, a small mark for the source
// it shows, the title, and previous / play-pause / next. YouTube Music keeps
// Solfa's round cover in a progress ring; podcasts and audiobooks get a
// rounded square cover and a title that scrolls while it plays. Left click
// opens the panel, middle click plays or pauses, right click skips, the
// wheel sets the volume (Shift+wheel seeks) — always on the source shown
// (the service's controlSource).
BarWidget {
  id: root
  moduleName: "ninepointlabs.vibe-stage"

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("ninepointlabs.vibe-stage") : null

  // The service reads its settings from this widget's shell.json entry,
  // and saves new ones back through the shell's plugin API (Settings).
  // The shell assigns this widget's `bar` before its `settings`, so for a
  // moment `settings` is still the empty default: that is not an entry, and
  // the service must never see it (it would start the engine on defaults).
  function pushSettings() {
    if (!root.svc || !root.bar || !Model.hasSettings(root.settings)) return
    if (typeof root.svc.adoptSettings === "function") root.svc.adoptSettings(root.settings)
    else root.svc.settings = root.settings
    root.svc.shell = root.bar ? root.bar.shell : null
  }
  onSvcChanged: { pushSettings(); injectPanel() }
  onSettingsChanged: { pushSettings(); injectPanel() }
  onBarChanged: { pushSettings(); injectPanel() }
  Component.onCompleted: pushSettings()

  // ---- the shape Bar.findPanelWidget expects (shell summon/hide/toggle)
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var p = panelLoader.item
    if (!p) return
    p.bar = root.bar
    p.settings = root.settings
    p.anchorItem = root
    p.hostWidget = root
    p.svc = root.svc
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  // ---- which source the pill shows (a service without sources: YouTube Music)
  readonly property string source: svc && svc.controlSource ? svc.controlSource : "ytmusic"
  readonly property bool isMusic: source === "ytmusic"
  readonly property var pc: svc && svc.pc ? svc.pc : null
  readonly property var ab: svc && svc.audible ? svc.audible : null

  // ---- state
  readonly property bool hasTrack: !svc ? false : isMusic ? svc.hasTrack
    : source === "podcasts" ? !!(pc && pc.playerActive)
    : source === "audible" ? !!(ab && ab.playerActive) : false
  // Closed: YouTube Music is off. The pill dims; any click starts it again
  // (a left click also opens the panel).
  readonly property bool closed: isMusic && svc ? svc.closed === true : false
  readonly property bool playing: !svc ? false : isMusic ? svc.isPlaying
    : source === "podcasts" ? !!(pc && pc.isPlaying)
    : source === "audible" ? !!(ab && ab.isPlaying) : false
  readonly property bool showControls: root.setting("barControls", true) && hasTrack && !vertical
  readonly property bool signingIn: isMusic && svc ? svc.signingIn === true : false
  readonly property bool showTitle: root.setting("showTitle", true) && !vertical
  readonly property real maxLabelWidth: Number(root.setting("maxLabelWidth", 160)) || 160
  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property string trackTitle: !svc ? "" : isMusic ? (svc.title || "") : source === "podcasts" && pc ? pc.title : source === "audible" && ab ? ab.title : ""
  readonly property string trackSubtitle: !svc ? "" : isMusic ? (svc.artist || "") : source === "podcasts" && pc ? pc.show : source === "audible" && ab ? ab.author : ""
  readonly property string art: !svc ? "" : isMusic ? (svc.thumb || "") : source === "podcasts" && pc ? pc.art : source === "audible" && ab ? ab.art : ""
  readonly property real progress: !svc ? 0 : isMusic ? (svc.progress || 0) : source === "podcasts" && pc ? pc.progress : source === "audible" && ab ? ab.progress : 0
  // Why the source shown has nothing playing (its helper is down, it is
  // signed out, starting): said in the bar, dimmed, instead of a blank.
  readonly property string health: !svc ? "" : typeof svc.healthOf === "function" ? svc.healthOf(source)
    : (svc.engineLine || "")
  // The bar is shared: the title only. The show, artist, album and time are in the tooltip.
  readonly property string label: signingIn ? "Signing in…" : hasTrack ? trackTitle : "Vibe Stage"
  // Idle: the source's name, or what is wrong with it, dimmed.
  readonly property string subLabel: hasTrack || signingIn ? "" : (health || Model.sourceLabel(source))

  // Always shown: this is the one media chip in the bar.
  implicitWidth: body.implicitWidth + Style.space(10)
  implicitHeight: barSize

  Row {
    id: body
    anchors.centerIn: parent
    spacing: Style.space(6)
    opacity: root.closed ? 0.45 : 1
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    Item {
      id: coverSlot
      anchors.verticalCenter: parent.verticalCenter
      width: root.isMusic ? musicCover.width : podCover.width
      height: root.isMusic ? musicCover.height : podCover.height

      // While a sign-in runs (the panel closes when the Google window is
      // used), the bar's icon breathes: something is happening.
      transformOrigin: Item.Center
      SequentialAnimation on scale {
        loops: Animation.Infinite
        running: root.signingIn
        onRunningChanged: if (!running) coverSlot.scale = 1
        NumberAnimation { from: 0.85; to: 1.1; duration: 1400; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.1; to: 0.85; duration: 1400; easing.type: Easing.InOutSine }
      }

      Views.BarCover {
        id: musicCover
        visible: root.isMusic
        barSize: root.barSize
        hasTrack: root.hasTrack
        progress: root.progress
        ringColor: root.playing ? Color.accent : Util.alpha(root.fg, 0.45)
        trackColor: Util.alpha(root.fg, 0.15)
        source: root.isMusic ? root.art : ""
        foreground: root.fg
        fill: root.hasTrack ? Util.alpha(root.fg, 0.08) : "transparent"
        fontFamily: root.family
        dim: root.hasTrack && !root.playing
        opacity: root.closed || (root.svc && (root.svc.ready || root.svc.hasTrack)) ? 1 : 0.55
      }

      Views.SquareCover {
        id: podCover
        visible: !root.isMusic
        width: Math.round(root.barSize * 0.78)
        height: width
        source: root.isMusic ? "" : root.art
        glyph: Icons.sourceIcon(root.source)
        foreground: root.fg
        fill: root.hasTrack ? Util.alpha(root.fg, 0.08) : "transparent"
        fontFamily: root.family
        dim: root.hasTrack && !root.playing
        opacity: root.hasTrack || root.health === "" ? 1 : 0.55
      }

      // The source's mark, small, at the cover's lower right: which of the
      // three the pill is showing. Only over a cover; idle, the glyph in
      // the cover already says it.
      Rectangle {
        id: sourceBadge
        objectName: "sourceBadge"
        visible: root.hasTrack
        readonly property real size: Math.max(9, Math.round(root.barSize * 0.38))
        width: size
        height: size
        radius: size / 2
        x: parent.width - size * 0.7
        y: parent.height - size * 0.7
        color: Color.bar.background
        Text {
          anchors.centerIn: parent
          text: Icons.sourceIcon(root.source)
          textFormat: Text.PlainText
          color: root.playing ? Color.accent : root.fg
          font.family: root.family
          font.pixelSize: Math.max(7, Math.round(sourceBadge.size * 0.72))
        }
      }
    }

    // The title. Podcast and audiobook titles are long: past the width they
    // scroll while playing (and the panel is closed), like the Pocket Casts
    // chip did; a song title is cut short, as before.
    Item {
      id: labelClip
      visible: root.showTitle
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
      height: labelText.implicitHeight
      clip: true

      Text {
        id: labelText
        anchors.verticalCenter: parent.verticalCenter
        width: scrolls ? implicitWidth : labelClip.width
        text: root.label
        textFormat: Text.PlainText
        elide: scrolls ? Text.ElideNone : Text.ElideRight
        color: root.fg
        font.family: root.family
        font.pixelSize: Style.font.body
        readonly property bool scrolls: !root.isMusic && root.hasTrack && implicitWidth > root.maxLabelWidth + 1

        NumberAnimation on x {
          running: labelText.scrolls && root.playing && !root.opened
          loops: Animation.Infinite
          duration: Math.max(6000, labelText.implicitWidth * 28)
          from: labelClip.width
          to: -labelText.implicitWidth
          easing.type: Easing.Linear
        }
        onScrollsChanged: if (!scrolls) x = 0
        onTextChanged: x = 0
      }
    }

    Text {
      id: subLabelText
      visible: root.showTitle && root.subLabel !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(root.maxLabelWidth, implicitWidth)
      text: root.subLabel
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Util.alpha(root.fg, 0.5)
      font.family: root.family
      font.pixelSize: Style.font.caption
    }

    Row {
      visible: root.showControls
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      BarIconButton {
        bar: root.bar
        text: root.isMusic ? Icons.previous : Icons.skipBack
        tooltipText: root.isMusic ? "Previous" : "Skip back"
        slotSize: Math.round(Style.bar.iconSlot * 0.85)
        onPressed: function (b) { if (b === Qt.LeftButton && root.svc) root.previous() }
      }
      BarIconButton {
        bar: root.bar
        text: root.playing ? Icons.pause : Icons.play
        tooltipText: root.playing ? "Pause" : "Play"
        slotSize: Math.round(Style.bar.iconSlot * 0.85)
        onPressed: function (b) { if (b === Qt.LeftButton && root.svc) root.playPause() }
      }
      BarIconButton {
        bar: root.bar
        text: root.isMusic ? Icons.next : Icons.skipForward
        tooltipText: root.isMusic ? "Next" : "Skip forward"
        slotSize: Math.round(Style.bar.iconSlot * 0.85)
        onPressed: function (b) { if (b === Qt.LeftButton && root.svc) root.skip() }
      }
    }
  }

  // The actions, on the source shown. A service without sources (a test's
  // fake) is YouTube Music's own.
  function playPause() {
    if (!root.svc) return
    if (typeof root.svc.mediaPlayPause === "function") root.svc.mediaPlayPause()
    else root.svc.togglePlaying()
  }
  function previous() {
    if (!root.svc) return
    if (typeof root.svc.mediaPrevious === "function") root.svc.mediaPrevious()
    else root.svc.previous()
  }
  // Next song, or skip forward in an episode (what the Pocket Casts chip did).
  function skip() {
    if (!root.svc) return
    if (!root.isMusic && typeof root.svc.mediaSkip === "function") root.svc.mediaSkip(1)
    else if (typeof root.svc.mediaNext === "function") root.svc.mediaNext()
    else root.svc.next()
  }

  // Clicks and wheel on the cover and the title (the buttons take their own).
  MouseArea {
    x: body.x
    y: 0
    width: coverSlot.width + (labelClip.visible ? labelClip.width + body.spacing : 0)
      + (subLabelText.visible ? subLabelText.width + body.spacing : 0) + Style.space(5)
    height: parent.height
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    property real wheelAcc: 0

    onClicked: function (mouse) {
      if (root.closed) {
        root.svc.startEngine()
        if (mouse.button === Qt.LeftButton) root.toggle()
        return
      }
      if (mouse.button === Qt.MiddleButton) root.playPause()
      else if (mouse.button === Qt.RightButton) root.skip()
      else root.toggle()
    }
    onWheel: function (wheel) {
      if (!root.svc || !root.hasTrack) return
      var w = Util.wheelSteps(wheelAcc, wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x)
      wheelAcc = w.remainder
      if (w.steps === 0) return
      var media = typeof root.svc.mediaNudgeVolume === "function"
      if (wheel.modifiers & Qt.ShiftModifier) {
        if (media) root.svc.mediaSeekBy(w.steps * 5)
        else root.svc.seekBy(w.steps * 5)
      } else {
        if (media) root.svc.mediaNudgeVolume(w.steps)
        else root.svc.nudgeVolume(w.steps)
      }
    }
    onEntered: {
      if (!root.bar) return
      root.bar.showTooltip(root, root.tooltip())
    }
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  function tooltip() {
    var s = root.svc
    if (!s) return "Vibe Stage"
    var name = Model.sourceLabel(root.source)
    if (root.isMusic) {
      return s.hasTrack
        ? s.title + (s.artist ? "\n" + s.artist : "") + (s.album ? "\n" + s.album : "")
          + "\n" + Model.fmtTime(s.position) + " of " + Model.fmtTime(s.duration) + ", volume " + (s.muted ? "muted" : s.volume + "%")
        : s.closed ? "YouTube Music is off. Click to turn it on."
        : (s.engineLine || "YouTube Music: nothing playing. Click to search.")
    }
    if (root.source === "podcasts" && root.pc) {
      var p = root.pc
      return p.playerActive
        ? name + (p.isPlaying ? "" : " (paused)") + "\n" + p.title + (p.show ? "\n" + p.show : "")
          + "\n" + PM.fmtTime(p.localPosition) + " of " + PM.fmtTime(p.duration) + ", volume " + p.volume + "%"
          + (p.speed !== 1 ? ", " + PM.fmtSpeed(p.speed) : "")
        : name + ": " + (p.healthLine || "nothing playing. Click to pick an episode.")
    }
    if (root.source === "audible" && root.ab) {
      var a = root.ab
      return a.playerActive
        ? name + (a.isPlaying ? "" : " (paused)") + "\n" + a.title + (a.author ? "\n" + a.author : "")
          + "\n" + PM.fmtTime(a.localPosition) + " of " + PM.fmtTime(a.duration) + ", volume " + a.volume + "%"
          + (a.speed !== 1 ? ", " + PM.fmtSpeed(a.speed) : "")
        : name + ": " + (a.healthLine || "nothing playing. Click to pick a book.")
    }
    return name + ": nothing playing"
  }
}
