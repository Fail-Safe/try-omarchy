function view(data) {
  if (!data || data.type !== "wifi") return { label: "Unavailable", bars: 0, tooltip: "Mac Wi-Fi: unavailable" }
  if (!data.powered) return { label: "Off", bars: 0, tooltip: "Mac Wi-Fi: off" }
  if (!data.associated) return { label: "Disconnected", bars: 0, tooltip: "Mac Wi-Fi: not connected" }
  var name = typeof data.ssid === "string" && data.ssid.length ? data.ssid : "Connected"
  name = name.replace(/[\u0000-\u001f\u007f]/g, " ")
  var rssi = typeof data.rssiDbm === "number" ? data.rssiDbm : null
  var strength = rssi === null ? 0 : rssi >= -55 ? 4 : rssi >= -65 ? 3 : rssi >= -75 ? 2 : 1
  return { label: name, bars: strength, tooltip: "Mac Wi-Fi: " + name + (rssi === null ? " · Signal unavailable" : " · " + rssi + " dBm") }
}

function display(value, suffix) {
  if (value === null || value === undefined || value === "") return "--"
  return String(value).replace(/[\u0000-\u001f\u007f]/g, " ") + (suffix || "")
}

function quality(data) {
  if (!data || !data.associated || typeof data.rssiDbm !== "number") return "Unavailable"
  return data.rssiDbm >= -55 ? "Excellent" : data.rssiDbm >= -65 ? "Good" : data.rssiDbm >= -75 ? "Fair" : "Weak"
}

function radio(data) {
  if (!data || !data.associated) return "--"
  var band = {"2g": "2.4 GHz", "5g": "5 GHz", "6g": "6 GHz"}[data.band]
  return [band, data.phyMode].filter(function(value) { return !!value }).join(" · ") || "--"
}

function security(data) {
  if (!data || !data.associated) return "--"
  return display(data.security).replace(/-/g, " ").toUpperCase()
}

function channel(data) {
  if (!data || !data.associated || data.channel === null || data.channel === undefined) return "--"
  return display(data.channel) + (data.channelWidthMhz ? " (" + data.channelWidthMhz + " MHz)" : "")
}

function history(samples, data, now) {
  var next = samples.filter(function(sample) { return sample.time >= now - 120000 })
  if (next.length && now - next[next.length - 1].time < 4000) return next
  var rssi = data && data.associated && typeof data.rssiDbm === "number" ? data.rssiDbm : null
  next.push({time: now, rssi: rssi})
  return next.slice(-25)
}

// Match the glyph family used by Omarchy's built-in network widget.
function icon(data) {
  if (!data || data.type !== "wifi" || !data.powered || !data.associated) return "󰤮"
  return ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"][view(data).bars]
}

function connection(snapshot) {
  var mode = snapshot && snapshot.networkMode ? snapshot.networkMode : ""
  var wifi = mode === "bridged" && !!snapshot.bridgeInterface
    && snapshot.bridgeInterface === snapshot.interface
  return {mode: mode, bridgedWifi: wifi, showRadio: mode !== "bridged" || wifi}
}
