# Windows Settings inspiration, reference, and UI coverage

Research date: 2026-10-26. Target product: a global settings application for **Hyprland on Linux**, with **Material Design 3 Expressive** styling.

Remy'a Settings draws design inspiration and comparative benchmarks from modern desktop settings patterns such as Windows 11 Settings, rather than directly copying or attempting 1:1 emulation. Because the application targets Linux and Hyprland, its categories, actual controls, workflows, and backend implementations have diverged significantly to fit native Linux services (PipeWire, NetworkManager, pacman/Flatpak/AppImage, Fontconfig, systemd-timedated) and Wayland compositor rules.

This document records the initial desktop reference catalog researched for baseline comparative analysis (188 pages and 1,251 controls); `advanced-display` later moved into a collapsed section of `display`, which also took over its `ms-settings:display-advanced` entry. The later additive Hyprland catalog extension is documented separately in [Hyprland research](hyprland-settings-research.md).

## Evidence and limits

Microsoft publishes a [Settings navigation guide](https://support.microsoft.com/en-us/windows/experience/exploring-windows-settings), a [page URI reference](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings), and a [Windows 11 backup settings catalog](https://learn.microsoft.com/en-us/windows/configuration/windows-backup/catalog?pivots=windows-11). These are complementary inventories, not a published internal schema for every Windows Settings control. Availability varies by OS release, edition, hardware, installed applications, organization policy, account, and staged feature rollout.

The retained coverage includes **96 URI entries** from the reference tables. Query parameters selecting individual apps, cameras, or audio endpoints belong to the same page; aliases are recorded on their target page. Remaining Windows-only entries are clearly unavailable reference previews. A URI that redirects to another view is not evidence of an independent current Windows 11 page.

The retained backup coverage contains **31 hierarchy entries**: 20 leaf entries that an ordinary control represents, 8 entries that identify their groups and 3 recorded removals. The collapsible "Windows reference settings" sections that listed the remaining Windows leaf entries under their original English names were removed; Windows-only backup items are not previewed. Backup checkmarks describe Windows backup coverage, not implementation status in this application.

There are **188 detail pages**, **1,251 reference controls**, **10 settings categories**, and a separate Home and About view. All controls are authored UI previews. Control types, ranges, sample values, grouping, and option lists are this project's initial model, not Microsoft's internal types, actual hardware capabilities, live defaults, or a guarantee of an exact match to every Windows build. In particular, source-only reference fields whose choices are not documented use an explicit "未配置" option. Future implementation must verify real platform contracts and replace illustrative ranges and choices before enabling them.

Supplemental reference material comes from [Advanced settings](https://learn.microsoft.com/en-us/windows/advanced-settings/), [app privacy guidance](https://support.microsoft.com/en-us/windows/privacy/windows-privacy-settings-that-apps-use), [passkey management](https://support.microsoft.com/en-gb/accounts-billing/security/manage-your-saved-passkeys), and [presence sensing](https://support.microsoft.com/en-gb/windows/privacy/managing-presence-sensing-settings-in-windows-11). The retained runtime catalog includes only the selected product scope; universal application permission switches without a concrete Linux enforcement boundary are excluded. Hyprland permission rules and desktop portals remain separate previews. Exact service-specific and undocumented vendor extension schemas are outside the public evidence; no exhaustive Windows-internal export is claimed.

## Information architecture

| Category | Main subjects | Hyprland direction |
| --- | --- | --- |
| System | Display, notifications, focus, power, storage, windows, sharing, remote access, clipboard, device information, developer tools | Future compositor and Linux service integrations |
| Sound | Output & input, Volume mixer and Devices | Native per-user PipeWire audio through libpulse; see [Sound](sound.md) |
| Bluetooth & devices | Pairing, printers, cameras, mouse, touchpad, touch, USB, phone and accessory devices | Future Linux device service integrations |
| Network & Internet | Status, Wi-Fi, Ethernet, VPN, hotspot, airplane mode, cellular, proxy, adapters, usage | Future network service integration |
| Appearance | Background (image or video), colors and themes (merged), lock screen, launcher, panel, fonts, lighting | Future Hyprland and desktop component configuration |
| Apps | Installed apps, defaults and startup | Future package and XDG application integration |
| Accounts | Identity, login, local users, backup, credentials and passkeys | Future Linux session and account integration |
| Time & language | Clock, synchronization, region, languages, speech and external input-method configuration tools | Future locale and input method integration |
| Accessibility | Text, visual effects, pointer, cursor, magnification, contrast, reader, audio, captions, voice, keyboard, mouse and eye control | Future compositor and assistive technology integration |
| Privacy & security | Security, encryption, search/indexing and compositor permissions | Future Linux security and portal integration |
| System updates | Status, history and update preferences | Future distribution-aware update integration |

Windows-branded services and legacy concepts are preserved purely as reference material and inspiration, not promises to implement those services on Linux. The settings architecture diverges intentionally: Linux-native capabilities replace proprietary subsystems, and desktop components are integrated natively.

## Layout translation

The shell draws inspiration from modern desktop settings patterns for category navigation, persistent search, Home shortcuts/cards, category lists, breadcrumbs, grouped controls, and deeper related pages, while adapting them to Linux and Hyprland workflows. The native window keeps normal compositor behavior. At wide sizes the left sidebar stays visible; below 1,000 logical pixels navigation moves into a drawer. Settings rows stack their label and control on narrow content widths. Content scrolls without requiring a fixed window size.

Material Design 3 Expressive supplies colors, rounded surfaces, emphasis, buttons, switches, sliders, menus, typography, focus, and interaction feedback. Fluent visual assets and Windows window chrome are not copied. Display, theme, sound, network, power, storage, devices, and update pages include purpose-specific preview regions rather than a single generic empty template.

Search matches category/page labels, descriptions, control names, and Windows reference URI names locally. Navigation, search, back, Advanced section expansion, About, and license viewing are functioning UI interactions. They do not invoke system operations.

## Schema and availability

- Runtime data: `assets/settings/catalog.json`.
- JSON Schema: `assets/settings/catalog.schema.json` (Draft 2020-12).
- Included reference coverage: `docs/windows-settings-coverage.json`.
- Runtime model: `lib/features/settings/domain/settings_catalog.dart`.
- Renderer: `lib/features/settings/presentation/`.

Each category, page, and control has a stable identity. Keep IDs unchanged when changing labels or order. Pages declare sources, URI aliases, child routes, preview kind, availability, reason, and control sections. Control kinds are toggle, choice, slider, action, info, text, and color. Disabled preview controls never retain changes or perform I/O. Supplemental sections declare `collapsed: true`.

Availability always has a readable label and an icon:

| Value | Label | Meaning |
| --- | --- | --- |
| `available` | 已实现 | A real integration has been implemented and verified |
| `planned` | 未实现 | Visible preview; system integration is absent |

No system setting is currently `available`. The renderer deliberately keeps operation controls disabled. Adding an integration requires real read/write bindings, error handling, validation and tests, then updating the control state and availability together. Changing a status string alone must never enable a simulated setting. About labels implemented navigation/license UI separately from system functionality.

Retained tests resolve recorded URI and backup references, reject malformed data and broken routes, check source and progress-document parity, and cover shared row layout. Local presentation checks were removed after verification.

## Application icon and About

The owner-provided `settings.svg` is copied unchanged to `assets/icons/settings.svg`. The adjacent 512-pixel PNG is rendered with Inkscape so SVG filters are preserved without a new runtime package:

```bash
inkscape assets/icons/settings.svg --export-type=png --export-filename=assets/icons/settings.png --export-width=512 --export-height=512
```

Flutter uses the PNG in navigation, Home, About, and license branding. The GTK runner loads the bundled PNG independently of the working directory. The desktop entry and scalable SVG are included in the build bundle for future packaging; nothing is installed into the user's desktop configuration. Wayland taskbar icon discovery depends on desktop entry installation by a future package.

About shows product purpose, package version, UI-only status, a selectable private repository address, third-party licenses, and the PolyForm Noncommercial License 1.0.0 selected by the owner. The icon's ownership/licensing is not inferred from its appearance or filename.
