import '../models/models.dart';

/// Exception thrown when CLI output cannot be parsed.
class ParserException implements Exception {
  ParserException(this.message);
  final String message;

  @override
  String toString() => 'ParserException: $message';
}

/// Base interface for CLI output parsers.
abstract class BaseParser {
  /// Parser identifier.
  String get name;

  /// Parse CLI output into a structured response.
  ParsedResponse parse({required String stdout, required String stderr});
}
