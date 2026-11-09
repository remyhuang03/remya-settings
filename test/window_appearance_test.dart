import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/animations/presentation/animations_page.dart';
import 'package:remya_settings/features/multitasking/presentation/multitasking_page.dart';
import 'package:remya_settings/features/window_appearance/presentation/window_appearance_page.dart';

import 'input_test.dart' show catalog, pump;
import 'multitasking_cursor_test.dart' show FeaturesClient, desktop, themes;

Map<String, dynamic> _desktop(Map<String, Object?> options) => desktop({
  'window-appearance.rounding': 10,
  'window-appearance.rounding-power': 2.0,
  'window-appearance.active-border': '#33ccffee',
  'window-appearance.inactive-border': '#59595900',
  'window-appearance.dim-inactive': false,
  'window-appearance.shadow': true,
  'window-appearance.shadow-offset': [0, 4],
  'window-appearance.glow': false,
  'animations.enabled': true,
  'animations.motion-blur': false,
  'animations.wobble': false,
  ...options,
});

FeaturesClient _client([Map<String, Object?> options = const {}]) =>
    FeaturesClient({'desktop': _desktop(options), 'themes': themes()});

void main() {
  testWidgets('window appearance previews and hides dependent options', (
    tester,
  ) async {
    final client = _client();
    await pump(
      tester,
      WindowAppearancePage(
        catalog: catalog,
        page: catalog.page('window-appearance'),
        client: client,
      ),
    );
    expect(
      find.byKey(const ValueKey('window-appearance-preview')),
      findsOneWidget,
    );
    expect(find.text('#33ccffee'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('window-appearance.dim-strength')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('window-appearance.glow-color')),
      findsNothing,
    );
    expect(find.text('Right 0 px, down 4 px'), findsOneWidget);

    // Each offset axis writes both coordinates on release.
    tester
        .widget<Slider>(
          find.byKey(const ValueKey('window-appearance.shadow-offset-x')),
        )
        .onChangeEnd!(3);
    await tester.pumpAndSettle();
    expect(client.calls.last, [
      'Set',
      'window-appearance.shadow-offset',
      '[3,4]',
    ]);

    await tester.tap(
      find.byKey(const ValueKey('window-appearance.glow-switch')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('window-appearance.glow-color')),
      findsOneWidget,
    );
  });

  testWidgets('animation sub-options follow their switches', (tester) async {
    final client = _client({'animations.wobble': true});
    await pump(
      tester,
      AnimationsPage(
        catalog: catalog,
        page: catalog.page('animations'),
        client: client,
      ),
    );
    expect(
      find.byKey(const ValueKey('animations.motion-blur-samples')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('animations.wobble-stiffness')),
      findsOneWidget,
    );
  });

  testWidgets('dwindle options show only for the dwindle layout', (
    tester,
  ) async {
    final client = _client({'multitasking.layout': 'master'});
    await pump(
      tester,
      MultitaskingPage(
        catalog: catalog,
        page: catalog.page('multitasking'),
        client: client,
      ),
    );
    expect(find.text('Dwindle layout'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('layout-dwindle')));
    await tester.pumpAndSettle();
    expect(find.text('Dwindle layout'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('multitasking.dwindle-force-split')),
      findsOneWidget,
    );
  });
}
