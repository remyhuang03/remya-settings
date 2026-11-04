# Power and energy saver

The resident Rust service owns `power.json` and `power.runtime.json` beside the
ordinary Settings configuration. Flutter, CLI and session D-Bus use the same
controller. No privileged helper or legacy PowerProfiles interface is used.

PowerProfiles is required at `org.freedesktop.UPower.PowerProfiles`, object
`/org/freedesktop/UPower/PowerProfiles`. Available profiles come from `Profiles`;
changes write `ActiveProfile` and verify fresh readback. UPower supplies aggregate
battery percentage, state and external-power status.

Screen and sleep timeouts edit only unambiguous listeners in
`$XDG_CONFIG_HOME/hypr/hypridle.conf`. Commands remain intact. Never comments out
the listener using `# remya-disabled: ` prefixes, which Settings can reverse.
Includes, duplicate targets and unsupported shapes are refused. The current-user
hypridle instance is restarted; failure restores the previous file and attempts
recovery. Other idle daemons are not supported.

Automatic energy saver defaults to off. Thresholds are 10, 20, 30, 50 and 100
percent (Always), with an independent include-external-power preference (default
false). A manual profile change suppresses automatic changes until eligibility
changes. The previous profile is restored when eligibility ends. These managed
changes are distinguished from external configuration conflicts.

Optional dimming affects built-in kernel backlights only, reducing the entry
brightness to 70 percent, with a minimum of 1 percent. Exit restores only a
backlight still at the automatic level. Runtime restoration state survives a
service restart. Physical brightness is live state, not configuration to restore
on every startup.

## Battery history

SQLite 3 through MIT-licensed rusqlite stores append-only observations permanently:
`$XDG_STATE_HOME/remya/settings/power.sqlite3`, defaulting to
`~/.local/state/remya/settings/power.sqlite3`. Debug uses the repository config
directory. WAL and SHM files belong beside the database. No automatic retention
limit is applied. Query ranges and page sizes bound memory use.

Every 60 seconds while awake the service records a real UPower observation or a
read error. Any active display lit means screen-on; all displays off means
screen-off; sleep is separate. Hyprland is checked each second. logind
PrepareForSleep records sleep/resume boundaries. Session boundaries, unknown
states and sampling interruptions remain explicit; gaps are never filled with
invented battery levels or sleep. Timestamps are UTC Unix seconds. A clock jump
creates a gap, and cursor order follows insertion IDs.

History queries return raw events plus preceding state/session/battery context for range clipping. The battery usage page shows the last 24 hours or 7 days with a theme-colored fl_chart line/area chart and observed-duration bars. Unobserved time is reported separately; gaps break the curve. Per-application battery usage remains planned. fl_chart uses the MIT license.

## Public operations

- `Get power` / `Get battery-saver`: saved/system values, supported profiles,
  conflict, backend error and history error.
- `Set power.5a4f0131`: JSON profile string.
- `Set power.5e3af39c` / `power.8b4c8522`: JSON seconds, 0 (Never) to 86400.
- `Set battery-saver.743773bd`: JSON manual saver boolean.
- `Set battery-saver.9b0caf70`: JSON threshold 0, 10, 20, 30, 50 or 100.
- `Set battery-saver.power-source`: JSON include-external-power boolean.
- `Set battery-saver.07945503`: JSON dimming boolean.
- `Resolve power system|settings`: reconcile real preferences explicitly.
- `Get battery-history:{"from":0,"to":1794000000,"after":0,"limit":1000}`:
  inclusive Unix timestamp range, insertion-ID cursor, maximum 1000 rows.
  Response has `observations` and `next` (last ID, null for an empty page).
- `Changed power`: state invalidation. Dart exposes `PowerClient` methods.

## Verification

`cargo test -p remya_settings_power -p remya_settings_service` covers storage,
policy predicates, safe timeout transformations and service dispatch.
`cargo run -p remya_settings_power --example probe -- <isolated-dir> <hypridle.conf>`
is read-only for host settings. Add `exercise` to switch profiles, exercise the
automatic include-AC policy and built-in dimming, restoring the starting profile.
This workstation passed that roundtrip on 2026-11-04, and the first SQLite sample
was read back at 96 percent with external power. The hypridle timeout/restart roundtrip also passed and restored the original file byte-for-byte. Real suspend/resume and actual
idle timeout expiry require separate desktop verification.
