# Storage and Cleanup

Storage combines space usage with disks and volumes so measurements and the devices they describe stay together. Cleanup combines recommendations with automatic cleanup so users can review the same deletion policy before scheduling it. The four former storage pages are now two pages. Windows reference URIs remain attached to the page owning the corresponding behavior.

## Measurements

The cloneable Rust `Storage` handle owns worker threads. First Get of Storage or Cleanup starts a scan; service startup never scans HOME. Scan again does not restart an active scan. The service publishes `Changed` for `storage` and `cleanup` from its one-second poll, with scan progress throttled to once a second. Cleanup and scans never hold the service State mutex. Background reads use a separate coalesced refresh flag and do not set busy or disable user actions.

jwalk traverses hidden and ordinary HOME entries without following symlinks and prunes foreign filesystems before descending. Allocated blocks (`st_blocks * 512`) count toward categories; hard-linked files count once by device/inode. The most specific XDG user directory owns an entry. Unset directories and directories equal to HOME are omitted. Cache and Trash are distinguished from other home files. Cache children and the 30 largest regular files with at least 100 MB of allocated blocks outside cache/trash are gathered during the walk. Large-file sizes and the threshold use allocated blocks, not apparent lengths. Files under any hidden directory relative to HOME are excluded from suggestions but still count toward usage categories. Category paths are absolute and normalized without trailing separators. An XDG cache outside HOME or on another filesystem needs a separate cache-only pass; it never increases HOME volume categories. User directories outside HOME remain folder links with no bytes attributed by the HOME scan. Non-UTF-8 entries cannot be represented in the JSON API and are counted as skipped.

statvfs reports volume total, used and space available to the user. The residual after subtracting scanned home blocks is System and other files, or Other files on this volume when HOME has a different device from `/`. This includes other users' files, inaccessible entries, filesystem metadata and system files; it is not an installed-package size measurement. The row opens Installed apps. Reserved filesystem blocks can make used plus user-available free less than total. btrfs compression, reflinks and snapshots prevent allocated-block sums from being an exact measure of exclusive reclaimable space. Unreadable entries are skipped and counted. Reads and estimates are snapshots; files and mounts can change during them.

The usage hero labels the system drive and its mount/device explicitly. Its legend is sorted largest first, omits categories below 1 MiB, and uses two columns at content widths of at least 600 pixels. Storage and Cleanup share a harmonized categorical palette with brightness-appropriate tones and text labels. Cleanup omits zero-byte legend entries and displays recommendation errors with an icon and text instead of a zero size.

## Devices

The ordinary-user backend uses UDisks2 GetManagedObjects on the system bus. Only object paths in a fresh response can be acted on. LUKS cleartext filesystems use backing partition geometry; Settings does not unlock or format volumes. Ignored devices, zram and empty loop devices are omitted. Filesystems mounted on system paths, swap and HOME's filesystem cannot be unmounted or ejected. Mount and unmount use UDisks2 defaults and polkit interaction; rename validates a 255-byte label without slashes or control characters. The backend reads back labels and mount state after writes. Eject and power-off first unmount the drive's non-system filesystems. Ignored system blocks still protect their physical drive; another hidden mounted volume also prevents ejection. Operations can fail when a device is busy or authorization is denied. The filesystem methods follow the [UDisks2 Filesystem API](https://storaged.org/doc/udisks2-api/latest/gdbus-org.freedesktop.UDisks2.Filesystem.html). Open accepts only reported category paths, current mount points or reported large-file parent folders.

## Manual cleanup

- Trash: the trash crate lists FreeDesktop trash, including per-mount trash. Unreadable item metadata is skipped and counted as `broken`, without contributing to `items` or `bytes`. Only a list failure makes the component unavailable. Empty permanently purges only readable listed entries.
- Cached files: select reported direct cache children; names cannot contain slashes or be `.`/`..`. Removal is permanent and does not follow symlinks. Close the corresponding apps first; they rebuild caches.
- Package cache: paccache dry runs estimate savings for keeping 1, 2 or 3 versions and uninstalled versions. Missing pacman-contrib is reported as an unsupported host capability. Savings overlap between selections and are estimates.
- Unused packages: pacman `-Qdtq` and `-Qi` report orphan names, versions and installed sizes.
- Large files: selected, still-regular files inside HOME move to Trash. This does not immediately free space on that volume.

The confirmation lists permanent removal separately from moves to Trash. Cleanups may partially complete before a later failure; the error remains visible. Free-space changes can include concurrent activity by other processes.

Package cache and orphan removal use the existing authorized private helper, never the system updater. The root side validates keep count 1..3, at most 500 packages, package-name characters, current orphan membership and exact version. It refuses a locked pacman database. Its only write commands are `/usr/bin/paccache -r -k <keep>`, optionally `/usr/bin/paccache -r -u -k 0`, and `/usr/bin/pacman -R --noconfirm -- <names>`. The service refuses cleanup during system updates. Without an authorized session, users must first open Settings and authorize system changes. Frames are bounded to 64 KiB in both directions.

## Automatic cleanup

`cleanup.toml`, next to the main configuration, is an app-owned preference with no system reconciliation. Strict version-1 parsing rejects unknown fields and invalid values; invalid files remain untouched and policy controls become read-only. Writes are atomic. Defaults are off, low-space frequency, Trash 30 days, cache 30 days and Downloads Never.

The resident service checks every 60 seconds: daily is 24 hours, weekly 7 days, monthly 30 days since the last run; low-space requires less than 10 percent available on HOME's volume and at least 24 hours since the last run. Run now also works while automatic cleanup is off and uses the saved ages. Zero days means Never.

Old Trash entries are permanently purged according to their deletion date. Cache regular files are permanently deleted only when both access and modification times are older than the chosen age. Old regular Downloads files move to Trash. Symlinks are not followed; errors are counted and recorded with run time and freed bytes. Downloads moved to Trash do not count as freed bytes. Automatic runs never remove packages or package caches.

## Verification boundaries

Rust tests use temporary trees and fake D-Bus, process and Trash boundaries. Widget tests use fake state. `storage_checks()` runs inside the normal installed `test/interface_smoke.py` flow, using that suite's isolated HOME/XDG and session bus. Storage checks exercise read-only state and automatic preference writes and reject unreported paths; they never mount devices, clean files, or authorize root. The surrounding suite handles installation.

Destructive UDisks2 operations, real per-mount Trash, interactive polkit and privileged pacman/paccache execution require separate hardware review. No real user caches, Trash, configuration, devices or package database were changed during implementation verification. Installed application behavior has not been tested; installation is explicitly excluded for this task.


Polish validation on this worktree uses `TMPDIR=/tmp` for Rust and Flutter tests. The inherited TMPDIR points to fuseblk, where permission preservation tests fail and allocated-block fixtures cannot use fallocate. Native temporary storage preserves the required filesystem semantics.

Implementation validation on this worktree:

| Check | Result |
| --- | --- |
| Rust storage unit tests | 23 passed, using temporary trees and fakes |
| Rust Startup and service unit tests | 14 Startup and 8 service tests passed |
| Storage and Startup Clippy with warnings denied | Passed |
| Workspace Clippy with warnings denied | Blocked by 8 existing `collapsible_if` diagnostics in power; service additionally has an existing `items_after_test_module` diagnostic |
| Flutter analysis | No issues |
| Flutter tests | 122 passed, including 18 Storage/Cleanup and Startup tests |
| Installed Storage interface smoke | Integrated into the normal full smoke flow; reserved for the architect after installation |
| Linux release bundle | Built successfully; not installed or launched |
| Rust dependency notices | Regenerated for 241 dependencies; new jwalk/trash and their Linux dependencies use MIT/Apache/BSD-compatible licenses |

The root updater, real package cleanups, mounts and real user Trash/cache were not exercised. Large files are intentionally excluded from the immediately reclaimable total until Trash is emptied, because moving them to Trash does not free space.
