# Network settings

Network & internet > Network status, Wi-Fi and Known networks manage connections through NetworkManager on the system D-Bus, from the ordinary-user Rust service in `lib/src/rust/network`. NetworkManager is required, in the current Arch Linux release. There is no other backend: when it is stopped or absent, the pages and interfaces report the error and show no sample values. Reads use `NO_AUTO_START`, so inspecting state never starts a stopped service.

## Pages

| Page | Controls |
| --- | --- |
| Network status | Internet status, active network name, live download and upload speed, type, IPv4, gateway, DNS, IPv6, link speed, hardware address, physical adapters, virtual adapters under Advanced. Sign-in opens NetworkManager's connectivity address with the desktop opener and appears only when NetworkManager reports a captive portal. |
| Wi-Fi | Radio switch, adapter choice with more than one Wi-Fi adapter, current network and disconnect, available networks merged per name and security, refresh. Scans run on page entry and every 30 seconds while the page is open. |
| Known networks | Add (including hidden networks), search, connect, connect automatically, metered, change password, forget. Active first, then most recently used. |

An adapter is physical when NetworkManager does not flag it as software and `/sys/class/net/<name>/device` exists; VMware adapters look like Ethernet otherwise. The Wi-Fi P2P companion and loopback are not adapters.

`known-networks.mac` (Random hardware address) stays `planned`: NetworkManager's `iwd` backend does not read the per-profile `cloned-mac-address` in its device code, and `iwd` randomizes from its own global `AddressRandomization`. `data-usage` stays `planned`: NetworkManager has no per-application accounting or traffic limits.

`known-networks.priority` (Connection priority) stays `planned`: with `wifi.backend=iwd` and the default `wifi.iwd.autoconnect=true`, the NetworkManager manual states that `autoconnect-priority` is ignored and `iwd` chooses the network. Saved priorities are neither read nor changed.

`iwd` also drops WEP networks. The manual marks this backend experimental; it has not been run with Settings.

Speeds are derived from `/sys/class/net/<adapter>/statistics` of the adapter behind NetworkManager's primary connection, polled once a second only while the page is open. VPN or container traffic carried by that adapter counts toward it.

## Network types

| Type | Behavior |
| --- | --- |
| Open, Enhanced Open (OWE) | Connects without a password. |
| WPA, WPA2, WPA2/WPA3 Personal | `wpa-psk` with an 8 to 63 character password or 64 hexadecimal digits. |
| WPA3 Personal | `sae` with the same password limits. |
| Enterprise (802.1X) | Listed. An existing profile can connect and keeps its preferences editable; a new one cannot be created here, because safe setup needs an EAP method, identity and CA verification. Missing credentials are reported; use `nm-connection-editor` or `nmcli --ask`. |
| WEP | Listed and marked insecure. An existing profile can connect; a new one cannot be created. |

## Connecting and secrets

A new network is added with `persist=memory`, and saved to disk only once it is activated, so a wrong password leaves no broken profile. Activation returns immediately; the result arrives through NetworkManager's signals and `Changed("network", state)`. A failure with reason `no-secrets` or `supplicant-disconnect` offers a password retry.

Passwords are only written to NetworkManager. They are never read back, returned, logged, emitted in `Changed`, or stored in `network.toml`. Their parser errors do not echo the request. Settings has no secret agent: a profile whose password is agent-owned or asked for each time fails with missing secrets, and entering a password stores it in NetworkManager with `psk-flags=0`. The dialog states this. The CLI reads values on stdin with `-`, which keeps passwords out of the process list. Session D-Bus requests remain visible to processes of the same user.

Profile changes read the settings, change one field and send them back through `Update`; NetworkManager keeps stored secrets when none are sent (verified on NetworkManager 1.58).

## Permissions

The service calls `GetPermissions`. A `no` disables the control with its reason and rejects the operation; `auth` lets polkit ask when the write is made. Only writes allow interactive authorization, so reads and Bar activation never prompt. An `auth` prompt holds the service's request queue until it is answered or times out after 120 seconds.

## Reconciliation

`network.toml` beside the service configuration holds version 1 and, per profile UUID, `autoconnect` and `metered`. First use snapshots the system without writing to it; a failed read leaves it uninitialized. An invalid file is kept and blocks preference changes.

A differing preference on a profile present on both sides is a conflict, with Use system configuration and Apply saved Settings. Preference changes are refused until it is resolved; connecting is not. The radio state and profile additions or removals are not compared: other tools change the radio routinely, and a saved entry cannot recreate a deleted profile without its secrets.

## Interfaces

See [public API](public-api.md#network).

## Verification

- `cargo test -p remya_settings_network` uses a fake backend for initialization, both resolutions, failure retention, trial profiles, password validation, adapters and permissions.
- `python test/network_smoke.py [debug|release]` runs the service on private session and system buses against a stub NetworkManager, including the radio, connecting, wrong passwords, conflicts, a stopped daemon, and the absence of passwords from every emitted message.
- `test/service_controllers_test.dart` covers failed-write retention and unresolved conflicts in the GUI controller.
- On a real NetworkManager 1.58, a disposable `autoconnect=no` profile was added, changed, re-keyed, put in conflict, resolved and forgotten without activating it, and real state and scans were read.
- **Not tested on a real connection:** turning the radio off, connecting, disconnecting and switching networks, because the workstation's only link is Wi-Fi. These are marked implemented by the owner's explicit decision, with stub verification only. Captive-portal sign-in, more than one Wi-Fi adapter and the `iwd` backend have also not been run on real hardware.

## Airplane mode

The Airplane mode page uses the ordinary-user Rust service to set NetworkManager
`WirelessEnabled` and `WwanEnabled`, and every BlueZ `Adapter1.Powered`. On disables
all these radios; Off enables all of them, including radios previously off.
Ethernet is unaffected. Wi-Fi also has an independent switch.
No connection profiles or pairing keys are removed.

Airplane mode is derived from fresh live radio readback, including external
changes; there is no saved airplane preference, startup write or reconciliation
conflict. This is a live-state exclusion. A running BlueZ with no adapters is a
valid empty inventory; an unavailable NetworkManager or BlueZ prevents changes.
Hardware blocks, denied authorization, busy Bluetooth operations, partial writes
and mismatched readback are errors. Every radio shutdown is attempted even when
another fails; successful shutdowns are never rolled back. Refresh displays the
actual state so a failed operation never implies that all radios are off.

The GUI polls while this page is open. CLI/D-Bus use the same controller and
verified writes. Verification: network airplane unit tests, `test/airplane_test.dart`
and private system/session-bus `test/airplane_smoke.py`; no real radios are changed
by these automated checks.

Upstream contracts: [NetworkManager radio properties](https://networkmanager.pages.freedesktop.org/NetworkManager/NetworkManager/gdbus-org.freedesktop.NetworkManager.html)
and [BlueZ adapter power](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Adapter.rst).
