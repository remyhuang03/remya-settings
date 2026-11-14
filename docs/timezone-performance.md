# Time-zone navigation performance

## Diagnosis

The Time & language sidebar category opens the Date & time page. Its closed DropdownMenu built all 598 system time-zone entries. The option data was already cached by ServiceDateTimeController, but rebuilding the page recreated the menu's widget tree. Keeping DropdownMenuEntry objects cached would not remove that work.

## Applied design

- Keep cached system time-zone IDs and labels in the owning controller.
- The closed control shows only the selected label.
- Open the searchable dialog on demand.
- Build visible options with ListView.builder in a bounded viewport. A prototype row supplies row geometry without laying out the whole list.
- Isolate search setState to the picker. Keep finite system option validation, current selection, keyboard operation, cancellation, and controller error handling.
- Do not keep the entire page/widget tree alive or add a new state-management dependency.

The implementation follows Flutter's [performance best practices](https://docs.flutter.dev/perf/best-practices), [on-demand list construction](https://api.flutter.dev/flutter/widgets/ListView-class.html), and the official [large settings-list example](https://flutter.dev/blog/building-performant-flutter-widgets).

## Measurements and checks

A temporary widget harness used the workstation's actual 598 zones and 6 locales, remounting the same two public date/time controls. No system writes were made. The measurement harness and local picker checks were removed after verification. Configuration, validation, conflicts, and refresh behavior remain covered in test/service_controllers_test.dart.

| Closed controls | Before | After |
| --- | ---: | ---: |
| Constructed widgets | 34,387 | 762 |
| Repeated remount build | 828 ms | 48 ms |
| Other full-option remount | 1,110 ms | 35 ms |

Opening the new list constructed six option rows in that viewport. A temporary 601-option check built fewer than 20 rows and found a distant result by search. Retained tests cover manual-time behavior and search draft/focus retention during external state refresh.

These are debug widget-test CPU measurements, not release frame timings or a guaranteed frame rate. Cold framework initialization is excluded from the repeated-remount comparison. Installed-desktop inspection verifies the actual picker and page behavior; a full DevTools profile trace remains a separate measurement boundary.
