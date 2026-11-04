# System updates

System > System updates checks repository and AUR packages, upgrades repository packages with pacman, and runs an optional daily update from the resident Settings service.

## How it works

- **Check** runs as the ordinary user: `checkupdates --nocolor` (its own temporary sync database, so the system database is untouched) and `yay -Qua --color never` when `/usr/bin/yay` exists. Without yay the check still succeeds and the AUR list is hidden.
- **Update now** runs `pkexec /usr/local/libexec/remya-settings-update upgrade [--include-held]`. The root-owned updater accepts only those two command lines, computes holds as root, and `exec`s `systemd-run --wait --pipe --unit=remya-settings-update -- /usr/bin/pacman -Syu --noconfirm --color never --config /etc/pacman.conf [--ignore …]`. pacman runs in its own system unit, so logging out, stopping the Settings service or losing its output pipe cannot interrupt a transaction. The fixed unit name allows only one upgrade at a time.
- **AUR packages are never installed by Settings.** They appear in their own list for information; update them with yay in a terminal.
- **Holds** match the `up` fish function: kernel, headers, firmware and mkinitcpio packages, plus every installed `*nvidia*` package while an NVIDIA driver is loaded. **Include held packages** removes all holds for manual updates in the current service session. Automatic updates always keep the holds.
- **Retry after failure** retries a failed upgrade after 5 seconds per attempt, up to 60 seconds. Turning it off stops further attempts; a running transaction always finishes. A refused authorization (pkexec exit 126/127) is never retried.
- Output from checks and upgrades streams into a bounded, selectable log (512 lines, 128 KiB; ANSI and carriage-return progress handled).

## One-time system setup

The root updater and its polkit rule are installed separately from the user bundle:

```bash
sudo python tool/install_system_updater.py
```

It copies the release bundle's `libexec/remya-settings-update` to `/usr/local/libexec/remya-settings-update` (root:root, 0755) and writes `/etc/polkit-1/rules.d/50-top.remya.settings.update.rules` (0644). The rule returns `YES` only when `subject.user` is the invoking `SUDO_USER`, the program is that exact path, and the command line is exactly `… upgrade` or `… upgrade --include-held`. It matches the user rather than an active session because the login-started service is a systemd user unit, which has no logind session. Both files are written atomically. An existing rule without the installer's marker is never replaced.

Until this is done, the page reports the updater as `missing` and shows the command. Checks still work; installing and automatic runs do not. The service compares `remya-settings-update version` with its own `UPDATER_VERSION`; after a change to the updater, the page reports `outdated` until the command is run again.

Remove the system part with:

```bash
sudo rm /usr/local/libexec/remya-settings-update /etc/polkit-1/rules.d/50-top.remya.settings.update.rules
```

Security boundary: any process running as that user can start the fixed repository upgrade without a password. It cannot pass packages, options, configuration paths or other commands.

## Automatic updates and active hours

`tool/install.py` installs and enables the `top.remya.settings.service` systemd user unit (`WantedBy=graphical-session.target`), so the service starts with the graphical session. D-Bus activation goes through the same unit.

**Active hours** (System updates > Active hours; default 08:00 to 23:00, local time) mark when the computer is in use. They may cross midnight; start and end must differ. When **Automatic updates** is on (off by default):

- the update runs once per inactive period, at the first service tick after active hours end;
- if a whole inactive period was missed (computer off or service not running), the missed update runs at the next tick, even during active hours, and its notice says so;
- turning automatic updates on, or editing active hours, during active hours does not count as a missed period, so nothing starts until active hours end;
- a period that comes due while another operation is busy waits for it;
- each run checks first and starts pacman only when an unheld repository update exists; if the updater is missing, the period is recorded with a notice instead.

`updates.json` beside `config.toml` stores `version` (2), `enabled`, `active_start`, `active_end`, `last_run_day` (local date on which the last handled inactive period began) and `notice`, written atomically. A malformed or obsolete file blocks schedule edits and runs until it is removed or fixed; it is never rewritten. These are app-owned preferences with no system counterpart, so they are not reconciled.

## Requirements

`pacman`, `pacman-contrib` (`checkupdates`), `polkit` (`pkexec`) and systemd (`systemd-run`). `yay` is optional and used only to list AUR updates.

## Verification boundaries

See `docs/settings-implementation-progress.md` for recorded evidence. Verified on 2026-11-04 with the installed build: a real check, and a real held-respecting `pacman -Syu` through pkexec and systemd-run that ignored all 26 held packages and had nothing else to install. Untested: an upgrade that actually installs packages, logging out during a transaction, retry after a real mirror failure, and the polkit rule in isolation (this workstation already allows pkexec without a password through another rule).
