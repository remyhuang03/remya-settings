import 'dart:convert';

import 'dbus_client.dart';

const notificationDndSettingId = 'notifications.do-not-disturb';
const notificationDurationSettingId = 'notifications.popup-duration';
const notificationSoundsSettingId = 'notifications.sounds';
const quietScheduleSettingId = 'quiet-schedule.enabled';
const quietStartSettingId = 'quiet-schedule.start';
const quietEndSettingId = 'quiet-schedule.end';
const quietRepeatSettingId = 'quiet-schedule.repeat';
const quietFullscreenSettingId = 'quiet-schedule.fullscreen';
const priorityCallsSettingId = 'priority-notifications.calls';
const priorityAppsSettingId = 'priority-notifications.apps';

/// Writable notification IDs; `Changed` uses the written ID as its topic.
const notificationSettingIds = {
  notificationDndSettingId,
  notificationDurationSettingId,
  notificationSoundsSettingId,
  quietScheduleSettingId,
  quietStartSettingId,
  quietEndSettingId,
  quietRepeatSettingId,
  quietFullscreenSettingId,
  priorityCallsSettingId,
  priorityAppsSettingId,
};

/// Popup durations offered by Settings; the service accepts 1 to 60 seconds.
const notificationDurations = [3, 5, 8, 10, 15, 30];
const quietRepeats = ['every-day', 'weekdays', 'weekends'];

/// An app whose notifications break through Do Not Disturb, matched by
/// desktop entry ID or app name.
typedef PriorityApp = ({String id, String name});

/// Preferences of the desktop notification service, owned by Settings.
class NotificationPreferences {
  const NotificationPreferences({
    this.doNotDisturb = false,
    this.popupDuration = 5,
    this.sounds = true,
    this.schedule = false,
    this.scheduleStart = '22:00',
    this.scheduleEnd = '07:00',
    this.scheduleRepeat = 'every-day',
    this.fullscreen = false,
    this.priorityCalls = true,
    this.priorityApps = const [],
  });

  final bool doNotDisturb;
  final int popupDuration;
  final bool sounds;
  final bool schedule;
  final String scheduleStart;
  final String scheduleEnd;
  final String scheduleRepeat;
  final bool fullscreen;
  final bool priorityCalls;
  final List<PriorityApp> priorityApps;

  factory NotificationPreferences.fromJson(Object? json) {
    if (json case {
      'do_not_disturb': final bool doNotDisturb,
      'popup_duration': final int popupDuration,
      'sounds': final bool sounds,
      'schedule': final bool schedule,
      'schedule_start': final String scheduleStart,
      'schedule_end': final String scheduleEnd,
      'schedule_repeat': final String scheduleRepeat,
      'fullscreen': final bool fullscreen,
      'priority_calls': final bool priorityCalls,
      'priority_apps': final List apps,
    }) {
      return NotificationPreferences(
        doNotDisturb: doNotDisturb,
        popupDuration: popupDuration,
        sounds: sounds,
        schedule: schedule,
        scheduleStart: scheduleStart,
        scheduleEnd: scheduleEnd,
        scheduleRepeat: scheduleRepeat,
        fullscreen: fullscreen,
        priorityCalls: priorityCalls,
        priorityApps: [
          for (final app in apps)
            if (app case {'id': final String id, 'name': final String name})
              (id: id, name: name),
        ],
      );
    }
    throw const FormatException('Invalid notification preferences');
  }

  Map<String, Object> toJson() => {
    'do_not_disturb': doNotDisturb,
    'popup_duration': popupDuration,
    'sounds': sounds,
    'schedule': schedule,
    'schedule_start': scheduleStart,
    'schedule_end': scheduleEnd,
    'schedule_repeat': scheduleRepeat,
    'fullscreen': fullscreen,
    'priority_calls': priorityCalls,
    'priority_apps': [
      for (final app in priorityApps) {'id': app.id, 'name': app.name},
    ],
  };

  @override
  bool operator ==(Object other) =>
      other is NotificationPreferences && jsonEncode(this) == jsonEncode(other);

  @override
  int get hashCode => jsonEncode(this).hashCode;
}

extension NotificationsClient on SettingsClient {
  Future<NotificationPreferences> readNotificationPreferences() async =>
      NotificationPreferences.fromJson(
        (await call('Get', ['notifications']))['value'],
      );

  /// Writes one preference; [value] is a bool, int or string as the ID needs.
  Future<Object?> setNotificationPreference(String id, Object value) async =>
      (await call('Set', [id, '$value']))['value'];

  Future<void> setPriorityApp(PriorityApp app, {required bool priority}) =>
      call('Set', [
        priorityAppsSettingId,
        jsonEncode({'id': app.id, 'name': app.name, 'priority': priority}),
      ]);
}
