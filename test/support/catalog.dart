import 'dart:convert';
import 'dart:io';

/// Core is a required sibling dependency; widget tests select only their page inputs.
Map<String, dynamic> readCatalog() =>
    jsonDecode(File('../remya-core/assets/catalog.json').readAsStringSync())
        as Map<String, dynamic>;
