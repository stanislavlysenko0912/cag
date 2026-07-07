import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cag/src/detect/detect.dart';

class DetectCommand extends Command<void> {
  @override
  String get name => 'detect';

  @override
  String get description =>
      'Detect installed agent CLIs and update config enablement';

  @override
  Future<void> run() async {
    final result = await DetectService().detectAndSave();
    _printSummary(result.agents);
    stdout.writeln('Updated config: ${result.configPath}');
  }

  void _printSummary(Map<String, bool> detection) {
    stdout.writeln('Detected agents:');
    for (final entry in detection.entries) {
      final status = entry.value ? 'found' : 'missing';
      stdout.writeln('  - ${entry.key}: $status');
    }
  }
}
