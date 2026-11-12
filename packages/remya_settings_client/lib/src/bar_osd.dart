import 'dart:convert';

import 'dbus_client.dart';

const barOsdSettingId = 'remya-bar.osd';
const barVolumeStepSettingId = 'remya-bar.volume-step';
const barVolumeMaxSettingId = 'remya-bar.volume-max';
const barBrightnessStepSettingId = 'remya-bar.brightness-step';
const barGammaMinSettingId = 'remya-bar.gamma-min';
const displayGammaSettingId = 'display-gamma';

/// Writable OSD preference IDs; `Changed` uses the written ID as its topic.
const barOsdSettingIds = {
  barVolumeStepSettingId,
  barVolumeMaxSettingId,
  barBrightnessStepSettingId,
  barGammaMinSettingId,
};

/// Preferences of the Remy'a Bar on-screen display, owned by Settings.
class BarOsdPreferences {
  const BarOsdPreferences({
    this.volumeStep = 5,
    this.volumeMax = 150,
    this.brightnessStep = 5,
    this.gammaMin = 10,
  });

  final int volumeStep;

  /// Highest output volume percentage reachable from the bar (100–150).
  final int volumeMax;
  final int brightnessStep;
  final int gammaMin;

  factory BarOsdPreferences.fromJson(Object? json) {
    if (json case {
      'volume_step': final int volumeStep,
      'volume_max': final int volumeMax,
      'brightness_step': final int brightnessStep,
      'gamma_min': final int gammaMin,
    }) {
      return BarOsdPreferences(
        volumeStep: volumeStep,
        volumeMax: volumeMax,
        brightnessStep: brightnessStep,
        gammaMin: gammaMin,
      );
    }
    throw const FormatException("Invalid Remy'a Bar OSD preferences");
  }

  Map<String, Object> toJson() => {
    'volume_step': volumeStep,
    'volume_max': volumeMax,
    'brightness_step': brightnessStep,
    'gamma_min': gammaMin,
  };

  BarOsdPreferences copyWith({
    int? volumeStep,
    int? volumeMax,
    int? brightnessStep,
    int? gammaMin,
  }) => BarOsdPreferences(
    volumeStep: volumeStep ?? this.volumeStep,
    volumeMax: volumeMax ?? this.volumeMax,
    brightnessStep: brightnessStep ?? this.brightnessStep,
    gammaMin: gammaMin ?? this.gammaMin,
  );

  @override
  bool operator ==(Object other) =>
      other is BarOsdPreferences && jsonEncode(this) == jsonEncode(other);

  @override
  int get hashCode => jsonEncode(this).hashCode;
}

extension BarOsdClient on SettingsClient {
  Future<BarOsdPreferences> readBarOsdPreferences() async =>
      BarOsdPreferences.fromJson(
        (await call('Get', [barOsdSettingId]))['value'],
      );

  Future<int> setBarVolumeStep(int step) async =>
      (await call('Set', [barVolumeStepSettingId, '$step']))['value'] as int;

  Future<int> setBarVolumeMax(int max) async =>
      (await call('Set', [barVolumeMaxSettingId, '$max']))['value'] as int;

  Future<int> setBarBrightnessStep(int step) async =>
      (await call('Set', [barBrightnessStepSettingId, '$step']))['value']
          as int;

  Future<int> setBarGammaMin(int min) async =>
      (await call('Set', [barGammaMinSettingId, '$min']))['value'] as int;

  Future<int?> readOutputBrightness(String output) async =>
      (await call('Get', ['display-brightness:$output']))['percent'] as int?;

  Future<int?> setOutputBrightness(String output, int percent) async =>
      (await call('Set', ['display-brightness:$output', '$percent']))['percent']
          as int?;

  Future<int> readDisplayGamma() async =>
      (await call('Get', [displayGammaSettingId]))['gamma'] as int;

  Future<int> setDisplayGamma(int percent) async =>
      (await call('Set', [displayGammaSettingId, '$percent']))['gamma'] as int;
}
