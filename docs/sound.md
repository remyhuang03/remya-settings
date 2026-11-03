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
services report an error; device state is never invented. Runtime changes and
30-second service reconciliation emit the existing `Changed("sound", state)`
signal; an open Sound page also refreshes its live inventory every two seconds.

[PulseAudio client API](https://www.freedesktop.org/software/pulseaudio/doxygen/)
and [libpulse-binding](https://docs.rs/libpulse-binding/2.30.1/libpulse_binding/)
are the primary API references. WirePlumber retains its normal routing policy.
A default-device change affects new streams according to that policy; existing
streams can be moved individually in Volume mixer. Audio format is a readout;
this feature does not change device profiles, ports, codecs or sample-rate policy.
Those controls remain planned in Advanced, alongside the compositor bell preview.
Windows-specific enhancements, spatial audio, device tests and permission controls
have been removed from these pages.

## Persistence and reconciliation

`sound.toml` beside the selected Settings configuration stores schema version 1,
stable default device names and per-device raw channel volumes/mute values. First
use reads actual state and atomically saves it without writing to the audio server.
Failed write warnings survive automatic inventory polling until an explicit refresh
or successful operation. Invalid configuration, failed detection and failed persistence are reported without
replacing the last valid saved state. Device indices are used only for current
inventory; persisted identities use the audio server's stable names.

Startup, page opening and refresh compare saved values with fresh device readback.
An external volume, mute or default-device change produces a warning with both
choices: use system configuration, or apply saved Settings. Ordinary persistent
writes are blocked during a conflict. Applying saved values verifies that saved
defaults are connected and channel layouts still match, then verifies actual
readback. A disconnected non-default device's preferences are retained for when
it reappears; new devices are read live and their preferences are saved when edited
or when system configuration is adopted. Reconciliation never reconnects devices.

Per-application streams are ephemeral. Volume, mute and routing identify a current
stream by direction, stream index and client index, revalidate before writing and
verify readback afterwards. They never modify `sound.toml` and remain usable during
a device-preference conflict. Ended/replaced streams and removed destinations
produce an error. Volume changes preserve existing channel balance and allow
0–150%; actual values outside that range remain visible in the readout. No audio
is played as a device test, and no microphone audio is captured by Settings.

## Verification

`cargo test -p remya_settings_sound` covers initialization without writes, both
conflict resolutions, channel balance, failed/mismatched readback, failed
persistence, ephemeral stream writes and stale stream identity. Flutter
`test/sound_test.dart` covers the pure Dart client contract, scoped output/input writes, reconciliation actions,
mixer behavior and error retention. Catalog tests cover the navigation, source
mapping and progress tracker.

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
validation, both conflict resolutions and Sound change notifications on private
session/system-bus and PipeWire state. It uses the compiled service and a Linux
bundle's generic CLI, then terminates all validation processes.
