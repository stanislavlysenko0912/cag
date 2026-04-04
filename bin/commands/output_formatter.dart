class OutputFormatter {
  static void printSessionStart(String sessionId) {
    print('session_id: $sessionId');
    print('----');
  }

  static void printMetadataHeader() {
    print('\n---- metadata ----');
  }

  static void printConsensusStart(String consensusId) {
    print('consensus_id: $consensusId');
    print('====\n');
  }

  static void printCompareStart(String compareId, String title) {
    print('compare_id: $compareId');
    print('title: $title');
    print('====\n');
  }

  static void printStageHeader(String title) {
    print('==== $title ====');
  }

  static void printParticipantHeader({
    required String agent,
    required String model,
    required String stance,
  }) {
    final header =
        '=== ${agent.toUpperCase()} ($model) [${stance.toUpperCase()}] ===';
    print(header);
  }

  static void printCompareParticipantHeader({
    required String agent,
    required String model,
  }) {
    print('=== ${agent.toUpperCase()} ($model) ===');
  }

  static String formatLocalDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }
}
