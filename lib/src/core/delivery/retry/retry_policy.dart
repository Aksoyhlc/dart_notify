/// Only safe, retryable errors are retried. SMTP deliberately opts out.
final class RetryPolicy {
  RetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 300),
    this.maxDelay = const Duration(seconds: 10),
  }) {
    if (maxAttempts < 1) {
      throw ArgumentError.value(
          maxAttempts, 'maxAttempts', 'Must be positive.');
    }
    if (initialDelay.isNegative || maxDelay.isNegative) {
      throw ArgumentError('Retry delays must not be negative.');
    }
  }

  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;

  Duration delayFor(int failedAttempt, {Duration? retryAfter}) {
    if (retryAfter != null && !retryAfter.isNegative) return retryAfter;
    var delayMs = initialDelay.inMilliseconds;
    final capMs = maxDelay.inMilliseconds;
    for (var i = 1; i < failedAttempt; i++) {
      delayMs = (delayMs * 2).clamp(0, capMs).toInt();
    }
    return Duration(milliseconds: delayMs.clamp(0, capMs).toInt());
  }
}
