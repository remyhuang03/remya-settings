import 'dart:convert';

import 'dbus_client.dart';

const barLayoutSettingId = 'remya-bar.layout';

/// Pill IDs in their default order. The service rejects any other ID.
const barPillIds = [
  'notifications',
  'window',
  'resources',
  'media',
  'workspaces',
  'clock',
  'tray',
  'battery',
  'sidebar',
];

/// System resources metrics in display order.
const barResourceIds = ['cpu', 'memory', 'gpu', 'network'];

/// Main bar pill groups and per-pill options owned by Settings.
class BarLayout {
  const BarLayout({
    required this.groups,
    this.workspaceCount = 8,
    this.resources = barResourceIds,
    this.windowAppName = true,
    this.mediaMarquee = false,
    this.center,
  });

  static const defaults = BarLayout(
    groups: [
      ['notifications', 'window', 'resources', 'media'],
      ['workspaces', 'clock'],
      ['tray'],
      ['battery', 'sidebar'],
    ],
  );

  /// Ordered groups; a pill missing from every group is hidden.
  final List<List<String>> groups;
  final int workspaceCount;
  final List<String> resources;
  final bool windowAppName;
  final bool mediaMarquee;

  /// Index of the group centered on the bar, or null. Groups before and after
  /// it are spaced evenly within their own side.
  final int? center;

  factory BarLayout.fromJson(Object? json) {
    if (json
        case {
          'groups': final List groups,
          'workspace_count': final int workspaceCount,
          'resources': final List resources,
          'window_app_name': final bool windowAppName,
        }
        when json['center'] is int? &&
            (!json.containsKey('media_marquee') ||
                json['media_marquee'] is bool)) {
      return BarLayout(
        groups: [for (final group in groups) List<String>.from(group as List)],
        workspaceCount: workspaceCount,
        resources: List<String>.from(resources),
        windowAppName: windowAppName,
        mediaMarquee: json['media_marquee'] as bool? ?? false,
        center: json['center'] as int?,
      );
    }
    throw const FormatException('Invalid Remy\'a Bar layout');
  }

  Map<String, Object> toJson() => {
    'groups': groups,
    'workspace_count': workspaceCount,
    'resources': resources,
    'window_app_name': windowAppName,
    'media_marquee': mediaMarquee,
    'center': ?center,
  };

  List<String> get hidden => [
    for (final id in barPillIds)
      if (!groups.any((group) => group.contains(id))) id,
  ];

  BarLayout copyWith({
    int? workspaceCount,
    List<String>? resources,
    bool? windowAppName,
    bool? mediaMarquee,
  }) => BarLayout(
    groups: groups,
    workspaceCount: workspaceCount ?? this.workspaceCount,
    resources: resources ?? this.resources,
    windowAppName: windowAppName ?? this.windowAppName,
    mediaMarquee: mediaMarquee ?? this.mediaMarquee,
    center: center,
  );

  /// Returns this layout with new groups and centered group, keeping options.
  BarLayout withGroups(List<List<String>> groups, {int? center}) => BarLayout(
    groups: groups,
    workspaceCount: workspaceCount,
    resources: resources,
    windowAppName: windowAppName,
    mediaMarquee: mediaMarquee,
    center: center,
  );

  /// Applies [edit] to copies of the groups, then drops emptied groups while
  /// the centered group keeps its flag.
  BarLayout _edit(void Function(List<List<String>> groups) edit) {
    final next = [
      for (final pills in groups) [...pills],
    ];
    final centered = center == null ? null : next[center!];
    edit(next);
    final kept = [
      for (final pills in next)
        if (pills.isNotEmpty) pills,
    ];
    final index = kept.indexWhere((pills) => identical(pills, centered));
    return withGroups(kept, center: index < 0 ? null : index);
  }

  /// Moves [id] (visible or hidden) into [group] at [index], appending when
  /// null. A [group] equal to the group count adds a new last group.
  BarLayout movePill(String id, int group, [int? index]) => _edit((next) {
    for (final pills in next) {
      pills.remove(id);
    }
    if (group == next.length) next.add([]);
    final target = next[group];
    target.insert((index ?? target.length).clamp(0, target.length), id);
  });

  BarLayout hidePill(String id) => _edit((next) {
    for (final pills in next) {
      pills.remove(id);
    }
  });

  /// Hides every pill of [group] and removes it.
  BarLayout removeGroup(int group) => _edit((next) => next[group].clear());

  /// Moves [from] to position [to] counted after its removal.
  BarLayout moveGroup(int from, int to) =>
      _edit((next) => next.insert(to, next.removeAt(from)));

  BarLayout withCenter(int? group) => withGroups(groups, center: group);

  @override
  bool operator ==(Object other) =>
      other is BarLayout && jsonEncode(this) == jsonEncode(other);

  @override
  int get hashCode => jsonEncode(this).hashCode;
}

extension BarLayoutClient on SettingsClient {
  Future<BarLayout> readBarLayout() async =>
      BarLayout.fromJson((await call('Get', [barLayoutSettingId]))['value']);

  Future<BarLayout> setBarLayout(BarLayout layout) async => BarLayout.fromJson(
    (await call('Set', [barLayoutSettingId, jsonEncode(layout)]))['value'],
  );
}
