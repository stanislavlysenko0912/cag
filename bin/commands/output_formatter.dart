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
}
