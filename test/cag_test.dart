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
      expect(AgentModelRegistry.findModel('claude', 'sonnet')?.name, equals('claude-sonnet-4-6'));
      expect(AgentModelRegistry.findModel('claude', 'haiku')?.name, equals('claude-haiku-4-5'));
      expect(AgentModelRegistry.findModel('gemini', 'pro')?.name, equals('gemini-3.1-pro-preview'));
      expect(AgentModelRegistry.findModel('gemini', 'flash')?.name, equals('gemini-3-flash-preview'));
      expect(AgentModelRegistry.findModel('codex', 'gpt')?.name, equals('gpt-5.5'));
      expect(AgentModelRegistry.findModel('codex', 'mini')?.name, equals('gpt-5.5-mini'));
      expect(AgentModelRegistry.findModel('cursor', 'auto'), isNull);
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

    test('parse normalizes uppercase agent input', () {
      final participant = ConsensusParticipant.parse('GEMINI:pro:neutral');
      expect(participant.agent, equals('gemini'));
    });

    test('parse throws ArgumentError when no agents are enabled', () {
      expect(() => ConsensusParticipant.parse('gemini:pro:for', allowedAgents: const []), throwsArgumentError);
    });
  });

  group('AgentConfig', () {
    test('AgentConfig creates with default values', () {
      const config = AgentConfig(name: 'test', executable: 'test-cli', parser: 'json');

      expect(config.name, equals('test'));

      expect(config.hardTimeoutSeconds, equals(1800));
      expect(config.idleTimeoutSeconds, equals(900));

      expect(config.additionalArgs, isEmpty);
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
      expect(() => CompareParticipant.parse('gemini:pro:extra'), throwsArgumentError);
    });

    test('parse throws ArgumentError on invalid agent', () {
      expect(() => CompareParticipant.parse('unknown:pro'), throwsArgumentError);
    });

    test('parse normalizes uppercase agent input', () {
      final participant = CompareParticipant.parse('GEMINI:pro');
      expect(participant.agent, equals('gemini'));
    });

    test('parse throws ArgumentError when no agents are enabled', () {
      expect(() => CompareParticipant.parse('gemini:pro', allowedAgents: const []), throwsArgumentError);
    });
  });

  group('CouncilMember', () {
    test('parse throws ArgumentError when no agents are enabled', () {
      expect(() => CouncilMember.parse('gemini:pro', allowedAgents: const []), throwsArgumentError);
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
      final result = await runner.run(executable: 'echo', args: ['hello']);

      expect(result.exitCode, equals(0));
      expect(result.stdout.trim(), equals('hello'));
    });

    test('run executes a shell command when invoked via shell executable', () async {
      final runner = CLIRunner();
      final result = await runner.run(executable: '/bin/sh', args: ['-c', 'echo prefix && echo hello']);

      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('prefix'));
      expect(result.stdout, contains('hello'));
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

      final output = generator.generate(
        commands,
        agentConfigs: {'test-agent': const AgentConfig(name: 'test-agent', executable: 'test', parser: 'test')},
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
          models: [ModelConfig(name: 'sonnet', description: 'Default', isDefault: true)],
        ),
        const CommandMetadata(name: 'compare', description: 'Compare command'),
      ];

      final output = generator.generate(
        commands,
        agentConfigs: {'claude': const AgentConfig(name: 'claude', executable: 'claude', parser: 'claude')},
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
          models: [ModelConfig(name: 'sonnet', description: 'Base', isDefault: true)],
        ),
      ];

      final output = generator.generate(
        commands,
        agentConfigs: {
          'claude': const AgentConfig(
            name: 'claude',
            executable: 'claude',
            parser: 'claude',
            availableModels: [ModelConfig(name: 'custom-model', description: 'Custom model', isDefault: true)],
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
            ModelConfig(name: 'gpt-5.5', description: 'Default', isDefault: true),
            ModelConfig(name: 'gpt-5.3-codex', description: 'Code model'),
          ],
        ),
        const CommandMetadata(
          name: 'claude',
          description: 'Claude agent',
          models: [ModelConfig(name: 'claude-sonnet-4-6', description: 'Default', isDefault: true)],
        ),
        const CommandMetadata(name: 'compare', description: 'Compare command'),
      ];

      final output = generator.generate(
        commands,
        agentConfigs: {
          'codex': const AgentConfig(name: 'codex', executable: 'codex', parser: 'codex'),
          'claude': const AgentConfig(name: 'claude', executable: 'claude', parser: 'claude'),
        },
      );

      expect(output, contains('## Command Syntax'));
      expect(output, contains('cag codex -m gpt-5.5 "Review this approach"'));
      expect(output, contains('cag compare -a "codex:gpt-5.5" -a "claude:claude-sonnet-4-6" "Compare options"'));
      expect(output, contains('Wrong: cag codex:gpt-5.5 "Review this approach"'));
    });

    test('generate warns against retrying slow strong models', () {
      const generator = PrimeGenerator();

      final commands = [
        const CommandMetadata(
          name: 'codex',
          description: 'Codex agent',
          models: [ModelConfig(name: 'gpt-5.5', description: 'Default', isDefault: true)],
        ),
      ];

      final output = generator.generate(
        commands,
        agentConfigs: {'codex': const AgentConfig(name: 'codex', executable: 'codex', parser: 'codex')},
      );

      expect(
        output,
        contains('Stronger models can take noticeably longer to answer; do not resend the same request just because the response is slow'),
      );
    });

    test('generate explains that workspace is shared across agents', () {
      const generator = PrimeGenerator();

      final commands = [
        const CommandMetadata(
          name: 'codex',
          description: 'Codex agent',
          models: [ModelConfig(name: 'gpt-5.5-mini', description: 'Fast', isDefault: true)],
        ),
      ];

      final output = generator.generate(
        commands,
        agentConfigs: {'codex': const AgentConfig(name: 'codex', executable: 'codex', parser: 'codex')},
      );

      expect(
        output,
        contains('All agents start in the same current working directory (`cwd`) as you and have direct file access to that workspace'),
      );
      expect(
        output,
        contains(
          'Treat the workspace as shared: reference file paths and ask the agent to inspect files directly instead of retelling repository structure or pasting large file contents.',
        ),
      );
    });

    test('generate defaults to multi-turn dialogue instead of one-shot', () {
      const generator = PrimeGenerator();

      final commands = [
        const CommandMetadata(
          name: 'codex',
          description: 'Codex agent',
          models: [ModelConfig(name: 'gpt-5.5-mini', description: 'Fast', isDefault: true)],
        ),
      ];

      final output = generator.generate(
        commands,
        agentConfigs: {'codex': const AgentConfig(name: 'codex', executable: 'codex', parser: 'codex')},
      );

      expect(
        output,
        contains(
          'After the first useful answer, always continue with at least 2 follow-up rounds (pushback, refinement, deeper questions) before presenting results to the user',
        ),
      );
      expect(
        output,
        contains('Treat `session_id` as the default way to deepen the discussion, not just a technical detail for optional follow-ups.'),
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
            participant: CompareParticipant(agent: 'gemini', model: 'pro', sessionId: 's1'),
            response: ParsedResponse(content: 'hello', metadata: {'session_id': 's1'}),
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
          response: ParsedResponse(content: 'Gemini answer', metadata: {'session_id': 'gemini-session'}),
        ),
        codexAgent: _FakeCodexAgent(
          response: ParsedResponse(content: 'Codex answer', metadata: {'session_id': 'codex-session'}),
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
          response: ParsedResponse(content: 'Gemini answer', metadata: {'session_id': 'gemini-session'}),
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
      final updated = _buildCouncilRun(councilId: 'council_3', title: 'Updated title');

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
        agentConfigs: {'claude': const AgentConfig(name: 'claude', executable: '/tmp/custom-claude', parser: 'claude_json')},
      );

      final agent = registry.get('claude');

      expect(agent, isA<ClaudeAgent>());
      expect(agent.config.executable, equals('/tmp/custom-claude'));
    });
  });

  group('Agent buildArgs', () {
    test('ClaudeAgent uses config additionalArgs as the base arguments', () {
      final agent = ClaudeAgent(
        config: const AgentConfig(name: 'claude', executable: 'claude', parser: 'claude_json', additionalArgs: ['--custom-flag', '1']),
      );

      final args = agent.buildArgs(prompt: 'hello', model: 'sonnet');

      expect(args.take(2).toList(), equals(['--custom-flag', '1']));
      expect(args, contains('hello'));
      expect(args, contains('--model'));
    });

    test('GeminiAgent uses config additionalArgs as the base arguments', () {
      final agent = GeminiAgent(
        config: const AgentConfig(name: 'gemini', executable: 'gemini', parser: 'gemini_json', additionalArgs: ['--custom-output', 'json']),
      );

      final args = agent.buildArgs(prompt: 'hello', model: 'pro');

      expect(args.take(2).toList(), equals(['--custom-output', 'json']));
      expect(args, contains('-m'));
      expect(args, contains('hello'));
    });
  });

  group('CouncilRun', () {
    test('status is completed when all stages succeed', () {
      final run = _buildCouncilRun(councilId: 'council_completed');
      expect(run.status, equals('completed'));
    });

    test('status is partial_failure when some stages fail', () {
      final run = _buildCouncilRun(councilId: 'council_partial', answerError: 'answer failed');
      expect(run.status, equals('partial_failure'));
    });

    test('status is failed when no stage succeeds', () {
      final participants = [CouncilMember(agent: 'gemini', model: 'pro'), CouncilMember(agent: 'codex', model: 'gpt')];
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
                failure: AgentFailure(reason: AgentExitReason.crash, message: 'failed'),
              ),
            )
            .toList(),
        reviews: participants
            .map(
              (participant) => CouncilReviewResult(
                participant: participant,
                response: null,
                failure: AgentFailure(reason: AgentExitReason.crash, message: 'failed'),
              ),
            )
            .toList(),
        chairmanResult: CouncilChairmanResult(
          chairman: chairman,
          response: null,
          failure: AgentFailure(reason: AgentExitReason.crash, message: 'failed'),
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
          response: ParsedResponse(content: 'Gemini answer', metadata: {'session_id': 'gemini-session'}),
        ),
        codexAgent: _FakeCodexAgent(
          response: ParsedResponse(content: 'Codex answer', metadata: {'session_id': 'codex-session'}),
        ),
        claudeAgent: _FakeClaudeAgent(response: ParsedResponse(content: 'Chairman summary')),
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
          response: ParsedResponse(content: 'Gemini answer', metadata: {'session_id': 'gemini-session'}),
        ),
        codexAgent: _FakeCodexAgent(error: Exception('codex failed')),
        claudeAgent: _FakeClaudeAgent(response: ParsedResponse(content: 'Chairman summary')),
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
      expect(run.reviews.last.failure?.message, contains('Stage 1 response missing'));
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
}

CouncilRun _buildCouncilRun({required String councilId, String title = 'Council run', String? answerError}) {
  final firstParticipant = CouncilMember(agent: 'gemini', model: 'pro', sessionId: answerError == null ? 's1' : null);
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
        response: answerError == null ? ParsedResponse(content: 'answer 1', metadata: {'session_id': 's1'}) : null,
        failure: answerError == null ? null : AgentFailure(reason: AgentExitReason.crash, message: answerError),
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
