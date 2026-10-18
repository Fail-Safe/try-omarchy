# Host Wi‑Fi

Try Omarchy mirrors the Mac's Wi‑Fi powered/associated state and signal into
the guest with no configuration. The launcher starts a host bridge
automatically; the guest agent writes the latest snapshot into the session
runtime directory for bar widgets and `omarchy-host-wifi`.

State flows one way, host to guest. The guest may only ask for a fresh
snapshot. Nothing it sends can change Mac Wi‑Fi association or power.

## Why this exists

The guest NIC (NAT or bridged) is not the Mac's Wi‑Fi radio. When Omarchy runs
as a VM, a normal Linux Wi‑Fi indicator cannot show the Mac's RSSI/SSID. This
bridge fills that gap so the bar shows Mac wireless health in Omarchy.

## Protocol

A dedicated virtio-serial port, `dev.tryomarchy.hostnet` (`nr=9`), carries
newline-delimited JSON. Wi‑Fi v1 uses one complete snapshot message:

```json
{"type":"wifi","powered":true,"associated":true,"ssid":"HomeNet",
 "rssiDbm":-55,"noiseDbm":-92,"snrDb":37,"txRateMbps":600.0,
 "channel":149,"channelWidthMhz":80,"band":"5g",
 "security":"wpa3-personal","interface":"en0","ssidUnavailable":false,
 "ipAddress":"192.0.2.10","bssid":"02:00:00:00:00:01","phyMode":"802.11ax"}
```

`ssid` may be `null` even when associated if macOS withholds the network name
without Location permission. In that case `ssidUnavailable` is `true` and the
UI should show a generic connected label. Signal fields remain useful without
SSID.

`macos/Sources/OmarchyVMHelper/NativeHostNetBridge.swift` builds snapshots from
CoreWLAN and sends a snapshot every five seconds and answers the guest's
`{"type":"refresh"}` request. Wi-Fi controls remain read-only.

The same port carries [Mac Bluetooth](host-bluetooth.md) snapshots and
allowlisted paired-device actions when the guest advertises Bluetooth support.
Older guests continue to receive Wi-Fi snapshots only. New message `type` values
can be added without renumbering the serial port.

## Guest contract

`omarchy-native-hostnet-bridge` is a user unit enabled for the graphical
session. On each accepted wifi snapshot it atomically writes:

```text
$XDG_RUNTIME_DIR/try-omarchy-hostnet/wifi.json
```

Helpers:

```sh
omarchy-host-wifi           # human line
omarchy-host-wifi --json    # raw snapshot
omarchy-host-wifi --waybar  # Waybar custom-module JSON
```

When the host bridge disconnects or stops sending snapshots for 15 seconds,
the state file is removed and the widget shows unavailable.

## Permissions

macOS may withhold the SSID unless Location access is granted. This bridge
does not request or require a grant. Withheld Location access does
not stop the VM and does not remove signal/associated state. The app Info.plist
includes `NSLocationWhenInUseUsageDescription` explaining the purpose.

## End-user UX

No start-menu toggle, token, SSH tunnel, or brew package. If the Try Omarchy
app is new enough to expose `dev.tryomarchy.hostnet`, Wi‑Fi status appears
after sign-in.

## Omarchy bar

The bundled `tryomarchy.host-wifi` Quickshell plugin reads the runtime file,
uses Omarchy’s Wi-Fi signal glyphs and standard `BarIconButton`, and provides a tooltip with the SSID (or "Connected")
and RSSI. Off, disconnected, and unavailable states have distinct tooltips.
Clicking the Wi-Fi icon opens a themed Omarchy panel with signal quality, link rate,
signal/noise/SNR, channel and width, radio mode, security, BSSID, and the Mac
Wi-Fi interface's IPv4 address. The address is taken from that interface, not
the default route or a VPN. "Link rate" is the radio transmit rate, not measured
internet throughput. Missing values are shown as `--`.

The panel keeps up to two minutes of timestamped five-second signal samples
while the shell service is running, including when the panel is closed. It
leaves gaps on disconnect and resets history when the visible connection
identity changes. It does not persist radio history across shell restarts.
The graph uses a fixed -90 to -30 dBm scale. Quality labels are RSSI estimates.

SSID text is treated as plain text. Missing signal is shown as unknown rather
than full strength.

The graphical-session setup registers the plugin before the normal network
widget once. It preserves other layout entries, saves the previous shell
configuration, and records completion under
`$XDG_STATE_HOME/try-omarchy/host-wifi-bar-enabled` (default
`~/.local/state/try-omarchy`). Removing the widget later is respected. The guest
network widget remains available for the VM's independent network settings.

## Installation and restart

Wi-Fi is included in the `try-omarchy` guest integration package. The Mac app
exposes hostnet on channel 9 and starts `--bridge-native-hostnet` under its
normal bridge supervisor on every launch. Timezone sync retains channel 8.

On a guest upgrade to `0.1.0-28`, the package enables the Wi-Fi bridge and bar
setup units for graphical sessions. Factory installs use the same presets.
The app offers the bundled integration package through its normal pre-login
update path; no standalone installer or factory rebuild is needed.

The user bridge runs `/usr/bin/omarchy-native-hostnet-bridge`; the bar plugin
is installed under `/usr/share/try-omarchy/host-wifi`. The udev rule uses
logind active-session access so it does not require membership in `users`.

The graph labels -90, -70, -50, and -30 dBm. Red marks weak signal below
-70 dBm, amber usable signal from -70 dBm, and green strong signal from
-55 dBm. These are approximate RSSI ranges, not measurements of packet loss
or connection stability. Numeric labels accompany the colors.

The optional `ipAddress`, `bssid`, and `phyMode` fields extend the v1 snapshot.
The decoder accepts older hosts without those fields. macOS can withhold
SSID and BSSID; neither is required for the panel to work. Bluetooth shares this port; see [Mac Bluetooth](host-bluetooth.md).

## VM connection presentation

The launcher includes `networkMode` (`nat` or `bridged`) and the selected
`bridgeInterface` in radio snapshots. The guest never guesses the host's
connection from its virtual Ethernet device. Older hosts without these fields
retain the separate network and Mac Wi-Fi panels.

NAT shows a Mac Wi-Fi indicator plus a **VM Network / NAT** panel with the
virtual connection's guest IP, gateway, traffic and DNS controls. Bridging via
the reported Mac Wi-Fi interface shows one Wi-Fi indicator and a combined
panel: the guest's bridged IP and traffic remain guest measurements, while
signal, noise, channel and history describe the Mac radio. Bridging through
another host interface hides the Mac Wi-Fi indicator and identifies that
interface in the network panel.

`omarchy-vm-network-setup` adapts the installed upstream network panel using
Omarchy's supported `clonedFrom` plugin mechanism. It leaves upstream files
untouched and retains the original guest controls. The adapter checks its
required integration points before publishing; an incompatible upstream panel
causes setup to fail visibly while the original remains available. Layout
changes use the normal plugin API, with a backup and a receipt so later user
removal is respected. The generated clone refreshes from the installed upstream
source at graphical-session setup.
