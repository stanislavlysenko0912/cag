import 'dart:async';
import 'dart:convert';
import 'dart:io';

Map<String, dynamic>? pendingPrompt;
String selectedModel = 'agent-default';
String sessionId = 'session-new';
String permissionOutcome = 'none';
String sessionCwd = '';

Future<void> main(List<String> args) async {
  final mode = Platform.environment['FAKE_ACP_MODE'] ?? 'normal';
  if (mode == 'early_exit') exit(7);
  if (mode == 'idle') {
    await stdin.drain<void>();
    return;
  }
  if (mode == 'malformed') {
    stdout.writeln('not-json');
    await stdout.flush();
    await Completer<void>().future;
  }

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final message = jsonDecode(line) as Map<String, dynamic>;
    await handleMessage(message, mode, args);
  }
  if (mode == 'linger_after_eof') {
    await Completer<void>().future;
  }
}

Future<void> handleMessage(
  Map<String, dynamic> message,
  String mode,
  List<String> args,
) async {
  final method = message['method'];
  final id = message['id'];
  final params = message['params'] as Map<String, dynamic>? ?? const {};
  switch (method) {
    case 'initialize':
      if (mode == 'protocol_error') {
        reject(id, -32603, 'Protocol failure');
        return;
      }
      final capabilities = params['clientCapabilities'] as Map<String, dynamic>;
      final fileSystem = capabilities['fs'] as Map<String, dynamic>;
      if (fileSystem['readTextFile'] != false ||
          fileSystem['writeTextFile'] != false ||
          capabilities['terminal'] != false) {
        reject(id, -32602, 'Unexpected client capability');
        return;
      }
      respond(id, {
        'protocolVersion': 1,
        'agentCapabilities': {'loadSession': true},
        'authMethods': <Object>[],
      });
    case 'session/new':
      if (mode == 'auth_required') {
        reject(id, -32000, 'Authentication required');
        return;
      }
      sessionId = 'session-new';
      sessionCwd = params['cwd'] as String;
      respond(id, sessionResponse(sessionId));
    case 'session/load':
      sessionId = params['sessionId'] as String;
      sessionCwd = params['cwd'] as String;
      notifyMessage('old replay');
      respond(id, sessionState());
    case 'session/set_config_option':
      selectedModel = params['value'] as String;
      respond(id, sessionState());
    case 'session/prompt':
      pendingPrompt = message;
      requestPermission(mode);
    case null:
      if (id == 99) {
        final result = message['result'] as Map<String, dynamic>;
        final outcome = result['outcome'] as Map<String, dynamic>;
        permissionOutcome = outcome['outcome'] as String;
        await finishPrompt(args);
      }
  }
}

Map<String, dynamic> sessionResponse(String id) => {
  'sessionId': id,
  ...sessionState(),
};

Map<String, dynamic> sessionState() => {
  'configOptions': [
    {
      'id': 'model',
      'name': 'Model',
      'type': 'select',
      'currentValue': selectedModel,
      'options': [
        {'value': 'fast', 'name': 'Fast', 'description': 'Fast model'},
        {
          'value': 'agent-default',
          'name': 'Default',
          'description': 'Agent default model',
        },
      ],
    },
  ],
};

void requestPermission(String mode) {
  final options = mode == 'no_allow_once'
      ? [
          {'optionId': 'always', 'name': 'Always', 'kind': 'allow_always'},
        ]
      : [
          {'optionId': 'once', 'name': 'Once', 'kind': 'allow_once'},
          {'optionId': 'always', 'name': 'Always', 'kind': 'allow_always'},
        ];
  request(99, 'session/request_permission', {
    'sessionId': sessionId,
    'toolCall': {'toolCallId': 'tool-1', 'title': 'Test tool'},
    'options': options,
  });
}

Future<void> finishPrompt(List<String> args) async {
  final prompt = pendingPrompt!;
  final params = prompt['params'] as Map<String, dynamic>;
  final blocks = params['prompt'] as List<dynamic>;
  final text = (blocks.single as Map<String, dynamic>)['text'];
  notifyMessage('hello ');
  notifyMessage(
    'world|model=$selectedModel|permission=$permissionOutcome|'
    'env=${Platform.environment['ACP_TEST_ENV']}|'
    'args=${args.join(',')}|cwd=$sessionCwd|prompt=$text',
  );
  respond(prompt['id'], {'stopReason': 'end_turn'});
  pendingPrompt = null;
}

void notifyMessage(String text) {
  notify('session/update', {
    'sessionId': sessionId,
    'update': {
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': text},
    },
  });
}

void respond(Object? id, Map<String, dynamic> result) {
  write({'jsonrpc': '2.0', 'id': id, 'result': result});
}

void reject(Object? id, int code, String message) {
  write({
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  });
}

void request(int id, String method, Map<String, dynamic> params) {
  write({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
}

void notify(String method, Map<String, dynamic> params) {
  write({'jsonrpc': '2.0', 'method': method, 'params': params});
}

void write(Map<String, dynamic> message) {
  stdout.writeln(jsonEncode(message));
}
