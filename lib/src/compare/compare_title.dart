/// Build a compact title from a prompt.
String buildCompareTitle(String prompt, {int maxLength = 80}) {
  final normalized = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength - 3)}...';
}
