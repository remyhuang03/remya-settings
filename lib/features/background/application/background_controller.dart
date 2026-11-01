import 'package:material_ui/material_ui.dart';

const backgroundKindSettingId = 'background.99b01ada';
const backgroundDisplaySettingId = 'background.display';
const backgroundFileSettingId = 'background.9e58290b';
const backgroundFitSettingId = 'background.56c289eb';
const backgroundPauseSettingId = 'background.video-pause';
const splashSettingId = 'hypr-paper-misc-options.splash';
const splashOffsetSettingId = 'hypr-paper-misc-options.splash-offset';
const splashOpacitySettingId = 'hypr-paper-misc-options.splash-opacity';
const allDisplays = '*';

typedef BackgroundReply = Future<Map<String, dynamic>>;

/// GUI state for the service-owned background feature; it holds no system logic.
class BackgroundController extends ChangeNotifier {
  BackgroundController({
    required this.read,
    required this.write,
    required this.resolve,
  });
  final BackgroundReply Function() read;
  final BackgroundReply Function(String id, String value) write;
  final BackgroundReply Function(String source) resolve;

  Map<String, dynamic> value = {};
  String? _failure;
  bool _busy = false;
  (String, String)? _failedChange;

  bool get isBusy => _busy;
  bool get initialized => value['initialized'] == true;
  bool get hasConflict => value['conflict'] == true;
  String? get writeBlocked => value['write_blocked'] as String?;
  String? get errorMessage => _failure ?? value['error'] as String?;
  bool get canChange =>
      initialized && !hasConflict && writeBlocked == null && !_busy;
  Map<String, dynamic> get saved =>
      (value['saved'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get system =>
      (value['system'] as Map?)?.cast<String, dynamic>() ?? const {};
  String get kind => saved['kind'] as String? ?? 'image';
  bool get isVideo => kind == 'video';
  List<String> get monitors =>
      (value['monitors'] as List?)?.cast<String>() ?? const [];
  List<String> get warnings =>
      (value['warnings'] as List?)?.cast<String>() ?? const [];
  Map<String, dynamic> get video =>
      (saved['video'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get splash =>
      (saved['splash'] as Map?)?.cast<String, dynamic>() ?? const {};

  /// The image a display shows: its own entry, else the all-displays one.
  Map<String, dynamic>? imageFor(String display) {
    final images = (saved['images'] as List? ?? const [])
        .cast<Map<dynamic, dynamic>>()
        .map((image) => image.cast<String, dynamic>())
        .toList();
    for (final monitor in [display, allDisplays]) {
      for (final image in images) {
        if (image['monitor'] == monitor) return image;
      }
    }
    return images.isEmpty ? null : images.first;
  }

  String? pathFor(String display) => isVideo
      ? video['path'] as String?
      : imageFor(display)?['path'] as String?;
  String? fitFor(String display) =>
      isVideo ? video['fit'] as String? : imageFor(display)?['fit'] as String?;
  String? nameOf(String? path) => (value['names'] as Map?)?[path] as String?;
  String? previewOf(String? path) =>
      (value['previews'] as Map?)?[path] as String?;

  /// Displays showing the same file with the same fit, in display order.
  List<List<String>> get displayGroups {
    final groups = <String, List<String>>{};
    for (final monitor in monitors) {
      final image = imageFor(monitor);
      groups
          .putIfAbsent('${image?['path']}\n${image?['fit']}', () => [])
          .add(monitor);
    }
    return groups.values.toList();
  }

  /// The selection after a click: the display's group first, then that display
  /// alone, then its group again. A group of one has only one state.
  static Set<String> nextDisplaySelection(
    List<List<String>> groups,
    Set<String> selected,
    String clicked,
  ) {
    final group = groups.firstWhere((g) => g.contains(clicked)).toSet();
    final wholeGroup =
        selected.length == group.length && selected.containsAll(group);
    return wholeGroup ? {clicked} : group;
  }

  /// Keeps a selection that still fits one group; otherwise selects the first
  /// selected display's group, which also covers displays that have gone away.
  Set<String> validDisplaySelection(Set<String> selected) {
    final groups = displayGroups;
    if (groups.isEmpty) return const {};
    final present = selected.where(monitors.contains).toSet();
    if (present.isEmpty) return groups.first.toSet();
    final group = groups.firstWhere((g) => g.contains(present.first));
    return group.toSet().containsAll(present) ? present : group.toSet();
  }

  /// Saved and system values, shown as they are while a conflict is open.
  String get conflictSummary {
    String line(Map<String, dynamic> state) {
      if (state['kind'] == 'video') {
        final path = (state['video'] as Map?)?['path'];
        return 'video ${nameOf(path as String?) ?? path}';
      }
      final images = (state['images'] as List? ?? const []).cast<Map>();
      return images
          .map(
            (i) =>
                '${i['monitor']} ${nameOf(i['path'] as String?) ?? i['path']}',
          )
          .join(', ');
    }

    return 'System: ${line(system)}\nSettings: ${line(saved)}';
  }

  void apply(Map<String, dynamic> state) {
    value = state;
    notifyListeners();
  }

  Future<void> reload() async {
    try {
      value = await read();
      _failure = null;
    } catch (error) {
      _failure = '$error';
    }
    notifyListeners();
  }

  Future<void> _run(BackgroundReply Function() operation) async {
    _busy = true;
    notifyListeners();
    try {
      await operation();
      _failure = null;
      value = await read();
    } catch (error) {
      _failure = '$error';
      try {
        value = await read();
      } catch (_) {}
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> set(String id, String setting) async {
    _failedChange = (id, setting);
    await _run(() => write(id, setting));
    if (_failure == null) _failedChange = null;
  }

  Future<void> retry() async {
    if (_failedChange case (final id, final setting)?) {
      await set(id, setting);
    } else {
      await reload();
    }
  }

  Future<void> useSystemConfiguration() => _run(() => resolve('system'));
  Future<void> applySavedConfiguration() => _run(() => resolve('settings'));
}

class BackgroundScope extends InheritedNotifier<BackgroundController> {
  const BackgroundScope({
    super.key,
    required BackgroundController controller,
    required super.child,
  }) : super(notifier: controller);

  static BackgroundController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackgroundScope>()?.notifier;
}
