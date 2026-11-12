# Sound

Sound is a top-level category with three pages: Output & input, Volume mixer and
Devices (`sound-volume`, `volume-mixer`, `sound-devices`). Output & input is the default page and groups the default playback and
recording devices, their actual volume, mute, sample rate, channel count and running
state. Devices lists the complete
server inventory, including virtual devices and output-monitor recording sources.
Default-device selection stays on Output & input; Devices keeps individual device
volume/mute controls without repeating the default-device chooser. The mixer shows live playback and recording streams, their volume/mute capabilities,
and device routing. Bluetooth discovery, pairing, profiles and codecs stay in
Bluetooth; connected Bluetooth audio devices appear in the audio inventory normally.

## Backend and dependencies

The ordinary-user Rust service calls the native PulseAudio client API through
`libpulse-binding` 2.30.1 (MIT/Apache-2.0), dynamically linked to system `libpulse`.
The target is current Arch Linux with PipeWire, pipewire-pulse and WirePlumber.
The binding uses PulseAudio 15+ APIs. There is no shell command backend, privileged
helper or system configuration file editor for audio. Each request uses a bounded
native connection, without autospawning a server. Missing or unresponsive audio
services report an error; device state is never invented. One blocking PulseAudio
subscription in the Settings service watches playback sinks and server defaults.
It combines nearby events into one read and publishes changed snapshots through
`Changed("sound", state)`. The existing 30-second service refresh and open Sound
page's two-second refresh also cover other inventory changes.

[PulseAudio client API](https://www.freedesktop.org/software/pulseaudio/doxygen/)
and [libpulse-binding](https://docs.rs/libpulse-binding/2.30.1/libpulse_binding/)
are the primary API references. WirePlumber retains its normal routing policy.
A default-device change affects new streams according to that policy; existing
streams can be moved individually in Volume mixer. Audio format is a readout;
this feature does not change device profiles, ports, codecs or sample-rate policy.
Those controls remain planned in Advanced, alongside the compositor bell preview.
Windows-specific enhancements, spatial audio, device tests and permission controls
have been removed from these pages.

## Live state and operations

All audio controls follow the audio server's live state, including device volume,
mute, default input/output devices and application routing. Settings does not
persist audio preferences, compare them with a saved configuration, or restore
old values. External changes and device additions/removals are reflected on the
next read without a configuration conflict. No sound configuration file is read
or created, and there is no Sound configuration-resolution operation.

Every operation reads current inventory before writing and verifies only the
requested field afterwards. Device volume writes do not change mute, and mute
writes do not change volume. Failed write warnings survive automatic inventory
polling until an explicit refresh or successful operation. Failed detection keeps
the last readout visible, reports an error and disables device controls.

Per-application volume, mute and routing identify a current stream by direction,
stream index and client index, revalidate before writing and verify readback
afterwards. Ended/replaced streams and removed destinations produce an error.
Volume changes preserve existing channel balance and allow 0–150%; actual values
outside that range remain visible in the readout. No audio is played as a device
test, and no microphone audio is captured by Settings.

## Verification

`cargo test -p remya_settings_sound` covers reads without writes, external
changes and inventory changes across restarts, channel balance, failed/mismatched
readback, field-scoped verification, stale stream identity and error retention.
Flutter `test/sound_test.dart` covers the pure Dart client contract, scoped
output/input writes, live control refresh, mixer behavior and error retention.
Catalog tests cover navigation, source mapping and the progress tracker.

`cargo test -p remya_settings_sound --test isolated_pulse -- --ignored` starts
private PipeWire and pipewire-pulse servers, a WirePlumber policy-only instance
(without hardware monitors), and two null sinks inside a temporary runtime.
It verifies real native device/default/mute/volume and application stream routing
writes without accessing workstation audio devices. It requires those system
programs plus `pactl` and `pacat` only as test fixtures. The native production
backend does not invoke them. The test kills every child and removes its temporary
configuration/state. Physical hardware, Bluetooth handover and audible playback
are separate manual boundaries.

`python test/sound_smoke.py debug` verifies actual CLI/D-Bus parity, input
validation, live external changes, restarts, removed resolution requests and Sound
change notifications on private session/system-bus and PipeWire state. It uses the compiled service and a Linux
bundle's generic CLI, then terminates all validation processes.
