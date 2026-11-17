import 'dart:convert';
import 'dart:io';

/// Read the catalog from the Core checkout selected by the package resolver.
Map<String, dynamic> readCatalog() {
  final config = File('.dart_tool/package_config.json').absolute;
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
  final client = packages.cast<Map>().firstWhere(
    (package) => package['name'] == 'remya_client',
  );
  final catalog = config.uri.resolve(
    '${client['rootUri']}/../../assets/catalog.json',
  );
  return jsonDecode(File.fromUri(catalog).readAsStringSync())
      as Map<String, dynamic>;
}
