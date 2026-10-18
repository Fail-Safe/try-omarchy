import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import "WifiModel.js" as WifiModel
import qs.Ui

BarWidget {
  id: root
  moduleName: "tryomarchy.host-wifi"
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property var status: service ? service.status : ({
      label: "Unavailable",
      bars: 0,
      tooltip: "Mac Wi-Fi: unavailable"
    })
  readonly property string icon: WifiModel.icon(service ? service.snapshot : null)
  readonly property bool opened: details.opened
  readonly property bool popoutSwitchClosing: details.popoutSwitchClosing
  function open() {
    details.open()
  }
  function close() {
    details.close()
  }
  function toggle() {
    details.toggle()
  }
  function closeForPopoutSwitch() {
    details.closeForPopoutSwitch()
  }
  function switchPanel(direction) {
    return root.bar && typeof root.bar.switchPanelFrom === "function" ? root.bar.switchPanelFrom(root, direction) : false
  }
  visible: !service || service.networkMode !== "bridged"
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    tooltipText: root.status.tooltip
    active: root.opened
    useActiveColor: false
    onPressed: function (code) {
      if (code === Qt.LeftButton)
        root.toggle()
    }
  }

  Panel {
    id: details
    moduleName: root.moduleName
    ipcTarget: root.moduleName
    bar: root.bar
    readonly property var wifi: root.service && root.service.snapshot ? root.service.snapshot : ({})
    readonly property var samples: root.service ? root.service.samples : []
    readonly property color foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
    readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

    KeyboardPanel {
      id: popup
      anchorItem: button
      owner: root
      bar: root.bar
      open: details.opened
      focusTarget: popup.loadedContent
      contentWidth: popup.fittedContentWidth(Style.space(400))
      contentHeight: popup.fittedContentHeight(popup.loadedContentHeight)

      content: PanelKeyCatcher {
        implicitHeight: column.implicitHeight
        anchors.fill: parent
        onMoveRequested: function (dx, dy) {
          contentScroll.contentY = Math.max(0, Math.min(contentScroll.contentHeight - contentScroll.height, contentScroll.contentY + (dy || dx) * Style.space(40)))
        }
        onCloseRequested: root.close()
        onTabRequested: function (direction) {
          root.switchPanel(direction)
        }

        Flickable {
          id: contentScroll
          anchors.fill: parent
          contentWidth: width
          contentHeight: column.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          Controls.ScrollBar.vertical: Controls.ScrollBar {
            policy: Controls.ScrollBar.AsNeeded
          }
          Column {
            id: column
            width: parent.width
            spacing: Style.space(12)

            PanelHero {
              title: "Mac Wi-Fi"
              meta: root.status.label
              foreground: details.foreground
              fontFamily: details.fontFamily
              iconComponent: Component {
                Text {
                  text: root.icon
                  textFormat: Text.PlainText
                  color: details.foreground
                  font.family: details.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }

            Text {
              width: parent.width
              visible: details.wifi.ssidUnavailable === true
              text: "Connected · macOS requires Location access to show the network name."
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: details.foreground
              opacity: 0.6
              font.family: details.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            GridLayout {
              width: parent.width
              columns: 4
              columnSpacing: Style.space(16)
              rowSpacing: Style.spacing.labelGap
              InfoLabel {
                text: "Quality"
              }
              InfoValue {
                text: WifiModel.quality(details.wifi)
              }
              InfoLabel {
                text: "Link rate"
              }
              InfoValue {
                text: WifiModel.display(details.wifi.txRateMbps, " Mbps")
              }
              InfoLabel {
                text: "Signal"
              }
              InfoValue {
                text: WifiModel.display(details.wifi.rssiDbm, " dBm")
              }
              InfoLabel {
                text: "Noise"
              }
              InfoValue {
                text: WifiModel.display(details.wifi.noiseDbm, " dBm")
              }
              InfoLabel {
                text: "SNR"
              }
              InfoValue {
                text: WifiModel.display(details.wifi.snrDb, " dB")
              }
              InfoLabel {
                text: "Channel"
              }
              InfoValue {
                text: WifiModel.channel(details.wifi)
              }
            }

            GridLayout {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(20)
              rowSpacing: Style.spacing.labelGap
              InfoLabel {
                text: "Mac Wi-Fi IP"
              }
              InfoValue {
                text: WifiModel.display(details.wifi.ipAddress)
              }
              InfoLabel {
                text: "Radio"
              }
              InfoValue {
                text: WifiModel.radio(details.wifi)
              }
              InfoLabel {
                text: "Security"
              }
              InfoValue {
                text: WifiModel.security(details.wifi)
              }
              InfoLabel {
                text: "BSSID"
              }
              InfoValue {
                text: WifiModel.display(details.wifi.bssid)
              }
            }

            PanelSeparator {
              foreground: details.foreground
            }
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
                  return dbm < -70 ? (dark ? "#ed9b93" : "#ac3933") : dbm < -55 ? (dark ? "#e9b85c" : "#8f5800") : (dark ? "#8bc799" : "#287244")
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
                    ctx.beginPath()
                    ctx.moveTo(0, y)
                    ctx.lineTo(width, y)
                    ctx.stroke()
                  }
                  ctx.globalAlpha = 1
                  ctx.strokeStyle = lineColor
                  ctx.lineWidth = 2
                  var previous = null
                  for (var i = 0; i < samples.length; i++) {
                    var sample = samples[i]
                    if (sample.rssi === null) {
                      previous = null
                      continue
                    }
                    var x = width * (1 - (now - sample.time) / 120000)
                    var sy = height * (-30 - Math.max(-90, Math.min(-30, sample.rssi))) / 60
                    if (previous && sample.time - previous.time <= 10000) {
                      ctx.beginPath()
                      ctx.moveTo(previous.x, previous.y)
                      ctx.lineTo(x, sy)
                      ctx.stroke()
                    }
                    ctx.beginPath()
                    ctx.arc(x, sy, 1.5, 0, Math.PI * 2)
                    ctx.fillStyle = lineColor
                    ctx.fill()
                    previous = {
                      x: x,
                      y: sy,
                      time: sample.time
                    }
                  }
                }
              }
              Text {
                anchors.centerIn: parent
                visible: !details.samples.some(function (sample) {
                  return sample.rssi !== null
                })
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
              InfoLabel {
                text: "Weak <−70"
                color: graph.levelColor(-90)
                opacity: 1
              }
              InfoLabel {
                text: "Usable ≥−70"
                color: graph.levelColor(-70)
                opacity: 1
              }
              InfoLabel {
                text: "Strong ≥−55"
                color: graph.levelColor(-50)
                opacity: 1
              }
            }
            RowLayout {
              width: parent.width
              InfoLabel {
                text: "RSSI (dBm)"
              }
              Item {
                Layout.fillWidth: true
              }
              InfoLabel {
                text: "5-second samples"
              }
            }
          }
        }
      }
    }
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
