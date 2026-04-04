import 'package:cag/cag.dart';

class OutputFormatter {
  /// Prints a session start header with session_id.
  static void printSessionStart(String sessionId) {
    print('session_id: $sessionId');
    print('----');
  }

  /// Prints a metadata separator.
  static void printMetadataHeader() {
    print('\n---- metadata ----');
  }

  /// Prints a consensus session header.
  static void printConsensusStart(String consensusId, [String? title]) {
    print('consensus_id: $consensusId');
    if (title != null && title.isNotEmpty) {
      print('title: $title');
    }
    print('====\n');
  }

  /// Prints a compare run header.
  static void printCompareStart(String compareId, String title) {
    print('compare_id: $compareId');
    print('title: $title');
    print('====\n');
  }

  /// Prints a council run header.
  static void printCouncilStart(String councilId, String title) {
    print('council_id: $councilId');
    print('title: $title');
    print('====\n');
  }

  /// Prints a stage header.
  static void printStageHeader(String title) {
    print('==== $title ====');
  }

  /// Prints a participant header with agent, model, and stance.
  static void printParticipantHeader({
    required String agent,
    required String model,
    required String stance,
  }) {
    final header =
        '=== ${agent.toUpperCase()} ($model) [${stance.toUpperCase()}] ===';
    print(header);
  }

  /// Prints a participant header for compare runs.
  static void printCompareParticipantHeader({
    required String agent,
    required String model,
  }) {
    print('=== ${agent.toUpperCase()} ($model) ===');
  }

  /// Formats a date into a local human-readable string.
  static String formatLocalDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  static String formatFailure(AgentFailure failure) {
    return '${failure.summary}: ${failure.message}';
  }

  /// Formats a preview string for list output.
  static String formatPreview(String value, {int maxLength = 128}) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...';
  }

  /// Prints a compare list item.
  static void printCompareListItem(CompareRun run) {
    final participants = run.participants
        .map((participant) => participant.toString())
        .join(', ');
    print(
      '${run.compareId}  ${formatLocalDate(run.createdAt)}  ${run.successCount}/${run.results.length} ok  $participants',
    );
    print('  Title: ${run.title}');
  }

  /// Prints a council list item.
  static void printCouncilListItem(CouncilRun run) {
    final participants = run.participants
        .map((participant) => participant.toString())
        .join(', ');
    print(
      '${run.councilId}  ${formatLocalDate(run.createdAt)}  ${run.status}  $participants',
    );
    print('  Chairman: ${run.chairman}');
    print('  Title: ${run.title}');
  }

  /// Prints a consensus list item.
  static void printConsensusListItem(ConsensusSession session) {
    final participants = session.participants
        .map((participant) => participant.toString())
        .join(', ');
    print(
      '${session.consensusId}  ${formatLocalDate(session.createdAt)}  ${session.participants.length} participants  $participants',
    );
    if (session.title != null && session.title!.isNotEmpty) {
      print('  Title: ${session.title}');
    }
    if (session.proposal != null && session.proposal!.isNotEmpty) {
      print('  Proposal: ${formatPreview(session.proposal!)}');
    }
    print('  Prompt: ${formatPreview(session.prompt)}');
  }

  static void printFailure(AgentFailure failure) {
    print('ERROR [${failure.summary}]');
    print(failure.message);
  }
}
