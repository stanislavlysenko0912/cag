import 'dart:convert';
import 'dart:io';

import 'package:cag/cag.dart';
import 'package:cag/src/doctor/doctor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('consensus CLI', () {
    late Directory tempDir;
    late Map<String, String> environment;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cag_cli_consensus_');
      environment = buildAppEnvironment(tempDir);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('--list shows empty message', () async {
      final result = await runCli(['consensus', '--list'], environment);

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('No consensus sessions found.'));
    });

    test('--list --json returns empty runs payload', () async {
      final result = await runCli([
        'consensus',
        '--list',
        '--json',
      ], environment);

      expect(result.exitCode, equals(0));
      expect(
        jsonDecode(result.stdout as String),
        equals({'runs': <Object?>[]}),
      );
    });

    test('--inspect --json prints stored session document', () async {
      final storage = ConsensusStorage(storagePath: consensusPathFor(tempDir));
      await storage.save(
        ConsensusSession(
          consensusId: 'cons-123',
          title: 'Profile caching debate',
          prompt: 'Should we cache profiles?',
          proposal: 'Use Redis.',
          participants: [
            ConsensusParticipant(
              agent: 'gemini',
              model: 'pro',
              stance: ConsensusStance.forProposal,
            ),
          ],
          createdAt: DateTime.parse('2026-04-04T10:00:00Z'),
        ),
      );

      final result = await runCli([
        'consensus',
        '--inspect',
        'cons-123',
        '--json',
      ], environment);

      expect(result.exitCode, equals(0));
      final payload =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(payload['consensus_id'], equals('cons-123'));
      expect(payload['title'], equals('Profile caching debate'));
      expect(payload['proposal'], equals('Use Redis.'));
    });

    test('--inspect prints stored session summary', () async {
      final storage = ConsensusStorage(storagePath: consensusPathFor(tempDir));
      await storage.save(
        ConsensusSession(
          consensusId: 'cons-234',
          title: 'Caching session',
          prompt: 'Evaluate profile caching',
          participants: [
            ConsensusParticipant(
              agent: 'gemini',
              model: 'pro',
              stance: ConsensusStance.neutral,
            ),
          ],
          createdAt: DateTime.parse('2026-04-04T10:00:00Z'),
        ),
      );

      final result = await runCli([
        'consensus',
        '--inspect',
        'cons-234',
      ], environment);

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('consensus_id: cons-234'));
      expect(result.stdout, contains('title: Caching session'));
      expect(result.stdout, contains('participants: gemini:pro:neutral'));
    });

    test('--inspect missing exits non-zero', () async {
      final result = await runCli([
        'consensus',
        '--inspect',
        'missing',
      ], environment);

      expect(result.exitCode, equals(1));
      expect(result.stderr, contains('Consensus session not found: missing'));
    });

    test('--list with --inspect returns usage error', () async {
      final result = await runCli([
        'consensus',
        '--list',
        '--inspect',
        'cons-1',
      ], environment);

      expect(result.exitCode, equals(64));
      expect(
        result.stdout,
        contains('Cannot use --list and --inspect together'),
      );
    });

    test('--resume with --title returns usage error', () async {
      final result = await runCli([
        'consensus',
        '--resume',
        'cons-1',
        '--title',
        'Retry',
        'Follow up',
      ], environment);

      expect(result.exitCode, equals(64));
      expect(result.stdout, contains('Cannot use --title when resuming.'));
    });
  });

  group('compare and council CLI persistence', () {
    late Directory tempDir;
    late Map<String, String> environment;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cag_cli_persisted_');
      environment = buildAppEnvironment(tempDir);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('compare --list --json returns run summaries', () async {
      final storage = CompareStorage(storagePath: comparePathFor(tempDir));
      await storage.save(
        CompareRun(
          compareId: 'cmp_123',
          title: 'Compare run',
          prompt: 'Compare this',
          participants: [CompareParticipant(agent: 'gemini', model: 'pro')],
          results: [
            CompareParticipantResult(
              participant: CompareParticipant(
                agent: 'gemini',
                model: 'pro',
                sessionId: 's1',
              ),
              response: ParsedResponse(
                content: 'hello',
                metadata: {'session_id': 's1'},
              ),
            ),
          ],
          createdAt: DateTime.parse('2026-04-04T10:00:00Z'),
          updatedAt: DateTime.parse('2026-04-04T10:00:00Z'),
        ),
      );

      final result = await runCli(['compare', '--list', '--json'], environment);

      expect(result.exitCode, equals(0));
      final payload =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect((payload['runs'] as List), hasLength(1));
      expect((payload['runs'] as List).first['id'], equals('cmp_123'));
    });

    test('council --inspect --json returns stored run', () async {
      final storage = CouncilStorage(storagePath: councilPathFor(tempDir));
      await storage.save(
        CouncilRun(
          councilId: 'council_123',
          title: 'Council run',
          prompt: 'Discuss this',
          participants: [
            CouncilMember(agent: 'gemini', model: 'pro'),
            CouncilMember(agent: 'codex', model: 'gpt'),
          ],
          chairman: CouncilMember(agent: 'claude', model: 'sonnet'),
          answers: [
            CouncilParticipantResult(
              participant: CouncilMember(agent: 'gemini', model: 'pro'),
              response: ParsedResponse(content: 'answer 1'),
            ),
            CouncilParticipantResult(
              participant: CouncilMember(agent: 'codex', model: 'gpt'),
              response: ParsedResponse(content: 'answer 2'),
            ),
          ],
          reviews: [
            CouncilReviewResult(
              participant: CouncilMember(agent: 'gemini', model: 'pro'),
              response: ParsedResponse(content: 'review 1'),
            ),
            CouncilReviewResult(
              participant: CouncilMember(agent: 'codex', model: 'gpt'),
              response: ParsedResponse(content: 'review 2'),
            ),
          ],
          chairmanResult: CouncilChairmanResult(
            chairman: CouncilMember(agent: 'claude', model: 'sonnet'),
            response: ParsedResponse(content: 'summary'),
          ),
          createdAt: DateTime.parse('2026-04-04T10:00:00Z'),
          updatedAt: DateTime.parse('2026-04-04T10:00:00Z'),
        ),
      );

      final result = await runCli([
        'council',
        '--inspect',
        'council_123',
        '--json',
      ], environment);

      expect(result.exitCode, equals(0));
      final payload =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(payload['id'], equals('council_123'));
      expect(payload['title'], equals('Council run'));
    });

    test('compare --list with creation flags returns usage error', () async {
      final result = await runCli([
        'compare',
        '--list',
        '--title',
        'bad',
      ], environment);

      expect(result.exitCode, equals(64));
      expect(
        result.stdout,
        contains(
          'Cannot combine persisted run browsing with prompt or creation flags.',
        ),
      );
    });

    test('council --inspect with creation flags returns usage error', () async {
      final result = await runCli([
        'council',
        '--inspect',
        'council_1',
        '-c',
        'claude:sonnet',
      ], environment);

      expect(result.exitCode, equals(64));
      expect(
        result.stdout,
        contains(
          'Cannot combine persisted run browsing with prompt or creation flags.',
        ),
      );
    });
  });

  group('stdin prompt input', () {
    late Directory tempDir;
    late Map<String, String> environment;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cag_cli_stdin_');
      environment = buildAppEnvironment(tempDir);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('agent appends piped stdin to argument prompt', () async {
      final fakeCodex = await writeFakeCodexExecutable(tempDir);
      await writeCodexConfig(tempDir, fakeCodex.path);

      final result = await runCliWithStdin(
        ['codex', '-m', 'mini', 'review this'],
        environment,
        'diff --git a/file.dart b/file.dart\n+new line\n',
      );

      expect(result.exitCode, equals(0));
      final stdout = (result.stdout as String).replaceAll('\r\n', '\n');
      expect(stdout, contains('review this\n\ndiff --git'));
      expect(stdout, contains('+new line'));
    });
  });

  group('detect CLI', () {
    late Directory tempDir;
    late Map<String, String> environment;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cag_cli_detect_');
      environment = buildAppEnvironment(tempDir);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('detects antigravity and writes config enablement', () async {
      await writeFakeExecutable(tempDir, 'agy');
      environment['PATH'] = tempDir.path;
      if (Platform.isWindows) {
        environment['PATHEXT'] = '.cmd;.exe;.bat';
      }

      final result = await runCli(['detect'], environment);

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('  - antigravity: found'));

      final configFile = File(p.join(appDataDirFor(tempDir), 'config.json'));
      final config =
          jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
      final agents = config['agents'] as Map<String, dynamic>;
      final antigravity = agents['antigravity'] as Map<String, dynamic>;
      expect(antigravity['enabled'], isTrue);
    });
  });

  group('doctor CLI', () {
    late Directory tempDir;
    late Map<String, String> environment;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cag_cli_doctor_');
      environment = buildAppEnvironment(tempDir);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('missing config reports path without creating config', () async {
      final result = await runCli(['doctor'], environment);

      final configFile = File(p.join(appDataDirFor(tempDir), 'config.json'));
      expect(result.stdout, contains('Config: missing (${configFile.path})'));
      expect(await configFile.exists(), isFalse);
    });

    test('reports found executable and version for configured agent', () async {
      final fakeCodex = await writeVersionedFakeExecutable(
        tempDir,
        'fake-codex',
        'fake codex 1.2.3',
      );
      await writeAgentConfig(
        tempDir,
        disabledAgentConfig({
          'codex': {'enabled': true, 'executable': fakeCodex.path},
        }),
      );

      final result = await runCli(['doctor'], environment);

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('codex: enabled, found'));
      expect(result.stdout, contains('version: fake codex 1.2.3'));
    });

    test('enabled missing executable exits non-zero with hint', () async {
      await writeAgentConfig(
        tempDir,
        disabledAgentConfig({
          'codex': {'enabled': true, 'executable': 'missing-codex'},
        }),
      );

      final result = await runCli(['doctor'], environment);

      expect(result.exitCode, equals(1));
      expect(result.stdout, contains('codex: enabled, missing'));
      expect(
        result.stdout,
        contains('Install Codex CLI or set agents.codex.executable in config.'),
      );
    });

    test('disabled missing executable does not fail', () async {
      await writeAgentConfig(
        tempDir,
        disabledAgentConfig({
          'codex': {'enabled': false, 'executable': 'missing-codex'},
        }),
      );

      final result = await runCli(['doctor'], environment);

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('codex: disabled, disabled'));
      expect(result.stdout, isNot(contains('agents.codex.executable')));
    });

    test('--json returns documented diagnostic shape', () async {
      await writeAgentConfig(tempDir, disabledAgentConfig());

      final result = await runCli(['doctor', '--json'], environment);

      expect(result.exitCode, equals(0));
      final payload =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(payload['config'], containsPair('exists', true));
      expect(payload['config'], containsPair('valid', true));
      expect(payload['agents'], isA<List<dynamic>>());
      expect(payload['mcp'], containsPair('checked', false));
      expect(payload['summary'], containsPair('fail', 0));
    });

    test('invalid config fails without rewriting file', () async {
      final configFile = File(p.join(appDataDirFor(tempDir), 'config.json'));
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString('{"agents": {"unknown": {}}}\n');

      final result = await runCli(['doctor'], environment);

      expect(result.exitCode, equals(1));
      expect(result.stdout, contains('Config: invalid (${configFile.path})'));
      expect(
        await configFile.readAsString(),
        equals('{"agents": {"unknown": {}}}\n'),
      );
    });

    test('checks every known enabled agent', () async {
      final agents = <String, Map<String, Object?>>{};
      for (final name in AgentCatalog.names) {
        final fake = await writeVersionedFakeExecutable(
          tempDir,
          'fake-$name',
          '$name version',
        );
        agents[name] = {'enabled': true, 'executable': fake.path};
      }
      await writeAgentConfig(tempDir, agents);

      final result = await runCli(['doctor'], environment);

      expect(result.exitCode, equals(0));
      for (final name in AgentCatalog.names) {
        expect(result.stdout, contains('$name: enabled, found'));
        expect(result.stdout, contains('version: $name version'));
      }
    });

    test('lightweight diagnostics include MCP runtime fields', () async {
      final fakeCodex = await writeFakeExecutable(tempDir, 'fake-codex');
      await writeAgentConfig(
        tempDir,
        disabledAgentConfig({
          'codex': {
            'enabled': true,
            'executable': fakeCodex.path,
            'default_model': 'custom-codex',
            'models': [
              {'name': 'custom-codex', 'description': 'Custom Codex'},
            ],
          },
          'claude': {'enabled': true, 'executable': 'missing-claude'},
        }),
      );

      final report = await DoctorService(
        configPath: p.join(appDataDirFor(tempDir), 'config.json'),
      ).inspect(includeVersions: false);

      final codex = report.agents.singleWhere((agent) {
        return agent.name == 'codex';
      });
      expect(codex.enabled, isTrue);
      expect(codex.available, isTrue);
      expect(codex.defaultModel, equals('custom-codex'));
      expect(codex.modelCount, equals(4));
      expect(codex.authStatus, equals('not_checked'));
      expect(codex.executionMode, equals('direct'));
      expect(codex.version, isNull);

      final claude = report.agents.singleWhere((agent) {
        return agent.name == 'claude';
      });
      expect(claude.enabled, isTrue);
      expect(claude.available, isFalse);
      expect(claude.hint, contains('agents.claude.executable'));
    });

    test('lightweight diagnostics do not probe executable versions', () async {
      final marker = File(p.join(tempDir.path, 'version-called.txt'));
      final fakeCodex = await writeTrackedVersionExecutable(
        tempDir,
        'tracked-codex',
        marker,
      );
      await writeAgentConfig(
        tempDir,
        disabledAgentConfig({
          'codex': {'enabled': true, 'executable': fakeCodex.path},
        }),
      );

      final report = await DoctorService(
        configPath: p.join(appDataDirFor(tempDir), 'config.json'),
      ).inspect(includeVersions: false);

      final codex = report.agents.singleWhere((agent) {
        return agent.name == 'codex';
      });
      expect(codex.available, isTrue);
      expect(codex.version, isNull);
      expect(await marker.exists(), isFalse);
    });
  });
}

Future<ProcessResult> runCli(
  List<String> args,
  Map<String, String> environment,
) {
  return Process.run(
    Platform.resolvedExecutable,
    ['run', 'bin/cag.dart', ...args],
    workingDirectory: Directory.current.path,
    environment: environment,
  );
}

Future<ProcessResult> runCliWithStdin(
  List<String> args,
  Map<String, String> environment,
  String input,
) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', 'bin/cag.dart', ...args],
    workingDirectory: Directory.current.path,
    environment: environment,
  );
  process.stdin.write(input);
  await process.stdin.close();

  final stdout = await process.stdout.transform(utf8.decoder).join();
  final stderr = await process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode;

  return ProcessResult(process.pid, exitCode, stdout, stderr);
}

Map<String, String> buildAppEnvironment(Directory tempDir) {
  final environment = <String, String>{...Platform.environment};
  if (Platform.isWindows) {
    environment['APPDATA'] = tempDir.path;
    environment['LOCALAPPDATA'] = tempDir.path;
    environment['USERPROFILE'] = tempDir.path;
    return environment;
  }
  if (Platform.isMacOS) {
    environment['HOME'] = tempDir.path;
    return environment;
  }
  environment['HOME'] = tempDir.path;
  environment['XDG_DATA_HOME'] = tempDir.path;
  return environment;
}

String appDataDirFor(Directory tempDir) {
  if (Platform.isMacOS) {
    return p.join(tempDir.path, '.cag');
  }
  return p.join(tempDir.path, 'cag');
}

String consensusPathFor(Directory tempDir) {
  return p.join(appDataDirFor(tempDir), 'consensus.jsonl');
}

String comparePathFor(Directory tempDir) {
  return p.join(appDataDirFor(tempDir), 'compare.jsonl');
}

String councilPathFor(Directory tempDir) {
  return p.join(appDataDirFor(tempDir), 'council.jsonl');
}

Future<File> writeFakeCodexExecutable(Directory tempDir) async {
  final file = File(p.join(tempDir.path, 'fake_codex.dart'));
  await file.writeAsString('''
import 'dart:convert';

void main(List<String> args) {
  final prompt = args.isEmpty ? '' : args.last;
  print(jsonEncode({'type': 'thread.started', 'thread_id': 'fake-thread'}));
  print(jsonEncode({
    'type': 'item.completed',
    'item': {'type': 'agent_message', 'text': prompt},
  }));
}
''');
  return file;
}

Future<File> writeFakeExecutable(Directory tempDir, String name) async {
  final executableName = Platform.isWindows ? '$name.cmd' : name;
  final file = File(p.join(tempDir.path, executableName));
  final body = Platform.isWindows ? '@echo off\r\n' : '#!/bin/sh\n';
  await file.writeAsString(body);
  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', file.path]);
  }
  return file;
}

Future<File> writeVersionedFakeExecutable(
  Directory tempDir,
  String name,
  String version,
) async {
  final executableName = Platform.isWindows ? '$name.cmd' : name;
  final file = File(p.join(tempDir.path, executableName));
  final body = Platform.isWindows
      ? '@echo off\r\nif "%1"=="--version" echo $version\r\n'
      : '#!/bin/sh\nif [ "\$1" = "--version" ]; then echo "$version"; fi\n';
  await file.writeAsString(body);
  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', file.path]);
  }
  return file;
}

Future<File> writeTrackedVersionExecutable(
  Directory tempDir,
  String name,
  File marker,
) async {
  final executableName = Platform.isWindows ? '$name.cmd' : name;
  final file = File(p.join(tempDir.path, executableName));
  final body = Platform.isWindows
      ? '@echo off\r\necho called>>"${marker.path}"\r\necho tracked version\r\n'
      : '#!/bin/sh\necho called >> "${marker.path}"\necho "tracked version"\n';
  await file.writeAsString(body);
  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', file.path]);
  }
  return file;
}

Future<void> writeAgentConfig(
  Directory tempDir,
  Map<String, Map<String, Object?>> agents,
) async {
  final file = File(p.join(appDataDirFor(tempDir), 'config.json'));
  await file.parent.create(recursive: true);
  await file.writeAsString('${jsonEncode({'agents': agents})}\n');
}

Map<String, Map<String, Object?>> disabledAgentConfig([
  Map<String, Map<String, Object?>> overrides = const {},
]) {
  return {
    for (final name in AgentCatalog.names)
      name: {'enabled': false, ...?overrides[name]},
  };
}

Future<void> writeCodexConfig(Directory tempDir, String fakeCodexPath) async {
  final file = File(p.join(appDataDirFor(tempDir), 'config.json'));
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${jsonEncode({
      'agents': {
        'codex': {
          'executable': Platform.resolvedExecutable,
          'additional_args': [fakeCodexPath],
        },
      },
    })}\n',
  );
}
