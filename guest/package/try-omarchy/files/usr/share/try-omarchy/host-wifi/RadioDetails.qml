import QtQuick
import QtQuick.Layouts
import qs.Ui
import qs.Commons
import "WifiModel.js" as WifiModel

Column {
  id: details
  required property var wifi
  required property var samples
  required property color foreground
  required property string fontFamily
  spacing: Style.space(12)
          GridLayout {
            width: parent.width
            columns: 4
            columnSpacing: Style.space(16)
            rowSpacing: Style.spacing.labelGap
            InfoLabel { text: "Quality" }
            InfoValue { text: WifiModel.quality(details.wifi) }
            InfoLabel { text: "Link rate" }
            InfoValue { text: WifiModel.display(details.wifi.txRateMbps, " Mbps") }
            InfoLabel { text: "Signal" }
            InfoValue { text: WifiModel.display(details.wifi.rssiDbm, " dBm") }
            InfoLabel { text: "Noise" }
            InfoValue { text: WifiModel.display(details.wifi.noiseDbm, " dBm") }
            InfoLabel { text: "SNR" }
            InfoValue { text: WifiModel.display(details.wifi.snrDb, " dB") }
            InfoLabel { text: "Channel" }
            InfoValue { text: WifiModel.channel(details.wifi) }
          }

          GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(20)
            rowSpacing: Style.spacing.labelGap
            InfoLabel { text: "Radio" }
            InfoValue { text: WifiModel.radio(details.wifi) }
            InfoLabel { text: "Security" }
            InfoValue { text: WifiModel.security(details.wifi) }
            InfoLabel { text: "BSSID" }
            InfoValue { text: WifiModel.display(details.wifi.bssid) }
          }

          PanelSeparator { foreground: details.foreground }
          PanelSectionHeader {
            text: "SIGNAL HISTORY · 2 MINUTES"
            foreground: details.foreground
            fontFamily: details.fontFamily
          }

          Rectangle {
            width: parent.width
            height: Style.space(110)
            color: Qt.rgba(details.foreground.r, details.foreground.g, details.foreground.b, 0.04)
            radius: Style.cornerRadius
            border.width: 1
            border.color: Qt.rgba(details.foreground.r, details.foreground.g, details.foreground.b, 0.15)

            Repeater {
              model: [-30, -50, -70, -90]
              Text {
                required property int modelData
                x: Style.space(6)
                y: Style.space(8) + (parent.height - Style.space(16)) * (-30 - modelData) / 60 - height / 2
                text: modelData + ""
                textFormat: Text.PlainText
                color: graph.levelColor(modelData)
                font.family: details.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Canvas {
              id: graph
              anchors.fill: parent
              anchors.margins: Style.space(8)
              anchors.leftMargin: Style.space(34)
              property var samples: details.samples
              property color lineColor: details.foreground
              function levelColor(dbm) {
                var dark = lineColor.r + lineColor.g + lineColor.b > 1.5
                return dbm < -70 ? (dark ? "#ed9b93" : "#ac3933")
                  : dbm < -55 ? (dark ? "#e9b85c" : "#8f5800")
                  : (dark ? "#8bc799" : "#287244")
              }
              onSamplesChanged: requestPaint()
              onLineColorChanged: requestPaint()
              onWidthChanged: requestPaint()
              onHeightChanged: requestPaint()
              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var now = Date.now()
                ctx.lineWidth = 1
                for (var dbm = -90; dbm <= -30; dbm += 20) {
                  ctx.strokeStyle = levelColor(dbm)
                  ctx.globalAlpha = 0.3
                  var y = height * (-30 - dbm) / 60
                  ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
                }
                ctx.globalAlpha = 1
                ctx.strokeStyle = lineColor
                ctx.lineWidth = 2
                var previous = null
                for (var i = 0; i < samples.length; i++) {
                  var sample = samples[i]
                  if (sample.rssi === null) { previous = null; continue }
                  var x = width * (1 - (now - sample.time) / 120000)
                  var sy = height * (-30 - Math.max(-90, Math.min(-30, sample.rssi))) / 60
                  if (previous && sample.time - previous.time <= 10000) {
                    ctx.beginPath(); ctx.moveTo(previous.x, previous.y); ctx.lineTo(x, sy); ctx.stroke()
                  }
                  ctx.beginPath(); ctx.arc(x, sy, 1.5, 0, Math.PI * 2); ctx.fillStyle = lineColor; ctx.fill()
                  previous = {x: x, y: sy, time: sample.time}
                }
              }
            }
            Text {
              anchors.centerIn: parent
              visible: !details.samples.some(function(sample) { return sample.rssi !== null })
              text: "Waiting for signal samples"
              textFormat: Text.PlainText
              color: details.foreground
              opacity: 0.6
              font.family: details.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
          RowLayout {
            width: parent.width
            spacing: Style.space(12)
            InfoLabel { text: "Weak <−70"; color: graph.levelColor(-90); opacity: 1 }
            InfoLabel { text: "Usable ≥−70"; color: graph.levelColor(-70); opacity: 1 }
            InfoLabel { text: "Strong ≥−55"; color: graph.levelColor(-50); opacity: 1 }
          }
          RowLayout {
            width: parent.width
            InfoLabel { text: "RSSI (dBm)" }
            Item { Layout.fillWidth: true }
            InfoLabel { text: "5-second samples" }
          }
  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: details.foreground
    opacity: 0.6
    font.family: details.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
  component InfoValue: Text {
    textFormat: Text.PlainText
    color: details.foreground
    font.family: details.fontFamily
    font.pixelSize: Style.font.bodySmall
    Layout.fillWidth: true
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
  }
}
