import 'dart:convert';

import 'package:flutter/services.dart';

enum SettingAvailability {
  available('Available', 'A working, verified system integration'),
  planned('Planned', 'UI preview only; system integration is not implemented'),
  unsupported(
    'Unsupported',
    'Windows-specific, legacy, or inapplicable to this platform',
  );

  const SettingAvailability(this.label, this.description);
  final String label;
  final String description;
}

enum SettingKind { toggle, choice, slider, action, info, text, color }

class SettingsCatalog {
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

  static Future<SettingsCatalog> load() async => SettingsCatalog.fromJson(
    jsonDecode(await rootBundle.loadString('assets/settings/catalog.json'))
        as Map<String, dynamic>,
  );

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

  int get controlCount => pages.fold(0, (sum, p) => sum + p.controls.length);

  List<SettingsPageSpec> search(String query) {
    final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
    return pages.where((p) {
      final text = [
        p.title,
        p.description,
        category(p.category).title,
        ...p.windowsUris,
        ...p.sections.map((s) => s.description ?? ''),
        ...p.controls.map((c) => c.title),
      ].join(' ').toLowerCase();
      return terms.every(text.contains);
    }).toList();
  }
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
            !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value as String))) {
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
  if (value is! List || value.isEmpty) {
    throw FormatException('Expected nonempty object list: $key');
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
