import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/text_size/presentation/text_size_page.dart';
import 'package:remya_settings_client/settings_contract.dart';

import 'input_test.dart' show catalog, pump;

class _Client extends SettingsClient {
  _Client(this.state);
  Map<String, dynamic> state;
  final calls = <List<String>>[];

  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    calls.add([method, ...arguments]);
    if (method == 'Set') {
      state = {
        ...state,
        'options': {arguments[0]: jsonDecode(arguments[1])},
      };
    }
    return state;
  }
}

Map<String, dynamic> _state(double saved, [double? system]) => {
  'options': {textScaleId: saved},
  'saved': {textScaleId: saved},
  'system': {textScaleId: system ?? saved},
  'conflict': system != null,
  'conflicts': [if (system != null) textScaleId],
};

Widget _page(SettingsClient client) => TextSizePage(
  catalog: catalog,
  page: catalog.page('accessibility-vision'),
  client: client,
  onPage: (_) {},
);

double _sampleSize(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('text-size-sample')))
    .style!
    .fontSize!;

void main() {
  testWidgets('the sample follows the slider and release writes a 5 % step', (
    tester,
  ) async {
    final client = _Client(_state(1));
    await pump(tester, _page(client));
    final base = _sampleSize(tester);
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('$textScaleId-slider')),
    );
    expect(slider.divisions, 50);
    slider.onChanged!(1.5);
    await tester.pump();
    expect(_sampleSize(tester), base * 1.5);
    expect(find.text('Preview at 150%'), findsOneWidget);
    slider.onChangeEnd!(1.1500000000000001);
    await tester.pumpAndSettle();
    expect(client.calls.last, ['Set', textScaleId, '1.15']);
    expect(find.text('115%'), findsOneWidget);
  });

  testWidgets('a conflict names both sizes and blocks the slider', (
    tester,
  ) async {
    await pump(tester, _page(_Client(_state(1.25, 2))));
    expect(find.text('Text size: system 200%, Settings 125%'), findsOneWidget);
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('$textScaleId-slider')),
    );
    expect(slider.onChanged, isNull);
  });
}
