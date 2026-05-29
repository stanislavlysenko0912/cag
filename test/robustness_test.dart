import 'dart:io';

import 'package:cag/cag.dart';
import 'package:cag/src/utils/base_jsonl_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('BaseJsonlStorage robustness', () {
    late Directory tempDir;
    late String storagePath;
    late StringBuffer warningSink;
    late BaseJsonlStorage<_StoredValue> storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cag_storage_robust_');
      storagePath = p.join(tempDir.path, 'records.jsonl');
      warningSink = StringBuffer();
      storage = BaseJsonlStorage<_StoredValue>(
        storagePath: storagePath,
        fromJson: _StoredValue.fromJson,
        toJson: (value) => value.toJson(),
        getId: (value) => value.id,
        warningSink: warningSink,
      );
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test(
      'loadAll skips invalid json lines and preserves valid records',
      () async {
        final file = File(storagePath);
        await file.parent.create(recursive: true);
        await file.writeAsString(
          '{"id":"one","value":"ok"}\n'
          'not-json\n'
          '{"id":"two","value":"still-ok"}\n',
        );

        final values = await storage.loadAll();

        expect(values.map((value) => value.id), equals(['one', 'two']));
        expect(
          warningSink.toString(),
          contains('Warning: skipped invalid record'),
        );
        expect(warningSink.toString(), contains('$storagePath:2'));
      },
    );

    test('loadAll skips non-object and malformed object lines', () async {
      final file = File(storagePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '[]\n'
        '{"id":"missing-value"}\n'
        '{"id":"ok","value":"ready"}\n',
      );

      final values = await storage.loadAll();

      expect(values, hasLength(1));
      expect(values.single.id, equals('ok'));
      expect(warningSink.toString(), contains('$storagePath:1'));
      expect(warningSink.toString(), contains('$storagePath:2'));
    });

    test('load returns valid record when corruption is present', () async {
      final file = File(storagePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        'broken\n'
        '{"id":"target","value":"found"}\n',
      );

      final value = await storage.load('target');

      expect(value?.value, equals('found'));
      expect(warningSink.toString(), contains('$storagePath:1'));
    });

    test('save rewrites only valid records after partial corruption', () async {
      final file = File(storagePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '{"id":"keep","value":"first"}\n'
        'broken\n',
      );

      await storage.save(_StoredValue(id: 'new', value: 'second'));

      final content = await file.readAsString();
      expect(content, isNot(contains('broken')));
      expect(content, contains('"id":"keep"'));
      expect(content, contains('"id":"new"'));
    });

    test('delete removes file when final valid record is deleted', () async {
      final file = File(storagePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '{"id":"only","value":"first"}\n'
        'broken\n',
      );

      await storage.delete('only');

      expect(await file.exists(), isFalse);
      expect(warningSink.toString(), contains('$storagePath:2'));
    });
  });

  group('ConfigService robustness', () {
    late Directory tempDir;
    late String configPath;
    late StringBuffer warningSink;
    late ConfigService configService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cag_config_robust_');
      configPath = p.join(tempDir.path, 'config.json');
      warningSink = StringBuffer();
      configService = ConfigService(
        configPath: configPath,
        warningSink: warningSink,
      );
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('missing config creates defaults on disk', () async {
      final config = await configService.loadOrCreate();

      expect(config.agents, isEmpty);
      expect(await File(configPath).exists(), isTrue);
      expect(warningSink.toString(), isEmpty);
    });

    test('empty config rewrites defaults on disk', () async {
      final file = File(configPath);
      await file.parent.create(recursive: true);
      await file.writeAsString('   \n');

      final config = await configService.loadOrCreate();

      expect(config.agents, isEmpty);
      expect(await file.readAsString(), contains('"agents"'));
      expect(warningSink.toString(), isEmpty);
    });

    test('invalid json returns defaults and keeps broken file', () async {
      final file = File(configPath);
      await file.parent.create(recursive: true);
      await file.writeAsString('{invalid');

      final config = await configService.loadOrCreate();

      expect(config.agents, isEmpty);
      expect(await file.readAsString(), equals('{invalid'));
      expect(
        warningSink.toString(),
        contains('Config parse error: $configPath'),
      );
    });

    test(
      'schema-invalid config returns defaults and keeps invalid file',
      () async {
        final file = File(configPath);
        await file.parent.create(recursive: true);
        await file.writeAsString('{"agents": []}\n');

        final config = await configService.loadOrCreate();

        expect(config.agents, isEmpty);
        expect(await file.readAsString(), equals('{"agents": []}\n'));
        expect(
          warningSink.toString(),
          contains('Config validation failed at $configPath:'),
        );
      },
    );

    test('legacy timeout migration rewrites only valid config', () async {
      final file = File(configPath);
      await file.parent.create(recursive: true);
      await file.writeAsString('''
{
  "agents": {
    "claude": {
      "enabled": true,
      "timeout_seconds": 123
    }
  }
}
''');

      final config = await configService.loadOrCreate();
      final content = await file.readAsString();

      expect(config.agents['claude']?.hardTimeoutSeconds, equals(123));
      expect(config.agents['claude']?.idleTimeoutSeconds, equals(123));
      expect(content, contains('"hard_timeout_seconds": 123'));
      expect(content, contains('"idle_timeout_seconds": 123'));
      expect(content, isNot(contains('"timeout_seconds"')));
    });
  });
}

class _StoredValue {
  _StoredValue({required this.id, required this.value});

  final String id;
  final String value;

  factory _StoredValue.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final value = json['value'];
    if (id is! String || id.isEmpty) {
      throw FormatException('Missing required string field "id"');
    }
    if (value is! String || value.isEmpty) {
      throw FormatException('Missing required string field "value"');
    }
    return _StoredValue(id: id, value: value);
  }

  Map<String, dynamic> toJson() => {'id': id, 'value': value};
}
