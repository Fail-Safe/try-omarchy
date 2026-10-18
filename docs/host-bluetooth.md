# Mac Bluetooth

Try Omarchy shows the Mac's paired Bluetooth devices in the Omarchy bar. It
replaces the built-in guest Bluetooth widget through Omarchy's plugin clone
API, preserving the existing bar position and stable `omarchy.bluetooth` IPC
target. A one-time receipt respects later removal by the user. Upstream files
are untouched, and setup saves the previous shell configuration.

The existing supervised `dev.tryomarchy.hostnet` channel carries Wi-Fi and
Bluetooth snapshots. Bluetooth work has a separate queue so an unavailable
device cannot stall Wi-Fi heartbeats. The guest writes session-only state to
`$XDG_RUNTIME_DIR/try-omarchy-hostnet/bluetooth.json` and clears stale state.

The panel scrolls within the available screen height and keeps keyboard-selected
rows visible. It shows radio/permission status and paired devices, with connect and
disconnect controls, explicit pending/error feedback, and an action to open
Mac Bluetooth Settings. Apple controls pairing and radio power in that settings
pane. This does not expose a Linux Bluetooth controller or implement arbitrary
BLE access. Bluetooth audio continues through the existing Mac audio bridge.
Device connection results are followed by fresh observed state; submitting a
request alone does not establish that the device connected.

The signed app includes a Bluetooth usage description. Reading initial status
does not request access. Refreshing from the panel can request permission on
the Mac. Denial is visible in the panel and does not prevent Wi-Fi or VM startup.
There is no blueutil, Homebrew, HTTP server, credential, or separate daemon.

## Protocol and controls

The guest advertises `services=["wifi","bluetooth"]` in its refresh request.
Older guests receive Wi-Fi only; newer guests still accept Wi-Fi-only hosts.
Snapshots use `type=bluetooth`, with `authorization`, `powered`, and `devices`.
Each device has `id` (Bluetooth address), `name`, `connected`, and `kind`.
Only paired devices are exposed. Names render as plain text.

Requests use `type=bluetooth-action`, a UUID `id`, and an allowlisted `action`:
`refresh`, `connect`, `disconnect`, or `settings`. Connect/disconnect also require
a validated `device` address that the host rechecks against its current paired
list. Power, pairing, forgetting, arbitrary URLs and shell commands are rejected.
The fixed settings action opens the Mac Bluetooth pane.

Responses use `type=bluetooth-result`, the matching UUID, `ok`, and `message`.
The guest accepts one in-flight request through a mode-0600 session Unix socket;
the host also limits work to one action at a time. Requests and responses are
bounded and time out. `omarchy-host-bluetooth` provides status and these same
allowlisted actions for diagnostics. Its exit status reflects request success;
read subsequent status to establish the final connection state.

The `try-omarchy` package presets `omarchy-host-bluetooth-bar.service` at graphical
session startup. The same app launcher owns the combined Wi-Fi/Bluetooth bridge.
