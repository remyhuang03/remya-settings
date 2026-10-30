# Remya Settings client

Public integration boundary for independently built Remya applications. The
Settings application owns this package and is the only configuration/system
writer. See [the complete API contract](../../docs/public-api.md).

- `settings_contract.dart`: pure Dart D-Bus client, versioned theme configuration,
  settings opener, and XDG path resolution. The standalone CLI uses this entrypoint.
- `remya_settings_client.dart`: the same contract plus shared Material 3 Expressive
  theme construction and the observable theme controller for Flutter clients.

Use `SettingsClient.call` for application operations and `watch` for an initial
snapshot followed by updates. Use `SettingsThemeController.service()` for a
release Flutter application and dispose the controller when its application view
is released. Repository-based theme overrides are read-only debug helpers.

Do not add Settings pages, its system backend, private controllers, or native FFI
to this package. Add new contracts beside their owning feature and extend the
common operation dispatcher and parity tests in the Settings application. Pin a
version/tag before releasing clients independently; interface-incompatible changes
need a new D-Bus version.

Licensed under PolyForm Noncommercial License 1.0.0; see LICENSE. The `dbus`
dependency uses MPL-2.0 and is used unmodified; preserve its notices. Its
[source release](https://pub.dev/packages/dbus/versions/0.8.0) is publicly available. Flutter's license registry includes its Dart dependency notice.
