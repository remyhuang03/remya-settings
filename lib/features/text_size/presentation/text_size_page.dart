import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../input/presentation/input_widgets.dart';
import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_content.dart';
import '../../settings/presentation/settings_widgets.dart';

/// GNOME's whole accepted range in 5 % steps, shared with the conflict summary.
final _shape = sliderShapes[textScaleId]!;
String _percent(double factor) => _shape.text(factor);

/// GNOME text scaling factor with a sample that follows the slider.
class TextSizePage extends StatefulWidget {
  const TextSizePage({
    super.key,
    required this.catalog,
    required this.page,
    required this.client,
    required this.onPage,
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;
  final ValueChanged<SettingsPageSpec> onPage;

  @override
  State<TextSizePage> createState() => _TextSizePageState();
}

class _TextSizePageState extends State<TextSizePage> {
  late final _controller = FeatureOptionsController(
    widget.client,
    feature: 'text-size',
  )..reload();
  double? _dragging;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _saved => (_controller.option(textScaleId) as num?)?.toDouble();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final scale = _dragging ?? _saved;
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          Text(widget.page.description, style: text.bodyLarge),
          const SizedBox(height: 12),
          if (_controller.errorMessage case final error?)
            SettingsErrorCard(message: error, onRetry: _controller.reload),
          if (_controller.hasConflict)
            InputConflictCard(
              controls: widget.page.controls,
              controller: _controller,
              title: 'Text size differs from saved Settings',
            ),
          if (!_controller.isLoaded)
            const RemyaLoadingBar()
          else ...[
            if (scale != null) _Sample(scale: scale),
            for (final section in widget.page.sections)
              SettingsSectionCard(
                section,
                onPageRow: (_) {},
                pageRows: const {},
                controlBuilder: (setting) => setting.id == textScaleId
                    ? _row(setting, scale)
                    : SettingControlTile(setting),
              ),
            if (widget.page.children.isNotEmpty) ...[
              const SettingsSectionTitle('Related settings'),
              SettingsSurface(
                padding: .zero,
                child: Column(
                  children: [
                    for (final id in widget.page.children)
                      PageLink(
                        page: widget.catalog.page(id),
                        icon: pageIcon(
                          widget.catalog.page(id),
                          widget.catalog.category(
                            widget.catalog.page(id).category,
                          ),
                        ),
                        onTap: () => widget.onPage(widget.catalog.page(id)),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ],
      );
    },
  );

  Widget _row(SettingSpec setting, double? scale) {
    final text = Theme.of(context).textTheme;
    final enabled = _controller.canChange && scale != null;
    final value = (scale ?? 1).clamp(_shape.min, _shape.max);
    return SettingRow(
      id: setting.id,
      label: Column(
        crossAxisAlignment: .start,
        spacing: 4,
        children: [
          Text(setting.title, style: text.bodyLarge),
          Text(
            scale == null ? 'Unknown' : _percent(scale),
            style: text.bodySmall,
          ),
          Text(
            'Applies to GTK 3, GTK 4 and Flutter apps, including Settings. '
            'Open apps update right away. Qt, KDE and other toolkits keep '
            'their own text size.',
            style: text.bodySmall,
          ),
        ],
      ),
      control: SizedBox(
        width: 260,
        child: Slider(
          key: const ValueKey('$textScaleId-slider'),
          value: value,
          min: _shape.min,
          max: _shape.max,
          divisions: ((_shape.max - _shape.min) / _shape.step).round(),
          label: _percent(value),
          onChanged: enabled ? (v) => setState(() => _dragging = v) : null,
          onChangeEnd: enabled
              ? (v) async {
                  // Whole 5 % steps, so 1.15 is stored rather than 1.1500000000000001.
                  final factor = (v * 20).round() / 20;
                  await _controller.set(textScaleId, factor);
                  if (mounted) setState(() => _dragging = null);
                }
              : null,
        ),
      ),
    );
  }
}

/// A paragraph at the chosen size, independent of the current scaling.
class _Sample extends StatelessWidget {
  const _Sample({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final style = text.bodyLarge!;
    return Padding(
      padding: const .only(bottom: 8),
      child: SettingsSurface(
        child: Column(
          crossAxisAlignment: .start,
          spacing: 12,
          children: [
            Text(
              'Preview at ${_percent(scale)}',
              style: text.labelLarge?.copyWith(color: colors.onSurfaceVariant),
            ),
            MediaQuery.withNoTextScaling(
              child: Text(
                'Text in menus, windows and documents appears at this size. '
                'Choose a size that is comfortable to read.',
                key: const ValueKey('text-size-sample'),
                style: style.copyWith(fontSize: style.fontSize! * scale),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
