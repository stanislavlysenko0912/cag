import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cag/cag.dart';
import 'package:cag/src/utils/app_paths.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import '../bin/commands/mcp_agent_tasks.dart';

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
      expect(
        () => parser.parse(stdout: 'not json', stderr: ''),
        throwsA(isA<ParserException>()),
      );
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

    test(
      'parse extracts content from assistant message if result field is missing',
      () {
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

        final result = parser.parse(
          stdout: jsonEncode(mockResponse),
          stderr: '',
        );
        expect(result.content, equals('Content from message'));
      },
    );

    test('throws ParserException on empty stdout', () {
      expect(
        () => parser.parse(stdout: '', stderr: ''),
        throwsA(isA<ParserException>()),
      );
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
      expect(
        () => parser.parse(stdout: lines.join('\n'), stderr: ''),
        throwsA(isA<ParserException>()),
      );
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
      expect(
        () => parser.parse(stdout: '', stderr: ''),
        throwsA(isA<ParserException>()),
      );
    });
  });

  group('AntigravityParser', () {
    final parser = AntigravityParser();

    test('parse returns plain print-mode output', () {
      final result = parser.parse(
        stdout: 'Hello from Antigravity\n',
        stderr: '',
      );

      expect(result.content, equals('Hello from Antigravity'));
    });

    test('parse extracts conversation resume command', () {
      final result = parser.parse(
        stdout: 'Done\nResume with: agy --conversation abc-123',
        stderr: '',
      );

      expect(result.metadata['session_id'], equals('abc-123'));
    });
  });

  group('AgentModelRegistry', () {
    test('resolves model aliases to canonical names', () {
      expect(
        AgentModelRegistry.findModel('claude', 'sonnet')?.name,
        equals('claude-sonnet-4-6'),
      );
      expect(
        AgentModelRegistry.findModel('claude', 'haiku')?.name,
        equals('claude-haiku-4-5'),
      );
      expect(
        AgentModelRegistry.findModel('gemini', 'pro')?.name,
        equals('gemini-3.1-pro-preview'),
      );
      expect(
        AgentModelRegistry.findModel('gemini', 'flash')?.name,
        equals('gemini-3-flash-preview'),
      );
      expect(
        AgentModelRegistry.findModel('codex', 'gpt')?.name,
        equals('gpt-5.5'),
      );
      expect(
        AgentModelRegistry.findModel('codex', 'mini')?.name,
        equals('gpt-5.5-mini'),
      );
      expect(AgentModelRegistry.findModel('cursor', 'auto'), isNull);
      expect(
        AgentModelRegistry.findModel('antigravity', 'current')?.name,
        equals('configured'),
      );
      expect(
        AgentModelRegistry.findModel('antigravity', 'flash-low')?.name,
        equals('gemini-3-5-flash-low'),
      );
      expect(
        AgentModelRegistry.findModel('antigravity', 'sonnet')?.name,
        equals('claude-sonnet-4-6-thinking'),
      );
      expect(
        AgentModelRegistry.findModel(
          'antigravity',
          'gemini-3-5-flash-medium',
        )?.name,
        equals('gemini-3-5-flash-medium'),
      );
      expect(
        AgentModelRegistry.findModel(
          'antigravity',
          'claude-sonnet-4-6-thinking',
        )?.name,
        equals('claude-sonnet-4-6-thinking'),
      );
      expect(
        AgentModelRegistry.findModel(
          'antigravity',
          'gemini-3-5-flash-medium',
        )?.resolvedModel,
        equals('Gemini 3.5 Flash (Medium)'),
      );
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
      expect(
        () => ConsensusParticipant.parse('gemini:pro'),
        throwsArgumentError,
      );
      expect(
        () => ConsensusParticipant.parse('gemini:pro:for:extra'),
        throwsArgumentError,
      );
    });

    test('parse throws ArgumentError on invalid agent', () {
      expect(
        () => ConsensusParticipant.parse('unknown:pro:for'),
        throwsArgumentError,
      );
    });

    test('parse throws ArgumentError on invalid stance', () {
      expect(
        () => ConsensusParticipant.parse('gemini:pro:unknown'),
        throwsArgumentError,
      );
    });

    test('parse normalizes uppercase agent input', () {
      final participant = ConsensusParticipant.parse('GEMINI:pro:neutral');
      expect(participant.agent, equals('gemini'));
    });

    test('parse throws ArgumentError when no agents are enabled', () {
      expect(
        () => ConsensusParticipant.parse(
          'gemini:pro:for',
          allowedAgents: const [],
        ),
        throwsArgumentError,
      );
    });
  });

  group('AgentConfig', () {
    test('AgentConfig creates with default values', () {
      const config = AgentConfig(
        name: 'test',
        executable: 'test-cli',
        parser: 'json',
      );

      expect(config.name, equals('test'));

      expect(config.hardTimeoutSeconds, equals(1800));
      expect(config.idleTimeoutSeconds, equals(900));

      expect(config.additionalArgs, isEmpty);
    });

    test('ModelConfig preserves model override', () {
      final config = ModelConfig.fromJson({
        'name': 'gemini-3-5-flash-medium',
        'model': 'Gemini 3.5 Flash (Medium)',
        'description': 'Medium-tier Gemini model.',
        'aliases': ['flash'],
      });

      expect(config.name, equals('gemini-3-5-flash-medium'));
      expect(config.resolvedModel, equals('Gemini 3.5 Flash (Medium)'));
      expect(config.matches('flash'), isTrue);
      expect(config.toJson()['model'], equals('Gemini 3.5 Flash (Medium)'));
    });
  });

  group('CompareParticipant', () {
    test('parse correctly parses valid input', () {
      final participant = CompareParticipant.parse('gemini:pro');
      expect(participant.agent, equals('gemini'));
      expect(participant.model, equals('pro'));
    });

    test('parse throws ArgumentError on invalid format', () {
      expect(() => CompareParticipant.parse('gemini'), throwsArgumentError);
      expect(
        () => CompareParticipant.parse('gemini:pro:extra'),
        throwsArgumentError,
      );
    });

    test('parse throws ArgumentError on invalid agent', () {
      expect(
        () => CompareParticipant.parse('unknown:pro'),
        throwsArgumentError,
      );
    });

    test('parse normalizes uppercase agent input', () {
      final participant = CompareParticipant.parse('GEMINI:pro');
      expect(participant.agent, equals('gemini'));
    });

    test('parse throws ArgumentError when no agents are enabled', () {
      expect(
        () => CompareParticipant.parse('gemini:pro', allowedAgents: const []),
        throwsArgumentError,
      );
    });
  });

  group('CouncilMember', () {
    test('parse throws ArgumentError when no agents are enabled', () {
      expect(
        () => CouncilMember.parse('gemini:pro', allowedAgents: const []),
        throwsArgumentError,
      );
    });
  });

  group('CompareTitle', () {
    test('keeps short prompts unchanged after normalization', () {
      final title = buildCompareTitle('  compare   this prompt  ');
      expect(title, equals('compare this prompt'));
    });

    test('truncates long prompts with ellipsis', () {
      final title = buildCompareTitle('a' * 90);
      expect(title.length, equals(80));
      expect(title.endsWith('...'), isTrue);
    });
  });

  group('CLIRunner', () {
    test('run executes a basic command', () async {
      final runner = CLIRunner();
      final result = Platform.isWindows
          ? await runner.run(executable: 'cmd', args: ['/c', 'echo hello'])
          : await runner.run(executable: 'echo', args: ['hello']);

      expect(result.exitCode, equals(0));
      expect(result.stdout.trim(), equals('hello'));
    });

    test(
      'run executes a shell command when invoked via shell executable',
      () async {
        final runner = CLIRunner();
        final result = Platform.isWindows
            ? await runner.run(
                executable: 'cmd',
                args: ['/c', 'echo prefix && echo hello'],
              )
            : await runner.run(
                executable: '/bin/sh',
                args: ['-c', 'echo prefix && echo hello'],
              );

        expect(result.exitCode, equals(0));
        expect(result.stdout, contains('prefix'));
        expect(result.stdout, contains('hello'));
      },
    );

    test('runShellCommand appends and escapes shell arguments', () async {
      if (Platform.isWindows) return;

      final runner = CLIRunner();
      final result = await runner.runShellCommand(
        commandPrefix: 'printf "%s"',
        args: ["hello world & it's fine"],
      );

      expect(result.exitCode, equals(0));
      expect(result.stdout, equals("hello world & it's fine"));
    });

    test('run captures stdout larger than legacy pipe buffer limits', () async {
      final runner = CLIRunner();
      final result = Platform.isWindows
          ? await runner.run(
              executable: 'python',
              args: ['-c', 'print("x" * 250000)'],
            )
          : await runner.run(
              executable: '/bin/sh',
              args: ['-c', r'python3 -c "print(\"x\" * 250000)"'],
            );

      expect(result.exitCode, equals(0));
      expect(result.stdout.length, greaterThan(200000));
    });

    test('run decodes malformed UTF-8 output', () async {
      final runner = CLIRunner();
      final result = Platform.isWindows
          ? await runner.run(
              executable: 'python',
              args: ['-c', 'import sys; sys.stdout.buffer.write(bytes([255]))'],
            )
          : await runner.run(
              executable: '/bin/sh',
              args: [
                '-c',
                r'python3 -c "import sys; sys.stdout.buffer.write(bytes([255]))"',
              ],
            );

      expect(result.exitCode, equals(0));
      expect(result.stdout, isNotEmpty);
    });

    test('run does not create retained capture files by default', () async {
      final runner = CLIRunner();
      final before = Directory.systemTemp
          .listSync()
          .whereType<Directory>()
          .where((dir) => dir.path.contains('cag_cli_'))
          .length;

      await runner.run(executable: 'echo', args: ['cleanup-check']);

      final after = Directory.systemTemp
          .listSync()
          .whereType<Directory>()
          .where((dir) => dir.path.contains('cag_cli_'))
          .length;
      expect(after, lessThanOrEqualTo(before));
    });
  });

  group('PrimeGenerator', () {
    test('generate produces markdown with command info', () {
      const generator = PrimeGenerator();

      final commands = [
        const CommandMetadata(
          name: 'test-agent',
          description: 'A test agent',
          models: [
            ModelConfig(name: 'm1', description: 'Model 1', isDefault: true),
          ],
        ),
      ];

      final output = generator.generate(
        commands,
        agentConfigs: {
          'test-agent': const AgentConfig(
            name: 'test-agent',
            executable: 'test',
            parser: 'test',
          ),
        },
      );

      expect(output, contains('# CLI Agents'));

      expect(output, contains('### test-agent'));

      expect(output, contains('A test agent'));

      expect(output, contains('`m1` ⭐'));
    });

    test('generate includes compare section when compare command exists', () {
      const generator = PrimeGenerator();

      final commands = [
        const CommandMetadata(
          name: 'claude',
          description: 'Claude agent',
          models: [
            ModelConfig(
              name: 'sonnet',
              description: 'Default',
              isDefault: true,
            ),
          ],
        ),
        const CommandMetadata(name: 'compare', description: 'Compare command'),
      ];

      final output = generator.generate(
        commands,
        agentConfigs: {
          'claude': const AgentConfig(
            name: 'claude',
            executable: 'claude',
            parser: 'claude',
          ),
        },
      );

      expect(output, contains('## Compare'));
      expect(output, contains('cag compare --list'));
    });

    test('generate reflects custom models from config', () {
      const generator = PrimeGenerator();

      final commands = [
        const CommandMetadata(
          name: 'claude',
          description: 'Claude agent',
          models: [
            ModelConfig(name: 'sonnet', description: 'Base', isDefault: true),
          ],
        ),
      ];

      final output = generator.generate(
        commands,
        agentConfigs: {
          'claude': const AgentConfig(
            name: 'claude',
            executable: 'claude',
            parser: 'claude',
            availableModels: [
              ModelConfig(
                name: 'custom-model',
                description: 'Custom model',
                isDefault: true,
              ),
            ],
          ),
        },
      );

      expect(output, contains('### claude'));
      expect(output, contains('`custom-model` ⭐'));
      expect(output, isNot(contains('`sonnet`')));
    });

    test('generate explains single-agent model syntax explicitly', () {
      const generator = PrimeGenerator();

      final commands = [
        const CommandMetadata(
          name: 'codex',
          description: 'Codex agent',
          models: [
            ModelConfig(
              name: 'gpt-5.5',
              description: 'Default',
              isDefault: true,
            ),
            ModelConfig(name: 'gpt-5.3-codex', description: 'Code model'),
          ],
        ),
        const CommandMetadata(
          name: 'claude',
          description: 'Claude agent',
          models: [
            ModelConfig(
              name: 'claude-sonnet-4-6',
              description: 'Default',
              isDefault: true,
            ),
          ],
        ),
        const CommandMetadata(name: 'compare', description: 'Compare command'),
      ];

      final output = generator.generate(
        commands,
        agentConfigs: {
          'codex': const AgentConfig(
            name: 'codex',
            executable: 'codex',
            parser: 'codex',
          ),
          'claude': const AgentConfig(
            name: 'claude',
            executable: 'claude',
            parser: 'claude',
          ),
        },
      );

      expect(output, contains('## Command Syntax'));
      expect(output, contains('cag codex -m gpt-5.5 "Review this approach"'));
      expect(
        output,
        contains(
          'cag compare -a "codex:gpt-5.5" -a "claude:claude-sonnet-4-6" "Compare options"',
        ),
      );
      expect(
        output,
        contains('Wrong: cag codex:gpt-5.5 "Review this approach"'),
      );
    });

    test('generate warns against retrying slow strong models', () {
      const generator = PrimeGenerator();

      final commands = [
        const CommandMetadata(
          name: 'codex',
          description: 'Codex agent',
          models: [
            ModelConfig(
              name: 'gpt-5.5',
              description: 'Default',
              isDefault: true,
            ),
          ],
        ),
      ];

      final output = generator.generate(
        commands,
        agentConfigs: {
          'codex': const AgentConfig(
            name: 'codex',
            executable: 'codex',
            parser: 'codex',
          ),
        },
      );

      expect(
        output,
        contains(
          'Stronger models can take noticeably longer to answer; do not resend the same request just because the response is slow',
        ),
      );
    });

    test('generate explains that workspace is shared across agents', () {
      const generator = PrimeGenerator();

      final commands = [
        const CommandMetadata(
          name: 'codex',
          description: 'Codex agent',
          models: [
            ModelConfig(
              name: 'gpt-5.5-mini',
              description: 'Fast',
              isDefault: true,
            ),
          ],
        ),
      ];

      final output = generator.generate(
        commands,
        agentConfigs: {
          'codex': const AgentConfig(
            name: 'codex',
            executable: 'codex',
            parser: 'codex',
          ),
        },
      );

      expect(
        output,
        contains(
          'All agents start in the same current working directory (`cwd`) as you and have direct file access to that workspace',
        ),
      );
      expect(
        output,
        contains(
          'Treat the workspace as shared: reference file paths and ask the agent to inspect files directly instead of retelling repository structure or pasting large file contents.',
        ),
      );
    });

    test('generate explains when to prefer native tools over CAG', () {
      const generator = PrimeGenerator();

      final commands = [
        const CommandMetadata(
          name: 'codex',
          description: 'Codex agent',
          models: [
            ModelConfig(
              name: 'gpt-5.5-mini',
              description: 'Fast',
              isDefault: true,
            ),
          ],
        ),
      ];

      final output = generator.generate(
        commands,
        agentConfigs: {
          'codex': const AgentConfig(
            name: 'codex',
            executable: 'codex',
            parser: 'codex',
          ),
        },
      );

      expect(
        output,
        contains(
          'Use CAG only when the user asks for CAG or a specific CAG agent/model, or when external independent judgment or cross-agent comparison would materially improve the work.',
        ),
      );
      expect(
        output,
        contains(
          'Prefer your own native tools, subagents, or direct model tools for ordinary delegation and simple same-family model calls.',
        ),
      );
    });

    test('generate defaults to multi-turn dialogue instead of one-shot', () {
      const generator = PrimeGenerator();

      final commands = [
        const CommandMetadata(
          name: 'codex',
          description: 'Codex agent',
          models: [
            ModelConfig(
              name: 'gpt-5.5-mini',
              description: 'Fast',
              isDefault: true,
            ),
          ],
        ),
      ];

      final output = generator.generate(
        commands,
        agentConfigs: {
          'codex': const AgentConfig(
            name: 'codex',
            executable: 'codex',
            parser: 'codex',
          ),
        },
      );

      expect(
        output,
        contains(
          'After the first useful answer, always continue with at least 2 follow-up rounds (pushback, refinement, deeper questions) before presenting results to the user',
        ),
      );
      expect(
        output,
        contains(
          'Treat `session_id` as the default way to deepen the discussion, not just a technical detail for optional follow-ups.',
        ),
      );
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
      final session = ConsensusSession(
        consensusId: 'c1',
        prompt: 'test prompt',
        participants: [],
        createdAt: DateTime.now(),
      );

      await storage.save(session);

      final loaded = await storage.loadAll();

      expect(loaded, hasLength(1));

      expect(loaded.first.consensusId, equals('c1'));

      expect(loaded.first.prompt, equals('test prompt'));
    });

    test('load by ID', () async {
      final session = ConsensusSession(
        consensusId: 'c2',
        prompt: 'test prompt 2',
        participants: [],
        createdAt: DateTime.now(),
      );

      await storage.save(session);

      final loaded = await storage.load('c2');

      expect(loaded, isNotNull);

      expect(loaded?.consensusId, equals('c2'));
    });

    test('delete session', () async {
      final session = ConsensusSession(
        consensusId: 'c3',
        prompt: 'test prompt 3',
        participants: [],
        createdAt: DateTime.now(),
      );

      await storage.save(session);

      await storage.delete('c3');

      final loaded = await storage.loadAll();

      expect(loaded, isEmpty);
    });
  });

  group('CompareStorage', () {
    late Directory tempDir;
    late String storagePath;
    late CompareStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cag_compare_test_');
      storagePath = '${tempDir.path}/test_compare.jsonl';
      storage = CompareStorage(storagePath: storagePath);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('save and loadAll', () async {
      final run = CompareRun(
        compareId: 'cmp_1',
        title: 'Compare run',
        prompt: 'test prompt',
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
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await storage.save(run);

      final loaded = await storage.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.first.compareId, equals('cmp_1'));
      expect(loaded.first.title, equals('Compare run'));
    });

    test('load by ID', () async {
      final run = CompareRun(
        compareId: 'cmp_2',
        title: 'Compare run 2',
        prompt: 'prompt',
        participants: const [],
        results: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await storage.save(run);

      final loaded = await storage.load('cmp_2');
      expect(loaded, isNotNull);
      expect(loaded?.compareId, equals('cmp_2'));
    });

    test('loadAll returns empty list for missing file', () async {
      final loaded = await storage.loadAll();
      expect(loaded, isEmpty);
    });

    test('loadAll returns empty list for empty file', () async {
      await File(storagePath).writeAsString('');
      final loaded = await storage.loadAll();
      expect(loaded, isEmpty);
    });

    test('save overwrites existing run by id', () async {
      final original = CompareRun(
        compareId: 'cmp_same',
        title: 'Original title',
        prompt: 'prompt',
        participants: const [],
        results: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final updated = CompareRun(
        compareId: 'cmp_same',
        title: 'Updated title',
        prompt: 'prompt',
        participants: const [],
        results: const [],
        createdAt: original.createdAt,
        updatedAt: original.updatedAt,
      );

      await storage.save(original);
      await storage.save(updated);

      final loaded = await storage.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.first.title, equals('Updated title'));
    });
  });

  group('CompareRunner', () {
    late Directory tempDir;
    late CompareStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cag_compare_runner_');
      storage = CompareStorage(storagePath: '${tempDir.path}/compare.jsonl');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('run saves successful results with session IDs', () async {
      final runner = CompareRunner(
        storage: storage,
        geminiAgent: _FakeGeminiAgent(
          response: ParsedResponse(
            content: 'Gemini answer',
            metadata: {'session_id': 'gemini-session'},
          ),
        ),
        codexAgent: _FakeCodexAgent(
          response: ParsedResponse(
            content: 'Codex answer',
            metadata: {'session_id': 'codex-session'},
          ),
        ),
      );

      final run = await runner.run(
        prompt: 'Compare this',
        title: 'Compare this',
        participants: [
          CompareParticipant(agent: 'gemini', model: 'pro'),
          CompareParticipant(agent: 'codex', model: 'gpt'),
        ],
      );

      expect(run.compareId, startsWith('cmp_'));
      expect(run.successCount, equals(2));
      expect(run.results.first.participant.sessionId, equals('gemini-session'));

      final saved = await storage.load(run.compareId);
      expect(saved, isNotNull);
      expect(saved?.results.length, equals(2));
    });

    test('run keeps partial failure without throwing', () async {
      final runner = CompareRunner(
        storage: storage,
        geminiAgent: _FakeGeminiAgent(
          response: ParsedResponse(
            content: 'Gemini answer',
            metadata: {'session_id': 'gemini-session'},
          ),
        ),
        codexAgent: _FakeCodexAgent(error: Exception('codex failed')),
      );

      final run = await runner.run(
        prompt: 'Compare this',
        title: 'Compare this',
        participants: [
          CompareParticipant(agent: 'gemini', model: 'pro'),
          CompareParticipant(agent: 'codex', model: 'gpt'),
        ],
      );

      expect(run.status, equals('partial_failure'));
      expect(run.successCount, equals(1));
      expect(run.failureCount, equals(1));
      expect(run.results.last.failure?.message, contains('codex failed'));
    });
  });

  group('CouncilStorage', () {
    late Directory tempDir;
    late String storagePath;
    late CouncilStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cag_council_test_');
      storagePath = '${tempDir.path}/test_council.jsonl';
      storage = CouncilStorage(storagePath: storagePath);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('save and loadAll', () async {
      final run = _buildCouncilRun(councilId: 'council_1');

      await storage.save(run);

      final loaded = await storage.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.first.councilId, equals('council_1'));
      expect(loaded.first.answers.first.participant.sessionId, equals('s1'));
    });

    test('load by ID', () async {
      final run = _buildCouncilRun(councilId: 'council_2');

      await storage.save(run);

      final loaded = await storage.load('council_2');
      expect(loaded, isNotNull);
      expect(loaded?.councilId, equals('council_2'));
    });

    test('save overwrites existing run by id', () async {
      final original = _buildCouncilRun(councilId: 'council_3');
      final updated = _buildCouncilRun(
        councilId: 'council_3',
        title: 'Updated title',
      );

      await storage.save(original);
      await storage.save(updated);

      final loaded = await storage.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.first.title, equals('Updated title'));
    });

    test('load returns null for missing id', () async {
      final loaded = await storage.load('missing');
      expect(loaded, isNull);
    });

    test('loadAll returns empty list for missing file', () async {
      final loaded = await storage.loadAll();
      expect(loaded, isEmpty);
    });
  });

  group('AgentRegistry', () {
    test('get throws ArgumentError on unknown agent', () {
      final registry = AgentRegistry();
      expect(() => registry.get('unknown'), throwsArgumentError);
    });

    test('get uses configured agent instances built from agent configs', () {
      final registry = AgentRegistry(
        agentConfigs: {
          'claude': const AgentConfig(
            name: 'claude',
            executable: '/tmp/custom-claude',
            parser: 'claude_json',
          ),
        },
      );

      final agent = registry.get('claude');

      expect(agent, isA<ClaudeAgent>());
      expect(agent.config.executable, equals('/tmp/custom-claude'));
    });
  });

  group('Agent buildArgs', () {
    test('ClaudeAgent uses config additionalArgs as the base arguments', () {
      final agent = ClaudeAgent(
        config: const AgentConfig(
          name: 'claude',
          executable: 'claude',
          parser: 'claude_json',
          additionalArgs: ['--custom-flag', '1'],
        ),
      );

      final args = agent.buildArgs(prompt: 'hello', model: 'sonnet');

      expect(args.take(2).toList(), equals(['--custom-flag', '1']));
      expect(args, contains('hello'));
      expect(args, contains('--model'));
    });

    test('GeminiAgent uses config additionalArgs as the base arguments', () {
      final agent = GeminiAgent(
        config: const AgentConfig(
          name: 'gemini',
          executable: 'gemini',
          parser: 'gemini_json',
          additionalArgs: ['--custom-output', 'json'],
        ),
      );

      final args = agent.buildArgs(prompt: 'hello', model: 'pro');

      expect(args.take(2).toList(), equals(['--custom-output', 'json']));
      expect(args, contains('-m'));
      expect(args, contains('hello'));
    });

    test('AntigravityAgent does not pass model flag for configured model', () {
      final agent = AntigravityAgent(
        config: const AgentConfig(
          name: 'antigravity',
          executable: 'agy',
          parser: 'antigravity',
          additionalArgs: ['--print'],
        ),
      );

      final args = agent.buildArgs(prompt: 'hello', model: 'configured');

      expect(args, isNot(contains('--model')));
      expect(args, isNot(contains('-m')));
      expect(args, contains('hello'));
      expect(args.where((arg) => arg == '--print'), hasLength(1));
      expect(args[args.indexOf('--print') + 1], equals('hello'));
    });

    test('AntigravityAgent passes model flag for AGY models', () {
      final agent = AntigravityAgent(
        config: const AgentConfig(
          name: 'antigravity',
          executable: 'agy',
          parser: 'antigravity',
          additionalArgs: ['--print'],
        ),
      );
      final model = AgentModelRegistry.findModel(
        'antigravity',
        'gemini-3-5-flash-low',
      )?.resolvedModel;

      final args = agent.buildArgs(prompt: 'hello', model: model);

      expect(args, contains('--model'));
      expect(args, contains('Gemini 3.5 Flash (Low)'));
    });

    test('AntigravityAgent resumes by explicit conversation id', () async {
      final runner = _FakeCLIRunner(stdout: 'resumed\n');
      final agent = AntigravityAgent(
        config: const AgentConfig(
          name: 'antigravity',
          executable: 'agy',
          parser: 'antigravity',
          additionalArgs: ['--print'],
        ),
        runner: runner,
      );

      final response = await agent.execute(
        prompt: 'continue',
        resume: '7c110f84-b4a0-4c84-bd56-6badc97920c5',
      );

      expect(runner.lastArgs, contains('--conversation'));
      expect(runner.lastArgs, contains('7c110f84-b4a0-4c84-bd56-6badc97920c5'));
      expect(runner.lastArgs, isNot(contains('--log-file')));
      expect(
        response.metadata['session_id'],
        equals('7c110f84-b4a0-4c84-bd56-6badc97920c5'),
      );
    });

    test('AntigravityAgent extracts conversation id from temp log', () async {
      const conversationId = '23b69d94-05d1-4c8d-96c8-5a3b20272aeb';
      String? logPath;
      final runner = _FakeCLIRunner(
        stdout: 'done\n',
        onRun: (args) {
          final index = args.indexOf('--log-file');
          expect(index, isNot(equals(-1)));
          logPath = args[index + 1];
          File(logPath!).writeAsStringSync(
            'Created conversation $conversationId\n'
            'Print mode: conversation=$conversationId, sending message\n',
          );
        },
      );
      final agent = AntigravityAgent(
        config: const AgentConfig(
          name: 'antigravity',
          executable: 'agy',
          parser: 'antigravity',
          additionalArgs: ['--print'],
        ),
        runner: runner,
      );

      final response = await agent.execute(prompt: 'hello');

      expect(response.content, equals('done'));
      expect(response.metadata['session_id'], equals(conversationId));
      expect(logPath, isNotNull);
      expect(File(logPath!).existsSync(), isFalse);
    });
  });

  group('CouncilRun', () {
    test('status is completed when all stages succeed', () {
      final run = _buildCouncilRun(councilId: 'council_completed');
      expect(run.status, equals('completed'));
    });

    test('status is partial_failure when some stages fail', () {
      final run = _buildCouncilRun(
        councilId: 'council_partial',
        answerError: 'answer failed',
      );
      expect(run.status, equals('partial_failure'));
    });

    test('status is failed when no stage succeeds', () {
      final participants = [
        CouncilMember(agent: 'gemini', model: 'pro'),
        CouncilMember(agent: 'codex', model: 'gpt'),
      ];
      final chairman = CouncilMember(agent: 'claude', model: 'sonnet');
      final run = CouncilRun(
        councilId: 'council_failed',
        title: 'Failed',
        prompt: 'prompt',
        participants: participants,
        chairman: chairman,
        answers: participants
            .map(
              (participant) => CouncilParticipantResult(
                participant: participant,
                response: null,
                failure: AgentFailure(
                  reason: AgentExitReason.crash,
                  message: 'failed',
                ),
              ),
            )
            .toList(),
        reviews: participants
            .map(
              (participant) => CouncilReviewResult(
                participant: participant,
                response: null,
                failure: AgentFailure(
                  reason: AgentExitReason.crash,
                  message: 'failed',
                ),
              ),
            )
            .toList(),
        chairmanResult: CouncilChairmanResult(
          chairman: chairman,
          response: null,
          failure: AgentFailure(
            reason: AgentExitReason.crash,
            message: 'failed',
          ),
        ),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(run.status, equals('failed'));
    });
  });

  group('CouncilRunner', () {
    late Directory tempDir;
    late CouncilStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cag_council_runner_');
      storage = CouncilStorage(storagePath: '${tempDir.path}/council.jsonl');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('run saves successful results with answer session IDs', () async {
      final runner = CouncilRunner(
        storage: storage,
        geminiAgent: _FakeGeminiAgent(
          response: ParsedResponse(
            content: 'Gemini answer',
            metadata: {'session_id': 'gemini-session'},
          ),
        ),
        codexAgent: _FakeCodexAgent(
          response: ParsedResponse(
            content: 'Codex answer',
            metadata: {'session_id': 'codex-session'},
          ),
        ),
        claudeAgent: _FakeClaudeAgent(
          response: ParsedResponse(content: 'Chairman summary'),
        ),
      );

      final run = await runner.run(
        prompt: 'Discuss this',
        title: 'Discuss this',
        participants: [
          CouncilMember(agent: 'gemini', model: 'pro'),
          CouncilMember(agent: 'codex', model: 'gpt'),
        ],
        chairman: CouncilMember(agent: 'claude', model: 'sonnet'),
      );

      expect(run.councilId, startsWith('council_'));
      expect(run.answers.first.participant.sessionId, equals('gemini-session'));
      expect(run.status, equals('completed'));

      final saved = await storage.load(run.councilId);
      expect(saved, isNotNull);
      expect(saved?.answers.length, equals(2));
    });

    test('run keeps partial failure without throwing', () async {
      final runner = CouncilRunner(
        storage: storage,
        geminiAgent: _FakeGeminiAgent(
          response: ParsedResponse(
            content: 'Gemini answer',
            metadata: {'session_id': 'gemini-session'},
          ),
        ),
        codexAgent: _FakeCodexAgent(error: Exception('codex failed')),
        claudeAgent: _FakeClaudeAgent(
          response: ParsedResponse(content: 'Chairman summary'),
        ),
      );

      final run = await runner.run(
        prompt: 'Discuss this',
        title: 'Discuss this',
        participants: [
          CouncilMember(agent: 'gemini', model: 'pro'),
          CouncilMember(agent: 'codex', model: 'gpt'),
        ],
        chairman: CouncilMember(agent: 'claude', model: 'sonnet'),
      );

      expect(run.status, equals('partial_failure'));
      expect(run.answers.last.failure?.message, contains('codex failed'));
      expect(
        run.reviews.last.failure?.message,
        contains('Stage 1 response missing'),
      );
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

    test('comparePath ends with compare.jsonl', () {
      final path = AppPaths.comparePath();
      expect(path, endsWith('${Platform.pathSeparator}compare.jsonl'));
    });

    test('councilPath ends with council.jsonl', () {
      final path = AppPaths.councilPath();
      expect(path, endsWith('${Platform.pathSeparator}council.jsonl'));
    });
  });

  group('CagAgentTaskManager', () {
    late Directory tempDir;
    late CagAgentTaskManager manager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cag_task_test_');
      final fakeCodex = await _writeTaskFakeCodex(tempDir);
      final agent = CodexAgent(
        config: AgentConfig(
          name: 'codex',
          executable: Platform.resolvedExecutable,
          parser: 'codex_jsonl',
          defaultModel: 'mini',
          additionalArgs: [fakeCodex.path],
          hardTimeoutSeconds: 30,
          idleTimeoutSeconds: 30,
        ),
      );

      manager = CagAgentTaskManager(
        resolveRequest: (args) {
          final prompt = args?['prompt'] as String? ?? 'ok';
          return CagAgentRequest(
            agentName: 'codex',
            agent: agent,
            prompt: prompt,
            model: 'mini',
            mode: args?['mode'] == 'background'
                ? CagAgentMode.background
                : CagAgentMode.sync,
            cwd: args?['cwd'] as String?,
            name: args?['name'] as String?,
            verbose: args?['verbose'] == true,
          );
        },
        perAgentConcurrencyLimit: 3,
      );
    });

    tearDown(() async {
      await manager.dispose();
      await tempDir.delete(recursive: true);
    });

    test('background mode returns a handle immediately', () async {
      final created = await manager.createTask({
        'prompt': 'slow background',
        'mode': 'background',
        'name': 'slow task',
      }, null);

      final launcherResult = await manager.getTaskResult(created.task.taskId);
      final realTaskId = launcherResult.structuredContent?['task_id'] as String;
      final realTask = await manager.getTask(realTaskId);

      expect(created.task.status, equals(TaskStatus.completed));
      expect(launcherResult.isError, isFalse);
      expect(launcherResult.structuredContent?['status'], equals('working'));
      expect(launcherResult.structuredContent?['name'], equals('slow task'));
      expect(realTask.status, equals(TaskStatus.working));

      await manager.cancelTask(realTaskId);
    });

    test('cag_task waits for any task and retrieves each result', () async {
      final taskIds = await Future.wait([
        _startBackgroundTask(manager, 'first'),
        _startBackgroundTask(manager, 'second'),
        _startBackgroundTask(manager, 'third'),
      ]);

      final waitAny = await manager.handleTaskTool({
        'action': 'wait_any',
        'task_ids': taskIds,
        'timeout_ms': 5000,
      });

      expect(waitAny.isError, isFalse);
      expect(waitAny.structuredContent?['task'], isNotNull);

      for (final taskId in taskIds) {
        await _waitForTaskStatus(manager, taskId, TaskStatus.completed);
        final result = await manager.handleTaskTool({
          'action': 'result',
          'task_id': taskId,
        });

        expect(result.isError, isFalse);
        expect(result.structuredContent, isNot(contains('log')));
        expect(
          result.structuredContent?['task'],
          containsPair('result', containsPair('session_id', 'fake-thread')),
        );
      }
    });

    test(
      'background mode rejects a fourth running task for the same agent',
      () async {
        await Future.wait([
          _startBackgroundTask(manager, 'slow one'),
          _startBackgroundTask(manager, 'slow two'),
          _startBackgroundTask(manager, 'slow three'),
        ]);

        expect(
          () => manager.createTask({
            'prompt': 'slow four',
            'mode': 'background',
          }, null),
          throwsA(isA<McpError>()),
        );
      },
    );

    test('cag_task wait timeout and cancel return status payloads', () async {
      final taskId = await _startBackgroundTask(manager, 'slow wait');

      final wait = await manager.handleTaskTool({
        'action': 'wait',
        'task_id': taskId,
        'timeout_ms': 1,
      });
      expect(wait.isError, isFalse);
      expect(wait.structuredContent?['timed_out'], isTrue);
      expect(
        wait.structuredContent?['task'],
        containsPair('status', 'working'),
      );

      final cancel = await manager.handleTaskTool({
        'action': 'cancel',
        'task_id': taskId,
      });
      expect(cancel.isError, isFalse);
      expect(
        cancel.structuredContent?['task'],
        containsPair('status', 'cancelled'),
      );
    });

    test('include_log is opt-in for cag_task result', () async {
      final taskId = await _startBackgroundTask(manager, 'log please');
      await _waitForTaskStatus(manager, taskId, TaskStatus.completed);

      final compact = await manager.handleTaskTool({
        'action': 'result',
        'task_id': taskId,
      });
      expect(compact.structuredContent, isNot(contains('log')));

      final withLog = await manager.handleTaskTool({
        'action': 'result',
        'task_id': taskId,
        'include_log': true,
      });
      expect(
        withLog.structuredContent,
        containsPair('log', containsPair('stdout', contains('agent_message'))),
      );
    });

    test('launcher tasks stay hidden from lists and resources', () async {
      final created = await manager.createTask({
        'prompt': 'slow hidden launcher',
        'mode': 'background',
      }, null);
      final launcherId = created.task.taskId;
      final launcherResult = await manager.getTaskResult(launcherId);
      final realTaskId = launcherResult.structuredContent?['task_id'] as String;

      final taskList = await manager.listTasks();
      expect(taskList.tasks.map((task) => task.taskId), contains(realTaskId));
      expect(
        taskList.tasks.map((task) => task.taskId),
        isNot(contains(launcherId)),
      );

      final resources = await manager.listResources();
      final resourceUris = resources.resources.map((resource) => resource.uri);
      expect(resourceUris, contains('cag://tasks/$realTaskId'));
      expect(resourceUris, isNot(contains('cag://tasks/$launcherId')));

      final toolList = await manager.handleTaskTool({'action': 'list'});
      final tasks = toolList.structuredContent?['tasks'] as List;
      expect(tasks.map((task) => task['task_id']), contains(realTaskId));
      expect(tasks.map((task) => task['task_id']), isNot(contains(launcherId)));

      await manager.cancelTask(realTaskId);
    });

    test(
      'cancel issued before process start kills the process on start',
      () async {
        await manager.dispose();
        final fakeProcess = await _writeLongRunningDartProcess(tempDir);
        final agent = _DelayedStartAgent(fakeProcess.path);
        manager = CagAgentTaskManager(
          resolveRequest: (args) {
            return CagAgentRequest(
              agentName: 'codex',
              agent: agent,
              prompt: 'delayed',
              model: 'mini',
              mode: CagAgentMode.sync,
              verbose: false,
            );
          },
        );

        final created = await manager.createTask({'prompt': 'delayed'}, null);
        await manager.cancelTask(created.task.taskId);
        await agent.started.future;
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(Process.killPid(agent.pid!, ProcessSignal.sigkill), isFalse);
        final task = await manager.getTask(created.task.taskId);
        expect(task.status, equals(TaskStatus.cancelled));
      },
    );

    test(
      'runs concurrent tasks with compact results and opt-in logs',
      () async {
        final created = await Future.wait([
          manager.createTask({'prompt': 'first'}, null),
          manager.createTask({'prompt': 'second'}, null),
          manager.createTask({'prompt': 'third'}, null),
        ]);

        for (final task in created) {
          await _waitForTaskStatus(
            manager,
            task.task.taskId,
            TaskStatus.completed,
          );
          final result = await manager.getTaskResult(task.task.taskId);
          expect(result.isError, isFalse);
          expect(result.structuredContent?['result'], isNotNull);

          final resultJson =
              jsonDecode(await manager.readTaskResultJson(task.task.taskId))
                  as Map<String, dynamic>;
          expect(resultJson.containsKey('stdout'), isFalse);
          expect(resultJson.containsKey('stderr'), isFalse);

          final logJson =
              jsonDecode(await manager.readTaskLog(task.task.taskId))
                  as Map<String, dynamic>;
          expect(logJson['stdout'], contains('agent_message'));
        }
      },
    );

    test('rejects a fourth running task for the same agent', () async {
      await Future.wait([
        manager.createTask({'prompt': 'slow one'}, null),
        manager.createTask({'prompt': 'slow two'}, null),
        manager.createTask({'prompt': 'slow three'}, null),
      ]);

      expect(
        () => manager.createTask({'prompt': 'slow four'}, null),
        throwsA(isA<McpError>()),
      );
    });

    test('tasks/result errors before terminal status', () async {
      final created = await manager.createTask({'prompt': 'slow'}, null);

      expect(
        () => manager.getTaskResult(created.task.taskId),
        throwsA(isA<McpError>()),
      );
    });

    test('cancels a running process', () async {
      final created = await manager.createTask({'prompt': 'slow'}, null);

      await manager.cancelTask(created.task.taskId);
      final task = await manager.getTask(created.task.taskId);

      expect(task.status, equals(TaskStatus.cancelled));
      final result = await manager.getTaskResult(created.task.taskId);
      expect(result.isError, isTrue);
    });

    test('evicts terminal tasks and removes retained capture files', () async {
      await manager.dispose();
      final fakeCodex = await _writeTaskFakeCodex(tempDir);
      final agent = CodexAgent(
        config: AgentConfig(
          name: 'codex',
          executable: Platform.resolvedExecutable,
          parser: 'codex_jsonl',
          defaultModel: 'mini',
          additionalArgs: [fakeCodex.path],
          hardTimeoutSeconds: 30,
          idleTimeoutSeconds: 30,
        ),
      );
      manager = CagAgentTaskManager(
        resolveRequest: (args) {
          return CagAgentRequest(
            agentName: 'codex',
            agent: agent,
            prompt: args?['prompt'] as String? ?? 'ok',
            model: 'mini',
            mode: CagAgentMode.sync,
            verbose: false,
          );
        },
        retention: const Duration(seconds: 1),
      );

      final created = await manager.createTask({'prompt': 'evict me'}, null);
      await _waitForTaskStatus(
        manager,
        created.task.taskId,
        TaskStatus.completed,
      );
      final stdoutPath = await _taskStdoutPath(manager, created.task.taskId);
      expect(stdoutPath, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await manager.sweepExpiredTasks();

      expect(
        () => manager.getTask(created.task.taskId),
        throwsA(isA<McpError>()),
      );
      expect(await File(stdoutPath!).exists(), isFalse);
    });
  });
}

CouncilRun _buildCouncilRun({
  required String councilId,
  String title = 'Council run',
  String? answerError,
}) {
  final firstParticipant = CouncilMember(
    agent: 'gemini',
    model: 'pro',
    sessionId: answerError == null ? 's1' : null,
  );
  final secondParticipant = CouncilMember(agent: 'codex', model: 'gpt');
  final chairman = CouncilMember(agent: 'claude', model: 'sonnet');

  return CouncilRun(
    councilId: councilId,
    title: title,
    prompt: 'test prompt',
    participants: [firstParticipant, secondParticipant],
    chairman: chairman,
    answers: [
      CouncilParticipantResult(
        participant: firstParticipant,
        response: answerError == null
            ? ParsedResponse(
                content: 'answer 1',
                metadata: {'session_id': 's1'},
              )
            : null,
        failure: answerError == null
            ? null
            : AgentFailure(reason: AgentExitReason.crash, message: answerError),
      ),
      CouncilParticipantResult(
        participant: secondParticipant,
        response: ParsedResponse(content: 'answer 2'),
      ),
    ],
    reviews: [
      CouncilReviewResult(
        participant: firstParticipant,
        response: ParsedResponse(content: 'review 1'),
      ),
      CouncilReviewResult(
        participant: secondParticipant,
        response: ParsedResponse(content: 'review 2'),
      ),
    ],
    chairmanResult: CouncilChairmanResult(
      chairman: chairman,
      response: ParsedResponse(content: 'summary'),
    ),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

Future<File> _writeTaskFakeCodex(Directory tempDir) async {
  final file = File('${tempDir.path}${Platform.pathSeparator}fake_codex.dart');
  await file.writeAsString(r'''
import 'dart:async';
import 'dart:convert';

Future<void> main(List<String> args) async {
  final prompt = args.isEmpty ? '' : args.last;
  if (prompt.contains('slow')) {
    await Future<void>.delayed(const Duration(seconds: 10));
  }
  print(jsonEncode({'type': 'thread.started', 'thread_id': 'fake-thread'}));
  print(jsonEncode({
    'type': 'item.completed',
    'item': {'type': 'agent_message', 'text': prompt},
  }));
}
''');
  return file;
}

Future<Task> _waitForTaskStatus(
  CagAgentTaskManager manager,
  String taskId,
  TaskStatus status,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final task = await manager.getTask(taskId);
    if (task.status == status) {
      return task;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return manager.getTask(taskId);
}

Future<String?> _taskStdoutPath(CagAgentTaskManager manager, String taskId) {
  return manager.debugStdoutPath(taskId);
}

Future<String> _startBackgroundTask(
  CagAgentTaskManager manager,
  String prompt,
) async {
  final created = await manager.createTask({
    'prompt': prompt,
    'mode': 'background',
  }, null);
  final launcherResult = await manager.getTaskResult(created.task.taskId);
  return launcherResult.structuredContent?['task_id'] as String;
}

Future<File> _writeLongRunningDartProcess(Directory tempDir) async {
  final file = File(
    '${tempDir.path}${Platform.pathSeparator}long_running.dart',
  );
  await file.writeAsString(r'''
import 'dart:async';

Future<void> main() async {
  await Future<void>.delayed(const Duration(seconds: 30));
}
''');
  return file;
}

class _DelayedStartAgent extends CodexAgent {
  _DelayedStartAgent(this.processScript)
    : super(
        config: AgentConfig(
          name: 'codex',
          executable: Platform.resolvedExecutable,
          parser: 'codex_jsonl',
          defaultModel: 'mini',
        ),
      );

  final String processScript;
  final Completer<void> started = Completer<void>();
  int? pid;

  @override
  Future<AgentDetailedExecution> executeDetailed({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
    String? workingDirectory,
    ProcessStarted? onProcessStarted,
    bool keepCapture = false,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final process = await Process.start(Platform.resolvedExecutable, [
      processScript,
    ]);
    pid = process.pid;
    onProcessStarted?.call(RunningProcess(process));
    if (!started.isCompleted) {
      started.complete();
    }
    final exitCode = await process.exitCode;
    return AgentDetailedExecution(
      response: ParsedResponse(content: 'done'),
      result: AgentExecutionResult(
        exitCode: exitCode,
        stdout: '',
        stderr: '',
        durationMs: 0,
      ),
    );
  }
}

class _FakeGeminiAgent extends GeminiAgent {
  _FakeGeminiAgent({this.response});

  final ParsedResponse? response;

  @override
  Future<ParsedResponse> execute({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
  }) async {
    return response!;
  }
}

class _FakeCodexAgent extends CodexAgent {
  _FakeCodexAgent({this.response, this.error});

  final ParsedResponse? response;
  final Object? error;

  @override
  Future<ParsedResponse> execute({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
  }) async {
    if (error != null) {
      throw error!;
    }
    return response!;
  }
}

class _FakeClaudeAgent extends ClaudeAgent {
  _FakeClaudeAgent({this.response});

  final ParsedResponse? response;

  @override
  Future<ParsedResponse> execute({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
  }) async {
    return response!;
  }
}

class _FakeCLIRunner extends CLIRunner {
  _FakeCLIRunner({required this.stdout, this.onRun});

  final String stdout;
  final void Function(List<String> args)? onRun;
  List<String> lastArgs = const [];

  @override
  Future<CLIResult> run({
    required String executable,
    required List<String> args,
    Map<String, String>? env,
    Duration? hardTimeout,
    Duration? idleTimeout,
    String? workingDirectory,
    ProcessStarted? onProcessStarted,
    bool keepCapture = false,
  }) async {
    lastArgs = args;
    onRun?.call(args);
    return CLIResult(exitCode: 0, stdout: stdout, stderr: '', durationMs: 1);
  }
}
