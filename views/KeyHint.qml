import QtQuick
import qs.Commons

// A key and what it does, for the hint line.
Row {
  id: hint

  property string keys: ""
  property string label: ""
  property QtObject bar: null
  // Set to fit the hint in a column: a longer label wraps instead of
  // running into the next one. 0 leaves it on one line.
  property real maxWidth: 0
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  spacing: Style.space(5)

  Rectangle {
    id: keyBox
    anchors.verticalCenter: parent.verticalCenter
    width: keyText.implicitWidth + Style.space(8)
    height: keyText.implicitHeight + Style.space(2)
    radius: Style.space(3)
    color: Util.alpha(hint.fg, 0.08)
    border.width: 1
    border.color: Util.alpha(hint.fg, 0.18)
    Text {
      id: keyText
      anchors.centerIn: parent
      text: hint.keys
      textFormat: Text.PlainText
      color: Util.alpha(hint.fg, 0.85)
      font.family: hint.family
      font.pixelSize: Style.font.caption
    }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    width: hint.maxWidth > 0 ? Math.min(implicitWidth, hint.maxWidth - keyBox.width - hint.spacing) : implicitWidth
    wrapMode: hint.maxWidth > 0 ? Text.WordWrap : Text.NoWrap
    text: hint.label
    textFormat: Text.PlainText
    color: Util.alpha(hint.fg, 0.55)
    font.family: hint.family
    font.pixelSize: Style.font.caption
  }
}
