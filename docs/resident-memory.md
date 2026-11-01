# Resident Settings memory verification

Measured on this workstation on 2026-10-31, using Linux `/proc/<pid>/smaps_rollup`
PSS in KiB. PSS accounts for shared pages proportionally; these are measurements,
not promises for other machines or future features.

The installed build completed actual startup authorization, Sync now, and LC_TIME
writes. Closing and reopening the GUI twice retained the same privileged PID
(`237407`) and did not request another authorization. The GUI process exited after
Close; the two resident processes remained available through CLI/D-Bus.

| Resident process after GUI close | PSS |
| --- | ---: |
| Ordinary-user Rust service | 8218 KiB |
| Privileged Rust service | 1308 KiB |
| Total | 9526 KiB (9.30 MiB) |

An isolated three-cycle regression test additionally checks that GUI engine memory
is released each time, that the daemon still responds after each close, and that
resident growth stays below 5 MiB. Results are written to
`build/resident-memory.json`. The installed-process samples are in
`build/final-installed-resident-memory.json`; they contain no credentials.

The native executable's runtime dependency inspection contains GLib/GIO and their
system dependencies, with no GTK or Flutter engine. A separately exercised
privileged process rejected a non-whitelisted command and exited on pipe EOF.
No system reboot was performed during verification.

## Background feature (2026-11-02)

Scanning every process's command line and environment raised the service to about
100 MiB PSS, so scans now read names first and details only for matching processes.
Measured with the same PSS method after that change: about 13 MiB during 30-second
reconciliation and after font and configuration reads, in an isolated session.

The GUI now prefers Mesa when a non-NVIDIA GPU exists, unless the user set
`__EGL_VENDOR_LIBRARY_FILENAMES`. Session-wide `__GLX_VENDOR_LIBRARY_NAME` and
`__NV_PRIME_RENDER_OFFLOAD` are replaced for the GUI, because they kept NVIDIA loaded. In a nested session the About page went from 437 MiB RSS and
152 MiB PSS to 306 MiB RSS and 108 MiB PSS, with no NVIDIA libraries mapped.
