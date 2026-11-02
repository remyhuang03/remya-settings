# Bluetooth

Bluetooth & devices > Bluetooth uses the ordinary-user Rust service and BlueZ on
the system D-Bus. BlueZ is the required backend; there is no CLI-output parser or
alternate backend. Existing GIO dependencies provide transport, so no new external
dependency or third-party source is bundled. Reads never activate bluetoothd.

## Device management

The page reads adapters, bonded devices and connection state through ObjectManager,
Adapter1 and Device1. Battery percentage appears only when the non-experimental
Battery1 percentage exists. Cached devices are not claimed to be nearby or online.
Multiple adapters have a session-local chooser; object paths are transient operation
targets, not persistent identities. Refresh always revalidates adapter membership.

Power applies immediately. Linux rfkill sysfs supplies hardware/software blocking diagnostics when available; a hardware block disables the switch. Adding a device scans for 60 seconds and supports PIN,
passkey, numeric comparison and keyboard display prompts. No confirmation request
is automatically approved. A successful pair attempts a profile connection; a failed
connection preserves the bond and reports the failure. Pairing expires after 120
seconds. Remove requires GUI confirmation and deletes BlueZ bonding information;
CLI/D-Bus writes are already explicit requests and need no second confirmation.
Trust, blocking, names, file transfer and audio profile management are not changed.

Advanced offers a temporary discoverable scan, using the client's discovery filter.
It does not edit global timeout or Pairable preferences. Incoming pairing remains
with the system's default agent. Settings registers only its own KeyboardDisplay
agent and never requests default-agent status. Agent callbacks must originate from
the current unique BlueZ owner and match the active target device.

GUI disposal and service-observed GUI exit cancel pending pairing and release only
Settings' own scans. Other applications' discovery sessions are preserved. BlueZ
restart or hot-unplug invalidates the operation without retrying a write.
The dedicated GLib context handles Agent calls while pairing is pending; the
service's global mutex is not held waiting for a PIN or radio operation.

## State ownership

No `bluetooth.toml` is created. Power, discovery, connection and the bond inventory
are live system state, like the Wi-Fi radio and NetworkManager profile inventory.
First use and subsequent reads adopt actual state without writing defaults. BlueZ
retains keys; Settings neither reads nor exports them. No stored target is restored
on startup, and no stable user preference is introduced for reconciliation.

The Airplane mode page links to Bluetooth; its remaining previews do not control
Bluetooth or imply that global airplane mode is implemented.

## Verification

- `test/bluetooth_test.dart`: page states, pairing dialogs, explicit confirmation,
  code validation, optional battery, removal confirmation, error recovery, narrow
  layout and the Airplane mode link.
- `cargo test -p remya_settings_bluetooth`: state parsing and input redaction.
- `python test/bluetooth_smoke.py [debug|release]`: private system and session buses,
  real service transport, target checks, every Agent prompt, rejection, incorrect
  PIN, callback sender checks, cancellation, hotplug, daemon restart, readback and
  operation failures. `--timers` also waits for the real scan/pair deadlines.
- Hardware validation is deliberately limited to reads and scans. Real pairing,
  power changes, connection/disconnection and removal are not tested, to preserve
  this workstation's paired keyboard, mouse and other devices. Implemented status
  for these operations relies on isolated verification, as explicitly agreed.

Upstream contracts: [Adapter1](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Adapter.rst),
[Device1](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Device.rst),
[Agent1](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Agent.rst),
[AgentManager1](https://github.com/bluez/bluez/blob/master/doc/org.bluez.AgentManager.rst).
