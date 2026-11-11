import 'dbus_client.dart';

const clipboardHistoryEnabledId = 'clipboard.history-enabled';
const clipboardMaxItemsId = 'clipboard.max-items';
const clipboardRetentionDaysId = 'clipboard.retention-days';
const clipboardClearHistoryId = 'clipboard.clear-history';
const clipboardPreferenceIds = {
  clipboardHistoryEnabledId,
  clipboardMaxItemsId,
  clipboardRetentionDaysId,
};

typedef ClipboardPreferences = ({
  bool enabled,
  int maxItems,
  int retentionDays,
});

extension ClipboardClient on SettingsClient {
  Future<ClipboardPreferences> readClipboardPreferences() async {
    final value =
        (await call('Get', ['clipboard']))['value'] as Map<String, dynamic>;
    return (
      enabled: value['enabled'] as bool,
      maxItems: value['maxItems'] as int,
      retentionDays: value['retentionDays'] as int,
    );
  }

  Future<void> setClipboardHistoryEnabled(bool enabled) async {
    await call('Set', [clipboardHistoryEnabledId, '$enabled']);
  }

  Future<void> setClipboardMaxItems(int items) async {
    await call('Set', [clipboardMaxItemsId, '$items']);
  }

  Future<void> setClipboardRetentionDays(int days) async {
    await call('Set', [clipboardRetentionDaysId, '$days']);
  }

  Future<void> clearClipboardHistory() async {
    await call('Set', [clipboardClearHistoryId, 'true']);
  }
}
