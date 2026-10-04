import QtQuick
import QtQuick.Effects
import qs.Commons
import "../lib/Icons.js" as Icons

// A cover with rounded corners (podcast and audiobook art, square by nature;
// the round one is YouTube Music's record), with a glyph while there is no
// picture. Rounded on rounded themes, square on sharp ones. `dim` fades it,
// for a paused episode. Ported from the Pocket Casts plugin's RoundedArt.
Item {
  id: root

  property url source: ""
  property color foreground: "white"
  property color fill: "transparent"
  property string glyph: Icons.podcast
  property string fontFamily: ""
  property bool dim: false
  property real cornerRadius: Style.cornerRadius > 0 ? Math.max(2, Math.round(width * 0.18)) : 0
  readonly property bool showsImage: String(source) !== "" && img.status === Image.Ready

  implicitWidth: 32
  implicitHeight: 32

  Rectangle {
    anchors.fill: parent
    radius: root.cornerRadius
    color: root.fill
    visible: !root.showsImage

    Text {
      anchors.centerIn: parent
      text: root.glyph
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Math.max(8, Math.round(root.width * 0.5))
    }
  }

  Image {
    id: img
    anchors.fill: parent
    source: root.source
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    smooth: true
    mipmap: true
    sourceSize.width: Math.ceil(root.width * 2)
    sourceSize.height: Math.ceil(root.height * 2)
    visible: false
    layer.enabled: true
  }

  Rectangle {
    id: mask
    anchors.fill: parent
    radius: root.cornerRadius
    visible: false
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: parent
    visible: root.showsImage
    source: img
    maskEnabled: true
    maskSource: mask
    opacity: root.dim ? 0.72 : 1
    Behavior on opacity { NumberAnimation { duration: 160 } }
  }
}
