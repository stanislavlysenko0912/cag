import 'dart:io';

import 'package:cag/cag.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('AcpAgent', () {
    test('runs ACP lifecycle and normalizes streamed response', () async {
      final workingDirectory = await Directory.systemTemp.createTemp(
        'cag_acp_cwd_',
      );
      addTearDown(() => workingDirectory.delete(recursive: true));
      final agent = _agent(args: ['--marker'], env: {'ACP_TEST_ENV': 'yes'});

      final execution = await agent.executeDetailed(
        prompt: 'review this',
        model: 'fast',
        systemPrompt: 'be exact',
        workingDirectory: workingDirectory.path,
      );

      expect(execution.response.content, startsWith('hello world'));
      expect(execution.response.content, contains('model=fast'));
      expect(execution.response.content, contains('permission=selected'));
      expect(execution.response.content, contains('env=yes'));
      expect(execution.response.content, contains('args=--marker'));
      expect(
        execution.response.content,
        contains('cwd=${workingDirectory.path}'),
      );
      expect(
        execution.response.content,
        contains('<system_instructions>\nbe exact\n</system_instructions>'),
      );
      expect(execution.response.metadata['session_id'], 'session-new');
      expect(execution.response.metadata['stop_reason'], 'end_turn');
    });

    test('keeps agent default model when model is omitted', () async {
      final response = await _agent().execute(prompt: 'hello');

      expect(response.content, contains('model=agent-default'));
    });

    test('loads resume session and excludes replayed messages', () async {
      final response = await _agent().execute(
        prompt: 'continue',
        resume: 'session-existing',
        systemPrompt: 'must not be resent',
      );

      expect(response.content, isNot(contains('old replay')));
      expect(response.content, contains('prompt=continue'));
      expect(response.content, isNot(contains('must not be resent')));
      expect(response.metadata['session_id'], 'session-existing');
    });

    test('cancels permission when allow_once is unavailable', () async {
      final response = await _agent(
        env: {'FAKE_ACP_MODE': 'no_allow_once'},
      ).execute(prompt: 'hello');

      expect(response.content, contains('permission=cancelled'));
    });

    test('fails malformed ACP output and stops the process', () async {
      final agent = _agent(
        env: {'FAKE_ACP_MODE': 'malformed'},
        hardTimeoutSeconds: 5,
      );

      await expectLater(
        agent.execute(prompt: 'hello'),
        throwsA(
          isA<AgentExecutionException>().having(
            (error) => error.failure.message,
            'message',
            contains('Invalid ACP message'),
          ),
        ),
      );
    });

    test('maps early process exit to CLI failure', () async {
      final agent = _agent(env: {'FAKE_ACP_MODE': 'early_exit'});

      await expectLater(
        agent.execute(prompt: 'hello'),
        throwsA(
          isA<AgentExecutionException>().having(
            (error) => error.failure.reason,
            'reason',
            AgentExitReason.cliError,
          ),
        ),
      );
    });

    test('maps protocol errors to an agent failure', () async {
      final agent = _agent(env: {'FAKE_ACP_MODE': 'protocol_error'});

      await expectLater(
        agent.execute(prompt: 'hello'),
        throwsA(
          isA<AgentExecutionException>().having(
            (error) => error.failure.message,
            'message',
            contains('Protocol failure'),
          ),
        ),
      );
    });

    test('reports authentication required without interactive login', () async {
      final agent = _agent(env: {'FAKE_ACP_MODE': 'auth_required'});

      await expectLater(
        agent.execute(prompt: 'hello'),
        throwsA(
          isA<AgentExecutionException>().having(
            (error) => error.failure.message,
            'message',
            contains('Authentication required'),
          ),
        ),
      );
    });

    test('maps idle process timeout', () async {
      final agent = _agent(
        env: {'FAKE_ACP_MODE': 'idle'},
        hardTimeoutSeconds: 5,
        idleTimeoutSeconds: 1,
      );

      await expectLater(
        agent.execute(prompt: 'hello'),
        throwsA(
          isA<AgentExecutionException>().having(
            (error) => error.failure.reason,
            'reason',
            AgentExitReason.timeoutIdle,
          ),
        ),
      );
    });

    test('maps hard process timeout', () async {
      final agent = _agent(
        env: {'FAKE_ACP_MODE': 'idle'},
        hardTimeoutSeconds: 1,
        idleTimeoutSeconds: 5,
      );

      await expectLater(
        agent.execute(prompt: 'hello'),
        throwsA(
          isA<AgentExecutionException>().having(
            (error) => error.failure.reason,
            'reason',
            AgentExitReason.timeoutHard,
          ),
        ),
      );
    });

    test('retains raw ACP capture when requested', () async {
      final execution = await _agent().executeDetailed(
        prompt: 'hello',
        keepCapture: true,
      );

      final stdoutPath = execution.result.stdoutPath;
      final stderrPath = execution.result.stderrPath;
      addTearDown(() async {
        if (stdoutPath != null) {
          await File(stdoutPath).parent.delete(recursive: true);
        }
      });
      expect(stdoutPath, isNotNull);
      expect(stderrPath, isNotNull);
      expect(
        await File(stdoutPath!).readAsString(),
        contains('"session/request_permission"'),
      );
    });
  });
}

AcpAgent _agent({
  List<String> args = const [],
  Map<String, String> env = const {},
  int hardTimeoutSeconds = 10,
  int? idleTimeoutSeconds,
}) {
  final fixture = p.join(
    Directory.current.path,
    'test',
    'fixtures',
    'fake_acp_agent.dart',
  );
  return AcpAgent(
    config: AgentConfig(
      name: 'test-acp',
      executable: Platform.resolvedExecutable,
      parser: 'acp',
      additionalArgs: [fixture, ...args],
      env: env,
      hardTimeoutSeconds: hardTimeoutSeconds,
      idleTimeoutSeconds: idleTimeoutSeconds ?? hardTimeoutSeconds,
    ),
  );
}
