/// Build the review prompt for council members.
///
/// Returns a strict-format instruction for ranking and critique.
String buildCouncilReviewPrompt({
  required String question,
  required List<CouncilAnswer> answers,
}) {
  final buffer = StringBuffer();
  buffer.writeln(
    'You are evaluating different responses to the following question:',
  );
  buffer.writeln();
  buffer.writeln('Question: $question');
  buffer.writeln();
  buffer.writeln('Here are the responses from different models (anonymized):');
  buffer.writeln();
  for (final answer in answers) {
    buffer.writeln('Response ${answer.answerId}:');
    buffer.writeln(answer.content);
    buffer.writeln();
  }
  buffer.writeln('Your task:');
  buffer.writeln(
    '1. First, evaluate each response individually. For each response, explain what it does well and what it does poorly.',
  );
  buffer.writeln(
    '2. Then, at the very end of your response, provide a final ranking.',
  );
  buffer.writeln();
  buffer.writeln(
    'IMPORTANT: Your final ranking MUST be formatted EXACTLY as follows:',
  );
  buffer.writeln(
    '- Start with the line "FINAL RANKING:" (all caps, with colon)',
  );
  buffer.writeln(
    '- Then list the responses from best to worst as a numbered list',
  );
  buffer.writeln(
    '- Each line should be: number, period, space, then ONLY the response label (e.g., "1. Response ans_1")',
  );
  buffer.writeln(
    '- Do not add any other text or explanations in the ranking section',
  );
  buffer.writeln();
  buffer.writeln('Example of the correct format for your ENTIRE response:');
  buffer.writeln();
  buffer.writeln('Response ans_1 provides good detail on X but misses Y...');
  buffer.writeln('Response ans_2 is accurate but lacks depth on Z...');
  buffer.writeln('Response ans_3 offers the most comprehensive answer...');
  buffer.writeln();
  buffer.writeln('FINAL RANKING:');
  for (var i = 0; i < answers.length; i++) {
    buffer.writeln('${i + 1}. Response ${answers[i].answerId}');
  }
  buffer.writeln();
  buffer.writeln('Now provide your evaluation and ranking:');
  return buffer.toString();
}

/// Build the chairman prompt that synthesizes the final answer.
///
/// Returns a synthesis instruction using answers and reviews.
String buildCouncilChairmanPrompt({
  required String question,
  required List<CouncilAnswer> answers,
  required List<CouncilReview> reviews,
}) {
  final buffer = StringBuffer();
  buffer.writeln(
    'You are the Chairman of an LLM Council. Multiple AI models have provided responses to a user\'s question, and then ranked each other\'s responses.',
  );
  buffer.writeln();
  buffer.writeln('Original Question: $question');
  buffer.writeln();
  buffer.writeln('STAGE 1 - Individual Responses:');
  for (final answer in answers) {
    buffer.writeln('Model: ${answer.label}');
    buffer.writeln('Response: ${answer.content}');
    buffer.writeln();
  }
  buffer.writeln('STAGE 2 - Peer Rankings:');
  for (final review in reviews) {
    buffer.writeln('Model: ${review.reviewerLabel}');
    buffer.writeln('Ranking: ${review.content}');
    buffer.writeln();
  }
  buffer.writeln(
    'Your task as Chairman is to synthesize all of this information into a single, comprehensive, accurate answer to the user\'s original question. Consider:',
  );
  buffer.writeln('- The individual responses and their insights');
  buffer.writeln(
    '- The peer rankings and what they reveal about response quality',
  );
  buffer.writeln('- Any patterns of agreement or disagreement');
  buffer.writeln();
  buffer.writeln(
    'Provide a clear, well-reasoned final answer that represents the council\'s collective wisdom:',
  );
  return buffer.toString();
}

/// A labeled answer for council prompts.
///
/// Used to keep answers anonymous and ordered.
class CouncilAnswer {
  /// Creates a labeled answer.
  ///
  /// The label should be "Answer A", "Answer B", etc.
  CouncilAnswer({
    required this.answerId,
    required this.label,
    required this.content,
  });

  /// Stable answer identifier (e.g., "ans_1").
  final String answerId;

  /// Label like "Answer A".
  final String label;

  /// Answer content.
  final String content;
}

/// A labeled review for council prompts.
///
/// Used to pass peer reviews into the chairman stage.
class CouncilReview {
  /// Creates a labeled review.
  ///
  /// The label should identify the reviewer.
  CouncilReview({required this.reviewerLabel, required this.content});

  /// Label for the reviewer (e.g., "GEMINI (pro)").
  final String reviewerLabel;

  /// Review content.
  final String content;
}
