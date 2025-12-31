import 'dart:convert';
import 'dart:io';

void main() {
  final input = File('docs/config.schema.json');
  if (!input.existsSync()) {
    stderr.writeln('Missing docs/config.schema.json');
    exit(1);
  }

  final raw = input.readAsStringSync();
  final normalized = _normalizeJson(raw);

  final output = File('lib/gen/config_schema.dart');
  output.createSync(recursive: true);
  output.writeAsStringSync(
    [
      '// GENERATED CODE - DO NOT MODIFY BY HAND',
      '// Run: fvm dart run tool/gen_schema.dart',
      '',
      "const String configSchemaJson = r'''",
      normalized,
      "''';",
      '',
    ].join('\n'),
  );
}

String _normalizeJson(String raw) {
  final decoded = jsonDecode(raw);
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(decoded);
}
