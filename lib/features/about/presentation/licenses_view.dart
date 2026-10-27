import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../settings/presentation/settings_widgets.dart';

class LicensesView extends StatefulWidget {
  const LicensesView({super.key});

  @override
  State<LicensesView> createState() => _LicensesViewState();
}

class _LicensesViewState extends State<LicensesView> {
  late final _licenses = _loadLicenses();
  String? _selected;

  Future<Map<String, List<LicenseEntry>>> _loadLicenses() async {
    final packages = <String, List<LicenseEntry>>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        packages.putIfAbsent(package, () => []).add(entry);
      }
    }
    final names = packages.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return {for (final name in names) name: packages[name]!};
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _licenses,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(child: Text('Unable to load licenses.'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final packages = snapshot.data!;
      if (packages.isEmpty) {
        return const Center(child: Text('No licenses found.'));
      }
      final selected = _selected ?? packages.keys.first;
      final names = packages.keys.toList();
      final list = SettingsSurface(
        padding: .zero,
        child: ListView.builder(
          key: const ValueKey('license-packages'),
          primary: false,
          padding: const .all(8),
          itemCount: names.length,
          itemBuilder: (context, index) {
            final name = names[index];
            return ListTile(
              key: ValueKey('license-package-$name'),
              title: Text(name),
              subtitle: Text(
                MaterialLocalizations.of(context)
                    .licensesPackageDetailText(packages[name]!.length),
              ),
              selected: selected == name,
              selectedTileColor: Theme.of(context)
                  .colorScheme
                  .secondaryContainer,
              shape: RoundedRectangleBorder(borderRadius: .circular(16)),
              onTap: () => setState(() => _selected = name),
            );
          },
        ),
      );
      final detail = SettingsSurface(
        padding: .zero,
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const .all(20),
              child: Text(
                selected,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SelectionArea(
                child: ListView(
                  key: ValueKey('license-text-$selected'),
                  primary: false,
                  padding: const .all(20),
                  children: [
                    for (var i = 0; i < packages[selected]!.length; i++) ...[
                      if (i != 0) const Divider(height: 32),
                      for (final paragraph in packages[selected]![i].paragraphs)
                        _LicenseParagraph(paragraph),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      return LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 720
            ? Row(
                crossAxisAlignment: .stretch,
                children: [
                  SizedBox(width: 260, child: list),
                  const SizedBox(width: 16),
                  Expanded(child: detail),
                ],
              )
            : Column(
                children: [
                  Expanded(child: list),
                  const SizedBox(height: 16),
                  Expanded(flex: 2, child: detail),
                ],
              ),
      );
    },
  );
}

class _LicenseParagraph extends StatelessWidget {
  const _LicenseParagraph(this.paragraph);
  final LicenseParagraph paragraph;

  @override
  Widget build(BuildContext context) {
    final centered = paragraph.indent == LicenseParagraph.centeredIndent;
    return Padding(
      padding: .only(top: 8, left: centered ? 0 : paragraph.indent * 16),
      child: Text(
        paragraph.text,
        textAlign: centered ? .center : .start,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
      ),
    );
  }
}
