# System updates — paused work in progress

The user paused this implementation before upgrade execution was verified. The page and all eight update controls are `planned`. Production state reports `available: false`, `work_in_progress: true` and the same incomplete/unverified reason as the catalog. The GUI shows a Work in progress notice and disables checks, installation, session options and schedule edits. CLI/D-Bus `Set` rejects every update control with `Unavailable`. Automatic ticks and job starts are gated off, including when an existing saved schedule has `enabled: true`.

Existing source code, saved `updates.json`, candidates, status and bounded selectable monospace output are retained. `Get("updates")` and per-setting inspection remain available. The gate does not erase or rewrite an old schedule, and reading state cannot start checks, upgrades or authorization. Active hours remains a separate planned preview page with no effect.

Observed unfinished boundaries:

- An actual user-triggered update failed with `Update directory is not private and owned by its user`. `tempfile` temporary directories default to permissions derived from 0777, so the random job could be 0755 under the ordinary umask. Job and privileged staging creation now explicitly request 0700; a regression checks a real production scratch directory against the same authorization directory boundary and still rejects 0755.
- A later actual attempt failed with ` -> invalid option 'nosudoloop'`. The user paused the task; the flag/invocation was not redesigned or repaired afterward.
- GUI authorization lacked an explicit retry entry point after cancellation/failure. Direct private `--gui` inspection also bypasses the normal public Open authorization path. That UX remains unfinished.
- No successful workstation upgrade, AUR build/install, package conflict handling or privileged pacman transaction has been verified. Fake-backend tests, metadata-only package queries and prior isolated read-only checks do not prove that upgrade flow works.

The retained draft uses `checkupdates` with an isolated database, `yay -Qua`, ordinary-user yay jobs, a typed private authorization bridge, held-package policy, retry/log handling and an app-owned local daily schedule. These are incomplete implementation details behind the production gate, not available features. Existing tests preserve the draft boundaries; WIP tests verify that all production writes are rejected and an enabled saved schedule stays untouched and never runs.
