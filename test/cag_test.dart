import 'dart:convert';
import 'dart:io';

import 'package:cag/cag.dart';
import 'package:cag/src/utils/app_paths.dart';
import 'package:test/test.dart';

void main() {
  group('GeminiParser', () {
    final parser = GeminiParser();

    test('parse successfully parses valid JSON output', () {
      final mockResponse = {
        'response': 'Hello from Gemini',
        'session_id': 'gemini-session',
        'stats': {
          'models': {
            'gemini-1.5-pro': {
              'tokens': {'total': 15},
              'api': {'totalLatencyMs': 150},
            },
          },
        },
      };

      final result = parser.parse(stdout: jsonEncode(mockResponse), stderr: '');

      expect(result.content, equals('Hello from Gemini'));
      expect(result.metadata['session_id'], equals('gemini-session'));
      expect(result.metadata['model_used'], equals('gemini-1.5-pro'));
    });

    test('throws ParserException on invalid JSON', () {
      expect(() => parser.parse(stdout: 'not json', stderr: ''), throwsA(isA<ParserException>()));
    });
  });

  group('ClaudeParser', () {
    final parser = ClaudeParser();

    test('parse successfully parses valid JSON list output', () {
      final mockResponse = [
        {'type': 'session_started', 'session_id': 'claude-session'},
        {
          'type': 'result',
          'result': 'Hello from Claude',
          'duration_ms': 200,
          'modelUsage': {'claude-3-5-sonnet': {}},
        },
      ];

      final result = parser.parse(stdout: jsonEncode(mockResponse), stderr: '');

      expect(result.content, equals('Hello from Claude'));
      expect(result.metadata['session_id'], equals('claude-session'));
      expect(result.metadata['model_used'], equals('claude-3-5-sonnet'));
      expect(result.metadata['duration_ms'], equals(200));
    });

    test('parse extracts content from assistant message if result field is missing', () {
      final mockResponse = [
        {
          'type': 'assistant',
          'message': {
            'content': [
              {'type': 'text', 'text': 'Content from message'},
            ],
          },
        },
        {'type': 'result', 'is_error': false},
      ];

      final result = parser.parse(stdout: jsonEncode(mockResponse), stderr: '');
      expect(result.content, equals('Content from message'));
    });

    test('throws ParserException on empty stdout', () {
      expect(() => parser.parse(stdout: '', stderr: ''), throwsA(isA<ParserException>()));
    });
  });

  group('CodexParser', () {
    final parser = CodexParser();

    test('parse successfully parses valid JSONL output', () {
      final lines = [
        jsonEncode({'type': 'thread.started', 'thread_id': 'codex-thread'}),
        jsonEncode({
          'type': 'item.completed',
          'item': {'type': 'agent_message', 'text': 'Hello from Codex'},
        }),
        jsonEncode({
          'type': 'turn.completed',
          'usage': {'total_tokens': 20},
        }),
      ];

      final result = parser.parse(stdout: lines.join('\n'), stderr: '');

      expect(result.content, equals('Hello from Codex'));
      expect(result.metadata['session_id'], equals('codex-thread'));
      expect(result.metadata['usage']['total_tokens'], equals(20));
    });

    test('throws ParserException if no agent message found', () {
      final lines = [
        jsonEncode({'type': 'thread.started', 'thread_id': 'codex-thread'}),
      ];
      expect(() => parser.parse(stdout: lines.join('\n'), stderr: ''), throwsA(isA<ParserException>()));
    });

    test('returns error content when only error events are present', () {
      final lines = [
        jsonEncode({'type': 'error', 'message': 'Codex failed to execute'}),
      ];

      final result = parser.parse(stdout: lines.join('\n'), stderr: '');

      expect(result.content, equals('Codex failed to execute'));
      expect(result.metadata['errors'], equals(['Codex failed to execute']));
    });
  });

  group('CursorParser', () {
    final parser = CursorParser();

    test('parse successfully parses valid JSON output', () {
      final mockResponse = {
        'type': 'result',
        'subtype': 'success',
        'is_error': false,
        'duration_ms': 1200,
        'duration_api_ms': 1150,
        'result': '\nHello from Cursor',
        'session_id': 'cursor-session',
        'request_id': 'cursor-request',
      };

      final result = parser.parse(stdout: jsonEncode(mockResponse), stderr: '');

      expect(result.content, equals('Hello from Cursor'));
      expect(result.metadata['session_id'], equals('cursor-session'));
      expect(result.metadata['request_id'], equals('cursor-request'));
      expect(result.metadata['duration_ms'], equals(1200));
    });

    test('throws ParserException on empty stdout', () {
      expect(() => parser.parse(stdout: '', stderr: ''), throwsA(isA<ParserException>()));
    });
  });

  group('AgentModelRegistry', () {
    test('resolves model aliases to canonical names', () {
      expect(AgentModelRegistry.findModel('gemini', 'pro')?.name, equals('gemini-3-pro-preview'));
      expect(AgentModelRegistry.findModel('gemini', 'flash')?.name, equals('gemini-3-flash-preview'));
      expect(AgentModelRegistry.findModel('codex', 'gpt')?.name, equals('gpt-5.2'));
      expect(AgentModelRegistry.findModel('codex', 'mini')?.name, equals('gpt-5.1-codex-mini'));
      expect(AgentModelRegistry.findModel('cursor', 'auto')?.name, equals('auto'));
    });
  });

  group('ConsensusParticipant', () {
    test('parse correctly parses valid input', () {
      final p = ConsensusParticipant.parse('gemini:pro:for');
      expect(p.agent, equals('gemini'));
      expect(p.model, equals('pro'));
      expect(p.stance, equals(ConsensusStance.forProposal));
    });

    test('parse throws ArgumentError on invalid format', () {
      expect(() => ConsensusParticipant.parse('gemini:pro'), throwsArgumentError);
      expect(() => ConsensusParticipant.parse('gemini:pro:for:extra'), throwsArgumentError);
    });

    test('parse throws ArgumentError on invalid agent', () {
      expect(() => ConsensusParticipant.parse('unknown:pro:for'), throwsArgumentError);
    });

    test('parse throws ArgumentError on invalid stance', () {
      expect(() => ConsensusParticipant.parse('gemini:pro:unknown'), throwsArgumentError);
    });
  });

  group('AgentConfig', () {
    test('AgentConfig creates with default values', () {
      const config = AgentConfig(name: 'test', executable: 'test-cli', parser: 'json');

      expect(config.name, equals('test'));

      expect(config.timeoutSeconds, equals(1800));

      expect(config.additionalArgs, isEmpty);
    });
  });

  group('PrimeGenerator', () {
    test('generate produces markdown with command info', () {
      const generator = PrimeGenerator();

      final commands = [
        const CommandMetadata(
          name: 'test-agent',

          description: 'A test agent',

          models: [ModelConfig(name: 'm1', description: 'Model 1', isDefault: true)],
        ),
      ];

      final output = generator.generate(commands);

      expect(output, contains('# CLI Agents'));

      expect(output, contains('### test-agent'));

      expect(output, contains('A test agent'));

      expect(output, contains('`m1` ⭐'));
    });
  });

  group('ConsensusStorage', () {
    late Directory tempDir;

    late String storagePath;

    late ConsensusStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cag_test_');

      storagePath = '${tempDir.path}/test_consensus.jsonl';

      storage = ConsensusStorage(storagePath: storagePath);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('save and loadAll', () async {
      final session = ConsensusSession(consensusId: 'c1', prompt: 'test prompt', participants: [], createdAt: DateTime.now());

      await storage.save(session);

      final loaded = await storage.loadAll();

      expect(loaded, hasLength(1));

      expect(loaded.first.consensusId, equals('c1'));

      expect(loaded.first.prompt, equals('test prompt'));
    });

    test('load by ID', () async {
      final session = ConsensusSession(consensusId: 'c2', prompt: 'test prompt 2', participants: [], createdAt: DateTime.now());

      await storage.save(session);

      final loaded = await storage.load('c2');

      expect(loaded, isNotNull);

      expect(loaded?.consensusId, equals('c2'));
    });

    test('delete session', () async {
      final session = ConsensusSession(consensusId: 'c3', prompt: 'test prompt 3', participants: [], createdAt: DateTime.now());

      await storage.save(session);

      await storage.delete('c3');

      final loaded = await storage.loadAll();

      expect(loaded, isEmpty);
    });
  });

  group('AppPaths', () {
    test('appDataDir uses platform-appropriate location', () {
      final dir = AppPaths.appDataDir();
      expect(dir, isNotEmpty);

      if (Platform.isMacOS) {
        expect(dir, endsWith('/.cag'));
      } else if (Platform.isLinux) {
        expect(dir, endsWith('/cag'));
      } else if (Platform.isWindows) {
        expect(dir.toLowerCase(), contains('cag'));
      }
    });

    test('consensusPath ends with consensus.jsonl', () {
      final path = AppPaths.consensusPath();
      expect(path, endsWith('${Platform.pathSeparator}consensus.jsonl'));
    });
  });
}
