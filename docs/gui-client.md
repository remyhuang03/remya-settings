# Settings GUI client

Settings depends on the sibling `../remya-core` checkout through path dependencies
`remya_client` and `remya_ui`. Core owns the daemon, CLI, D-Bus contract, system
configuration and shared theme; see Core's [public API](../../remya-core/docs/public-api.md),
[XDG layout](../../remya-core/docs/xdg-layout.md) and
[preferences](../../remya-core/docs/app-preferences.md).

There is no local catalog snapshot or configuration writer. Navigation loads
`Get("catalog")`; page payloads load lazily through `Get("page:<id>")` and are
cached for the session. Changed signals invalidate opened pages. `reload()` calls
Core Reload before refreshing them. Opening a system preference page calls its
supported Manage feature(s) once per page per session; a failed attempt remains
retryable. Search uses Core Search and exposes both system and app results.
Failed reads retain the previous valid page or preference values.

Camera frames alone stay in process. `camera_preview` depends on Core's camera
crate through a normal Cargo path dependency with its opt-in, plain Rust
`preview` feature. Core owns capture and validation; Settings owns `api.rs`,
the frame transfer type and generated FRB 2.13.0 bindings. No Core source files
are included directly and Core exports no FRB symbols.
Regenerate with `flutter_rust_bridge_codegen generate --config-file
flutter_rust_bridge.camera.yaml`, then `fvm dart format lib/src/rust/camera_bridge`.
Rust notices cover the wrapper's complete linked dependency graph, including
Core dependencies.

The runner opens the GUI with no arguments, a page argument, or `--gui <page>` /
`--settings <page>`. Core Open uses `--gui <page>`. The desktop settings action
uses `--settings`; there is no service or CLI dispatch in this executable.
The installer requires Core's activation file in an absolute XDG data root and
writes only the GUI bundle, command, desktop entries and icon. It refuses to
replace a running bundle and does not stop or install services.

Validation: `fvm flutter analyze`, `fvm flutter test`, `cargo fmt --all --check`,
`cargo build`, `cargo clippy --all-targets -- -D warnings`, `cargo test`,
`python -m unittest discover -s test -p '*_test.py'`, and
`fvm flutter build linux --release`. Component tests consume Core's authoritative
catalog as input rather than maintaining a duplicate snapshot. Catalog loader
regressions use minimal in-memory responses and never contact the live daemon.
