import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property var settings: ({})
  property var snapshot: null
  property string pending: ""
  property string message: ""
  readonly property bool busy: action.running
  readonly property var devices: snapshot && snapshot.devices ? snapshot.devices : []
  readonly property string authorization: snapshot ? snapshot.authorization : "unavailable"
  readonly property string status: authorization === "denied" ? "Bluetooth permission denied on Mac"
    : authorization === "restricted" ? "Bluetooth access restricted on Mac"
    : authorization === "not-determined" ? "Allow Bluetooth access on Mac"
    : authorization !== "allowed" ? "Mac Bluetooth unavailable"
    : snapshot.powered ? "Bluetooth on" : "Bluetooth off"
  readonly property string icon: authorization !== "allowed" || !snapshot.powered ? "󰂲"
    : devices.some(function(device) { return device.connected }) ? "󰂱" : "󰂯"

  function run(kind, device) {
    if (busy) return
    pending = device || kind
    message = ""
    var args = ["/usr/bin/omarchy-host-bluetooth", kind]
    if (device) args.push(device)
    action.command = args
    action.running = true
  }

  Process {
    id: action
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.message = JSON.parse(text).message || "Action completed" }
        catch (error) { root.message = "Mac Bluetooth action did not return a result" }
      }
    }
    onExited: { root.pending = ""; state.reload() }
  }
  FileView {
    id: state
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/try-omarchy-hostnet/bluetooth.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.snapshot = JSON.parse(text()) }
      catch (error) { root.snapshot = null }
    }
    onLoadFailed: root.snapshot = null
  }
  Timer { interval: 5000; running: true; repeat: true; onTriggered: state.reload() }
}
