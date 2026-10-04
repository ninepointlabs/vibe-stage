import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../lib/PodcastModel.js" as PM
import "../lib/Icons.js" as Icons

// The top of the panel for the sources that are not YouTube Music (whose
// own hero, NowPlaying, keeps its adverts, like and repeat): the episode
// or book the bar shows (the service's controlSource), its square cover,
// time, and skip back / play / skip forward / next (Podcasts only), speed
// and volume. Every
// control goes through the service's media* actions, so it acts on the same
// source as the bar and the media keys.
Column {
  id: root

  property var svc: null
  property QtObject bar: null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  // Width kept free at the top right (the panel's gear sits there).
  property real reserveRight: 0

  readonly property string source: svc && svc.controlSource ? svc.controlSource : "podcasts"
  readonly property var pc: svc && svc.pc ? svc.pc : null
  readonly property bool isPodcast: source === "podcasts"
  readonly property var ab: svc && svc.audible ? svc.audible : null
  readonly property bool isBook: source === "audible"
  // The source the controls drive: both have the same player actions.
  readonly property var media: isPodcast ? pc : isBook ? ab : null
  readonly property bool hasTrack: svc ? svc.nowHasTrack === true : false
  readonly property bool playing: svc ? svc.nowPlaying === true : false
  readonly property real duration: svc ? (svc.nowDuration || 0) : 0
  readonly property real position: svc ? (svc.nowPosition || 0) : 0
  readonly property int volume: svc ? (svc.nowVolume !== undefined ? svc.nowVolume : 100) : 100
  readonly property real speed: media ? media.speed : 1
  // Paused or idle, Pocket Casts remembers the last episode: shown dimmed.
  readonly property var lastItem: isPodcast && pc && !hasTrack ? pc.heroItem : null

  spacing: Style.space(10)

  Row {
    width: parent.width
    spacing: Style.space(14)

    SquareCover {
      id: cover
      width: Style.space(84)
      height: width
      source: root.hasTrack ? (root.svc ? root.svc.nowArt : "") : (root.lastItem ? PM.artSource(root.lastItem) : "")
      glyph: Icons.sourceIcon(root.source)
      foreground: root.fg
      fill: Util.alpha(root.fg, 0.08)
      fontFamily: root.family
      dim: root.hasTrack && !root.playing
      opacity: root.hasTrack ? 1 : 0.55

      MouseArea {
        anchors.fill: parent
        enabled: !!root.media
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.svc) root.svc.mediaPlayPause()
      }
    }

    Column {
      width: parent.width - cover.width - parent.spacing - root.reserveRight
      anchors.verticalCenter: cover.verticalCenter
      spacing: Style.space(3)

      Text {
        width: parent.width
        text: root.hasTrack ? root.svc.nowTitle
          : root.lastItem ? (root.lastItem.name || "Nothing playing")
          : "Nothing playing"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 2
        wrapMode: Text.WordWrap
        color: root.hasTrack ? root.fg : Util.alpha(root.fg, 0.75)
        font.family: root.family
        font.pixelSize: Style.font.heading
        font.bold: root.hasTrack
      }
      Text {
        width: parent.width
        text: root.hasTrack ? (root.svc.nowSubtitle || Model.sourceLabel(root.source))
          : root.lastItem ? "Last played" + (root.lastItem.show ? " · " + root.lastItem.show : "")
          : Model.sourceLabel(root.source)
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Util.alpha(root.fg, 0.75)
        font.family: root.family
        font.pixelSize: Style.font.body
        visible: text !== ""
      }
      // What the source is doing, or why it has nothing (helper down,
      // signed out, an action that failed).
      Text {
        width: parent.width
        text: root.isPodcast ? PM.statusLine(root.pc) || (root.svc ? root.svc.healthOf(root.source) : "")
          : root.isBook && root.ab ? root.ab.statusLine
          : (root.svc ? root.svc.healthOf(root.source) : "")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.isPodcast && root.pc && (root.pc.actionError || root.pc.playerError || root.pc.lastError) ? Color.urgent
          : root.isBook && root.ab && (root.ab.actionError || root.ab.lastError) ? Color.urgent
          : Util.alpha(root.fg, 0.5)
        font.family: root.family
        font.pixelSize: Style.font.caption
        visible: text !== ""
      }
    }
  }

  // ---- time
  Column {
    width: parent.width
    spacing: Style.space(2)
    visible: root.hasTrack

    PanelSlider {
      id: seek
      width: parent.width
      bar: root.bar
      minimum: 0
      maximum: root.duration > 0 ? root.duration : 1
      value: root.position
      step: 1
      integer: true
      enabled: root.duration > 0 && !!root.media
      fillColor: Color.accent
      onReleased: function (v) { if (root.media) root.media.seek(v) }
    }

    Item {
      width: parent.width
      height: posText.implicitHeight
      Text {
        id: posText
        text: PM.fmtTime(seek.dragging ? seek.liveValue : root.position)
        textFormat: Text.PlainText
        color: Util.alpha(root.fg, 0.6)
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
      Text {
        anchors.right: parent.right
        text: root.duration > 0 ? "-" + PM.fmtTime(Math.max(0, root.duration - (seek.dragging ? seek.liveValue : root.position))) : ""
        textFormat: Text.PlainText
        color: Util.alpha(root.fg, 0.6)
        font.family: root.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  // ---- controls (the same squares as NowPlaying's)
  Item {
    id: controls
    width: parent.width
    height: Math.max(transport.height, volumeRow.height)
    visible: !!root.media && (root.hasTrack || root.media.authenticated)

    readonly property real slot: Style.space(44)
    readonly property real playSlot: Style.space(48)
    readonly property real volumeSlot: Style.space(36)
    readonly property real glyph: Style.font.iconLarge

    Row {
      id: transport
      spacing: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter

      HitButton {
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.slot
        iconText: Icons.skipBack
        iconSize: controls.glyph
        foreground: root.fg
        fontFamily: root.family
        enabled: root.hasTrack
        opacity: enabled ? 1 : 0.4
        tooltipText: "Back " + (root.media ? root.media.skipBackSeconds : 10) + " s (p or ,)"
        onClicked: if (root.svc) root.svc.mediaPrevious()
      }
      HitButton {
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.playSlot
        iconText: root.playing ? Icons.pause : Icons.play
        iconSize: Math.round(controls.glyph * 1.3)
        foreground: root.fg
        fontFamily: root.family
        bordered: true
        tooltipText: (root.playing ? "Pause" : "Play") + " (space)"
        onClicked: if (root.svc) root.svc.mediaPlayPause()
      }
      HitButton {
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.slot
        iconText: Icons.skipForward
        iconSize: controls.glyph
        foreground: root.fg
        fontFamily: root.family
        enabled: root.hasTrack
        opacity: enabled ? 1 : 0.4
        tooltipText: "Forward " + (root.media ? root.media.skipForwardSeconds : 30) + " s (.)"
        onClicked: if (root.svc) root.svc.mediaSkip(1)
      }
      HitButton {
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.slot
        visible: root.isPodcast
        iconText: Icons.next
        iconSize: controls.glyph
        foreground: root.fg
        fontFamily: root.family
        enabled: !!root.pc && root.pc.upNext.length > (root.hasTrack ? 1 : 0)
        opacity: enabled ? 1 : 0.4
        tooltipText: "Next in Up Next (n)"
        onClicked: if (root.svc) root.svc.mediaNext()
      }
      HitButton {
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.slot
        text: PM.fmtSpeed(root.speed)
        fontSize: Style.font.caption
        foreground: root.speed !== 1 ? Color.accent : root.fg
        fontFamily: root.family
        selected: root.speed !== 1
        tooltipText: "Playback speed (x)"
        onClicked: if (root.media) root.media.cycleSpeed()
      }
    }

    Row {
      id: volumeRow
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      HitButton {
        anchors.verticalCenter: parent.verticalCenter
        minSize: controls.volumeSlot
        iconText: Icons.volumeIcon(root.volume, false)
        foreground: root.fg
        fontFamily: root.family
        tooltipText: root.volume === 0 ? "Unmute" : "Mute"
        onClicked: if (root.media) root.media.setVolume(root.volume === 0 ? 70 : 0)
      }
      // On a narrow card the slider gives way first; - and = still work.
      PanelSlider {
        anchors.verticalCenter: parent.verticalCenter
        visible: controls.width >= transport.width + controls.volumeSlot + width + Style.space(24)
        width: Style.space(100)
        bar: root.bar
        minimum: 0
        maximum: 100
        step: 5
        integer: true
        value: root.volume
        onMoved: function (v) { if (root.media) root.media.setVolume(v) }
        onReleased: function (v) { if (root.media) root.media.setVolume(v) }
      }
    }
  }
}
