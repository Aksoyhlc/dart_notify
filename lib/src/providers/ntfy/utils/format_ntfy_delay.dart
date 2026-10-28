/// Formats a positive delay using ntfy's duration syntax.
String formatNtfyDelay(Duration delay) {
  if (delay <= Duration.zero) {
    throw ArgumentError('Ntfy delay must be positive.');
  }
  final seconds = delay.inSeconds;
  if (seconds < 60) return '${seconds}s';
  final minutes = delay.inMinutes;
  if (minutes < 60) return '${minutes}m';
  final hours = delay.inHours;
  if (hours < 24) return '${hours}h';
  return '${delay.inDays}d';
}
