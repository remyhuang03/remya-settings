import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:remya_client/settings_contract.dart';

enum SettingAvailability {
  available('Available', 'A working, verified system integration'),
  planned('Planned', 'UI preview only; system integration is not implemented');

  const SettingAvailability(this.label, this.description);
  final String label;
  final String description;
}

enum SettingKind { toggle, choice, slider, action, info, text, color }

/// Control counts over the whole catalog, as reported by remyad.
typedef SettingsCoverage = ({int supported, int planned, int total});

class SettingsCatalog extends ChangeNotifier {
  SettingsCatalog({required this.categories, required this.pages}) {
    final categoryIds = categories.map((c) => c.id).toSet();
    final pageIds = pages.map((p) => p.id).toSet();
    final controlIds = <String>{};
    if (categoryIds.length != categories.length ||
        pageIds.length != pages.length) {
      throw const FormatException('Duplicate category or page ID');
    }
    for (final page in pages) {
      if (!categoryIds.contains(page.category) ||
          page.children.any((id) => !pageIds.contains(id))) {
        throw FormatException('Invalid navigation reference: ${page.id}');
      }
      for (final control in page.controls) {
        if (!controlIds.add(control.id)) {
          throw FormatException('Duplicate control ID: ${control.id}');
        }
      }
    }
  }

  factory SettingsCatalog.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported settings catalog version');
    }
    return SettingsCatalog(
      categories: _objects(
        json,
        'categories',
      ).map(SettingsCategory.fromJson).toList(),
      pages: _objects(json, 'pages').map(SettingsPageSpec.fromJson).toList(),
    );
  }

  static Future<SettingsCatalog> load({SettingsClient? client}) async {
    final connection = client ?? SettingsClient();
    try {
      return await _load(connection, ownsClient: client == null);
    } catch (_) {
      if (client == null) await connection.close();
      rethrow;
    }
  }

  static Future<SettingsCatalog> _load(
    SettingsClient connection, {
    required bool ownsClient,
  }) async {
    final json = await connection.call('Get', ['catalog']);
    if (json['version'] != 1) {
      throw const FormatException('Unsupported catalog');
    }
    final catalog = SettingsCatalog(
      categories: [
        ..._objects(json, 'categories').map(SettingsCategory.fromJson),
        remyaAppsCategory,
      ],
      pages: _objects(json, 'pages').map(SettingsPageSpec.summary).toList(),
    );
    catalog.sources = _objects(json, 'sources');
    catalog.coverage = switch (json['coverage']) {
      {
        'supported': final int supported,
        'planned': final int planned,
        'total': final int total,
      }
          when supported >= 0 && planned >= 0 && supported + planned == total =>
        (supported: supported, planned: planned, total: total),
      _ => throw const FormatException('Invalid catalog coverage'),
    };
    catalog._client = connection;
    catalog._ownsClient = ownsClient;
    catalog._changes = connection.changes.listen(
      (change) {
        // Changed values are invalidations: page payloads always come from Get.
        unawaited(catalog.refreshPages());
      },
      onError: (Object error) {
        catalog.error = error;
        catalog._notify();
      },
    );
    return catalog;
  }

  SettingsClient? _client;
  bool _ownsClient = false;
  StreamSubscription<SettingsChange>? _changes;
  List<Map<String, dynamic>> sources = const [];
  final Set<String> loadingPages = {};
  final Map<String, Object> pageErrors = {};
  final Set<String> _loaded = {};
  final Map<String, Future<void>> _pending = {};
  final Set<String> _managed = {};
  final Set<String> _opened = {};
  Future<void>? _refreshingPages;
  bool _pagesDirty = false;
  Object? error;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> openPage(String id) {
    if (_disposed) return Future<void>.value();
    _opened.add(id);
    return _pending[id] ??= _loadPage(id).whenComplete(() {
      _pending.remove(id);
    });
  }

  Future<void> _loadPage(String id) async {
    final client = _client;
    if (client == null) return;
    loadingPages.add(id);
    pageErrors.remove(id);
    _notify();
    try {
      var spec = page(id);
      if (!_loaded.contains(id)) {
        spec = SettingsPageSpec.fromJson(
          await client.call('Get', ['page:$id']),
        );
        if (_disposed) return;
        if (spec.id != id ||
            spec.category != page(id).category ||
            spec.children.any((child) => !pages.any((p) => p.id == child))) {
          throw const FormatException('Invalid page navigation');
        }
      }
      if (!_managed.contains(id)) {
        for (final feature in _features(spec)) {
          await client.manage(feature);
          if (_disposed) return;
        }
        _managed.add(id);
      }
      pages[pages.indexWhere((p) => p.id == id)] = spec;
      _loaded.add(id);
      error = null;
    } catch (failure) {
      if (!_disposed) pageErrors[id] = failure;
    } finally {
      loadingPages.remove(id);
      _notify();
    }
  }

  static Iterable<String> _features(SettingsPageSpec page) sync* {
    // Only stable system preferences have a Manage operation in Core.
    const direct = {
      'display',
      'night-light',
      'themes',
      'text-size',
      'language',
      'default-apps',
      'startup',
      'background',
      'power',
      'cameras',
      'cleanup',
      'appimages',
      'updates',
      'date-time',
    };
    if (direct.contains(page.id)) yield page.id;
    const aliases = {
      'mouse': 'input',
      'touchpad': 'input',
      'touch': 'input',
      'keyboard-shortcuts': 'input',
      'about': 'hostname',
      'network-status': 'network',
      'wifi': 'network',
      'known-networks': 'network',
      'ethernet': 'network',
      'battery-saver': 'power',
      'defaults': 'default-apps',
      'active-hours': 'updates',
      'accessibility-vision': 'text-size',
      'graphics': 'desktop',
      'multitasking': 'desktop',
      'workspaces': 'desktop',
      'environment-variables': 'desktop',
      'window-rules': 'desktop',
      'window-appearance': 'desktop',
      'animations': 'desktop',
      'cursor': 'desktop',
    };
    if (aliases[page.id] case final feature?) yield feature;
    if (page.id == 'cursor') yield 'themes';
  }

  Future<void> refreshPages() {
    if (_disposed) return Future<void>.value();
    _pagesDirty = true;
    return _refreshingPages ??= _refreshPages();
  }

  Future<void> _refreshPages() async {
    try {
      while (_pagesDirty && !_disposed) {
        _pagesDirty = false;
        // In-flight loads may have read an older snapshot before Changed.
        await Future.wait(_pending.values.toList());
        if (_disposed) return;
        _loaded.clear();
        await Future.wait([for (final id in _opened.toList()) openPage(id)]);
        if (_query.isNotEmpty) await _search(_query);
      }
    } finally {
      _refreshingPages = null;
    }
  }

  Future<void> reload() async {
    try {
      await _client?.call('Reload');
      error = null;
      await refreshPages();
      if (apps != null) await loadApps();
    } catch (failure) {
      error = failure;
      _notify();
    }
  }

  String _query = '';
  int _searchRequest = 0;
  List<SettingsPageSpec> _results = [];
  List<Map<String, dynamic>> searchResults = [];
  List<AppSearchResult> appResults = [];
  bool searching = false;
  Object? searchError;
  Future<void> _search(String query) async {
    if (_disposed || query.isEmpty) return;
    final request = ++_searchRequest;
    bool current() => !_disposed && request == _searchRequest;
    searching = true;
    searchError = null;
    try {
      final result = await _client!.call('Search', [query]);
      if (!current()) return;
      final rows = _objects(result, 'pages');
      final ids = rows
          .where((p) => !p.containsKey('app'))
          .map((p) => _string(p, 'id'))
          .toSet();
      final appRows = [
        for (final row in rows)
          if (row.containsKey('app'))
            (
              app: _string(row, 'app'),
              page: _string(row, 'page'),
              title: _string(row, 'title'),
            ),
      ];
      searchResults = rows;
      appResults = appRows;
      _results = pages.where((p) => ids.contains(p.id)).toList();
      // App results are labeled with their registration title.
      if (appRows.isNotEmpty && apps == null) unawaited(loadApps());
    } catch (failure) {
      if (current()) searchError = failure;
    } finally {
      if (current()) {
        searching = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final cancel = _changes?.cancel();
    if (_ownsClient) {
      unawaited(_closeClient(cancel));
    }
    super.dispose();
  }

  Future<void> _closeClient(Future<void>? cancel) async {
    try {
      await cancel;
    } finally {
      await _client?.close();
    }
  }

  final List<SettingsCategory> categories;
  final List<SettingsPageSpec> pages;

  SettingsCategory category(String id) =>
      categories.firstWhere((c) => c.id == id);

  SettingsPageSpec page(String id) => pages.firstWhere((p) => p.id == id);
  List<SettingsPageSpec> inCategory(String id) {
    final categoryPages = pages.where((p) => p.category == id);
    return [
      ...categoryPages.where((p) => !p.id.endsWith('-more')),
      ...categoryPages.where((p) => p.id.endsWith('-more')),
    ];
  }

  /// Null for a catalog not loaded from remyad.
  SettingsCoverage? coverage;

  List<SettingsPageSpec> search(String query) {
    if (_disposed || _client == null) return [];
    if (_query != query) {
      _query = query;
      _results = [];
      appResults = [];
      searchResults = [];
      if (query.isEmpty) {
        _searchRequest++;
        searching = false;
        searchError = null;
      } else {
        unawaited(_search(query));
      }
    }
    return _results;
  }

  Future<void> retrySearch() => _search(_query);

  /// Registered Remy'a apps from `List`, including rejected registration files.
  /// Null until first loaded; a failed refresh keeps the previous list.
  List<RemyaApp>? apps;
  Object? appsError;
  bool loadingApps = false;

  Future<void> loadApps() async {
    final client = _client;
    if (_disposed || client == null || loadingApps) return;
    loadingApps = true;
    appsError = null;
    _notify();
    try {
      final response = await client.call('List', ['0']);
      if (!_disposed) {
        apps = _objects(response, 'apps').map(RemyaApp.fromJson).toList();
      }
    } catch (failure) {
      if (!_disposed) appsError = failure;
    } finally {
      loadingApps = false;
      _notify();
    }
  }

  String appTitle(String id) =>
      apps?.where((app) => app.id == id).firstOrNull?.title ?? id;

  /// Core launches the app's settings desktop action; an empty page opens its home.
  Future<void> openApp(String app, [String page = '']) async {
    await _client?.call('OpenApp', [app, page]);
  }
}

/// Client-side category listing installed Remy'a apps; it has no catalog pages.
const remyaAppsCategory = SettingsCategory(
  id: 'remya-apps',
  title: "Remy'a apps",
  description: "Settings windows of installed Remy'a apps",
  icon: 'remya_apps',
);

typedef AppSearchResult = ({String app, String page, String title});

class RemyaApp {
  const RemyaApp({
    required this.id,
    required this.title,
    required this.icon,
    required this.pages,
    required this.error,
  });

  /// Rejected registrations may carry null or malformed metadata.
  factory RemyaApp.fromJson(Map<String, dynamic> json) {
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value : null;
    final pages = json['pages'];
    return RemyaApp(
      id: _string(json, 'id'),
      title: text(json['title']),
      icon: text(json['icon']),
      pages: [
        if (pages is List)
          for (final page in pages.whereType<Map<String, dynamic>>())
            if ((text(page['id']), text(page['title'])) case (
              final id?,
              final title?,
            ))
              (id: id, title: title),
      ],
      error: json['error'] == null ? null : '${json['error']}',
    );
  }

  final String id;
  final String? title;
  final String? icon;
  final List<({String id, String title})> pages;
  final String? error;
}

class SettingsCategory {
  const SettingsCategory({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
  });

  factory SettingsCategory.fromJson(Map<String, dynamic> json) =>
      SettingsCategory(
        id: _string(json, 'id'),
        title: _string(json, 'title'),
        description: _string(json, 'description'),
        icon: _string(json, 'icon'),
      );

  final String id;
  final String title;
  final String description;
  final String icon;
}

class SettingsPageSpec {
  const SettingsPageSpec({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.preview,
    required this.availability,
    required this.reason,
    required this.windowsUris,
    required this.children,
    required this.sections,
  });

  factory SettingsPageSpec.summary(Map<String, dynamic> json) =>
      SettingsPageSpec(
        id: _string(json, 'id'),
        category: _string(json, 'category'),
        title: _string(json, 'title'),
        description: '',
        preview: '',
        availability: .planned,
        reason: 'Page details have not been loaded',
        windowsUris: const [],
        children: const [],
        sections: const [],
      );

  factory SettingsPageSpec.fromJson(Map<String, dynamic> json) =>
      SettingsPageSpec(
        id: _string(json, 'id'),
        category: _string(json, 'category'),
        title: _string(json, 'title'),
        description: _string(json, 'description'),
        preview: _string(json, 'preview'),
        availability: .values.byName(_string(json, 'availability')),
        reason: _string(json, 'reason'),
        windowsUris: _strings(json, 'windowsUris'),
        children: _strings(json, 'children'),
        sections: _objects(
          json,
          'sections',
        ).map(SettingsSection.fromJson).toList(),
      );

  final String id;
  final String category;
  final String title;
  final String description;
  final String preview;
  final SettingAvailability availability;
  final String reason;
  final List<String> windowsUris;
  final List<String> children;
  final List<SettingsSection> sections;
  Iterable<SettingSpec> get controls => sections.expand((s) => s.controls);
}

class SettingsSection {
  const SettingsSection({
    required this.title,
    required this.controls,
    this.collapsed = false,
    this.description,
  });

  factory SettingsSection.fromJson(Map<String, dynamic> json) =>
      SettingsSection(
        title: _string(json, 'title'),
        collapsed: json['collapsed'] as bool? ?? false,
        description: json['description'] as String?,
        controls: _objects(json, 'controls').map(SettingSpec.fromJson).toList(),
      );

  final String title;
  final bool collapsed;
  final String? description;
  final List<SettingSpec> controls;
}

class SettingSpec {
  const SettingSpec({
    required this.id,
    required this.title,
    required this.kind,
    required this.availability,
    required this.reason,
    this.value,
    this.options = const [],
    this.min = 0,
    this.max = 100,
    this.unit = '',
  });

  factory SettingSpec.fromJson(Map<String, dynamic> json) {
    final kind = SettingKind.values.byName(_string(json, 'type'));
    final value = json['value'];
    final options = json.containsKey('options')
        ? _strings(json, 'options')
        : <String>[];
    final min = (json['min'] as num?)?.toDouble() ?? 0;
    final max = (json['max'] as num?)?.toDouble() ?? 100;
    if ((kind == .toggle && value is! bool) ||
        (kind == .choice && (options.isEmpty || !options.contains(value))) ||
        (kind == .slider &&
            (value is! num ||
                !value.isFinite ||
                min >= max ||
                value < min ||
                value > max)) ||
        (<SettingKind>{.action, .info, .text, .color}.contains(kind) &&
            value is! String) ||
        (kind == .color &&
            !RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$')
                .hasMatch(value as String))) {
      throw FormatException('Invalid value for setting ${json['id']}');
    }
    return SettingSpec(
      id: _string(json, 'id'),
      title: _string(json, 'title'),
      kind: kind,
      availability: .values.byName(_string(json, 'availability')),
      reason: _string(json, 'reason'),
      value: value,
      options: options,
      min: min,
      max: max,
      unit: json['unit'] as String? ?? '',
    );
  }

  final String id;
  final String title;
  final SettingKind kind;
  final SettingAvailability availability;
  final String reason;
  final Object? value;
  final List<String> options;
  final double min;
  final double max;
  final String unit;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Expected nonempty string: $key');
  }
  return value;
}

List<Map<String, dynamic>> _objects(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('Expected object list: $key');
  }
  return value.map((item) {
    if (item is! Map<String, dynamic>) {
      throw FormatException('Expected object in $key');
    }
    return item;
  }).toList();
}

List<String> _strings(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('Expected string list: $key');
  }
  return value.cast<String>();
}
