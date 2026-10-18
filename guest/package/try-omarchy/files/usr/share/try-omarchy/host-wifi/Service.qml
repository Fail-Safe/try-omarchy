import QtQuick
import Quickshell
import Quickshell.Io
import "WifiModel.js" as WifiModel

Item {
  id: root
  property var settings: ({})
  property var snapshot: null
  property var samples: []
  property string connectionKey: ""

  function record(data) {
    var key = data && data.associated ? [data.interface, data.ssid, data.bssid, data.ipAddress].join("|") : ""
    if (key && connectionKey && key !== connectionKey) samples = []
    if (key) connectionKey = key
    snapshot = data
    samples = WifiModel.history(samples, data, Date.now())
  }
  readonly property string radioIcon: WifiModel.icon(snapshot)
  readonly property var connection: WifiModel.connection(snapshot)
  readonly property string networkMode: connection.mode
  readonly property bool bridgedWifi: connection.bridgedWifi
  readonly property bool showRadio: connection.showRadio
  readonly property var status: WifiModel.view(snapshot)

  FileView {
    id: state
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/try-omarchy-hostnet/wifi.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.record(JSON.parse(text())) }
      catch (error) { root.record(null) }
    }
    onLoadFailed: root.record(null)
  }

  // Retry missing files too: the shell can start before the first snapshot.
  Timer { interval: 5000; running: true; repeat: true; onTriggered: state.reload() }
}
