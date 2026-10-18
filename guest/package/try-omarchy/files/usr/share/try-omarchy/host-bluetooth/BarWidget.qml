import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Ui
import qs.Commons

Panel {
  id: root
  ipcTarget: "omarchy.bluetooth"
  moduleName: "omarchy.bluetooth"
  BluetoothService {
    id: bluetoothService
  }
  readonly property var service: bluetoothService
  property int cursor: -1
  property bool keyboardCursor: false
  readonly property bool needsAccess: service && service.authorization === "not-determined"
  readonly property int deviceOffset: needsAccess ? 1 : 0
  readonly property int settingsIndex: deviceOffset + (service ? service.devices.length : 0)
  function pointerCursor(index, over) {
    if (over) {
      keyboardCursor = false
      cursor = index
    } else if (!keyboardCursor && cursor === index)
      cursor = -1
  }
  function moveCursor(delta) {
    keyboardCursor = true
    cursor = Math.max(0, Math.min(settingsIndex, cursor + delta))
    Qt.callLater(function () {
      if (popup.loadedContent)
        popup.loadedContent.ensureCursorVisible()
    })
  }

  function activateCursor() {
    if (!service || service.busy)
      return
    if (cursor === settingsIndex)
      service.run("settings")
    else if (needsAccess && cursor === 0)
      service.run("refresh")
    else if (cursor >= deviceOffset && service.snapshot && service.snapshot.powered) {
      var device = service.devices[cursor - deviceOffset]
      if (device)
        service.run(device.connected ? "disconnect" : "connect", device.id)
    }
  }
  readonly property string icon: service ? service.icon : "󰂲"
  function open() {
    keyboardCursor = false
    cursor = -1
    controller.show()
    service.run("refresh")
  }
  function close() {
    controller.hide()
  }
  function toggle() {
    opened ? close() : open()
  }
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    tooltipText: root.service ? root.service.status : "Mac Bluetooth unavailable"
    active: root.opened
    useActiveColor: false
    onPressed: function (code) {
      if (code === Qt.LeftButton)
        root.toggle()
    }
  }
  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: popup.loadedContent
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(popup.loadedContentHeight)
    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      function ensureCursorVisible() {
        var row = root.cursor === root.settingsIndex ? settingsButton : root.needsAccess && root.cursor === 0 ? accessButton : deviceRows.itemAt(root.cursor - root.deviceOffset)
        if (row) {
          var top = row.mapToItem(column, 0, 0).y
          if (top < deviceList.contentY)
            deviceList.contentY = top
          else if (top + row.height > deviceList.contentY + deviceList.height)
            deviceList.contentY = top + row.height - deviceList.height
        }
      }
      onCloseRequested: root.close()
      onMoveRequested: function (dx, dy) {
        root.moveCursor(dy || dx)
      }
      onActivateRequested: root.activateCursor()
      onTabRequested: function (direction) {
        if (root.bar)
          root.bar.switchPanelFrom(root, direction)
      }
      Flickable {
        id: deviceList
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
            title: "Mac Bluetooth"
            meta: root.service ? root.service.status : "Unavailable"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconComponent: Component {
              Text {
                text: root.icon
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }
          Text {
            width: parent.width
            text: "Devices connect to your Mac. Bluetooth audio uses the Mac audio bridge."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Button {
            id: accessButton
            visible: root.service && root.service.authorization === "not-determined"
            width: parent.width
            text: "Allow Bluetooth Access on Mac"
            hasCursor: root.keyboardCursor && root.cursor === 0
            onHovered: function (over) {
              root.pointerCursor(0, over)
            }
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            enabled: root.service && !root.service.busy
            onClicked: root.service.run("refresh")
          }
          PanelSeparator {
            foreground: root.bar.foreground
          }
          PanelSectionHeader {
            text: "PAIRED DEVICES"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }
          Column {
            id: deviceColumn
            width: parent.width
            spacing: Style.space(12)
            Repeater {
              id: deviceRows
              model: root.service ? root.service.devices : []
              delegate: RowLayout {
                required property var modelData
                required property int index
                width: deviceColumn.width
                spacing: Style.space(12)
                Column {
                  Layout.fillWidth: true
                  Text {
                    width: parent.width
                    text: modelData.name
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: root.service.pending === modelData.id ? "Working…" : modelData.connected ? "Connected" : "Not connected"
                    color: root.bar.foreground
                    opacity: 0.6
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
                Button {
                  text: modelData.connected ? "Disconnect" : "Connect"
                  hasCursor: root.keyboardCursor && root.cursor === index + root.deviceOffset
                  onHovered: function (over) {
                    root.pointerCursor(index + root.deviceOffset, over)
                  }
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  enabled: root.service && !root.service.busy && root.service.snapshot.powered
                  onClicked: root.service.run(modelData.connected ? "disconnect" : "connect", modelData.id)
                }
              }
            }
          }

          Text {
            visible: !root.service || root.service.devices.length === 0
            width: parent.width
            text: root.service && root.service.authorization === "allowed" ? "No paired devices. Pair a device in Mac Bluetooth Settings." : "Allow access on your Mac to show paired devices."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            visible: text !== ""
            width: parent.width
            text: root.service ? root.service.message : ""
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          PanelSeparator {
            foreground: root.bar.foreground
          }
          Button {
            id: settingsButton
            width: parent.width
            text: "Open Mac Bluetooth Settings"
            hasCursor: root.keyboardCursor && root.cursor === root.settingsIndex
            onHovered: function (over) {
              root.pointerCursor(root.settingsIndex, over)
            }
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            enabled: root.service && !root.service.busy
            onClicked: root.service.run("settings")
          }
        }
      }
    }
  }
}
