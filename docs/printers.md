# Printers

Devices › Printers manages CUPS print queues with the CUPS command-line tools,
run by the Rust crate `lib/src/rust/printers/` in the C locale behind a `Cups`
trait (faked in its unit tests). Interface details are in
[public API](public-api.md#printers).

- Each printer card shows its description, queue name, location, state as text and
  icon, the CUPS state message, the per-user default, and its waiting jobs.
- Actions: set as default (per user, `~/.cups/lpoptions`, no administrator rights),
  print the CUPS test page, pause or resume, cancel a job, and remove a queue after
  confirmation.
- Printers are live CUPS state and are not saved or reconciled: queues come and go
  with USB and network devices, and Settings cannot recreate a removed queue.
- The page polls every three seconds while it is open; a rejected action stays
  visible until the next action.

Not implemented: adding printers (needs device discovery and drivers; CUPS creates
queues for driverless IPP printers itself), printing preferences, sharing, and job
titles (`lpstat -o` does not report them).

Verification on 2026-11-12, with a USB HP Smart Tank 510 and CUPS 2.4.20: the real
`lpstat` output parsed as above; `printers.default` wrote `~/.cups/lpoptions` and
read back through `lpstat -d` (the file did not exist before and was removed again);
`printers.pause` paused and resumed the printer without a password for a user in
`sys` and `wheel`, reading back `stopped` with reason `Paused`, then `idle`. Test
page, job cancelling and removal were exercised only against the fake.
