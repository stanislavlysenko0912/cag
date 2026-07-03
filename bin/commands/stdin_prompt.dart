import 'dart:convert';
import 'dart:io';

Future<String> readPromptInput(List<String> rest) async {
  final argumentPrompt = rest.join(' ');
  if (stdin.hasTerminal) {
    return argumentPrompt;
  }

  final stdinPrompt = await stdin.transform(utf8.decoder).join();
  return combinePromptInput(argumentPrompt, stdinPrompt);
}

String combinePromptInput(String argumentPrompt, String stdinPrompt) {
  final pipePrompt = stdinPrompt.trimRight();
  if (argumentPrompt.trim().isEmpty) {
    return pipePrompt;
  }
  if (pipePrompt.isEmpty) {
    return argumentPrompt;
  }
  return '${argumentPrompt.trimRight()}\n\n$pipePrompt';
}
