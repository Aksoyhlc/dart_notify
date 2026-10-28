import 'package:dart_notify/dart_notify.dart';
import 'package:test/test.dart';

void main() {
  test('rejects invalid retry settings at construction', () {
    expect(() => RetryPolicy(maxAttempts: 0), throwsArgumentError);
    expect(() => RetryPolicy(maxAttempts: -1), throwsArgumentError);
    expect(
      () => RetryPolicy(initialDelay: const Duration(milliseconds: -1)),
      throwsArgumentError,
    );
    expect(
      () => RetryPolicy(maxDelay: const Duration(milliseconds: -1)),
      throwsArgumentError,
    );
  });

  test('exponential delay is capped and Retry-After takes precedence', () {
    final policy = RetryPolicy(
      initialDelay: const Duration(milliseconds: 300),
      maxDelay: const Duration(seconds: 1),
    );
    expect(policy.delayFor(1), const Duration(milliseconds: 300));
    expect(policy.delayFor(2), const Duration(milliseconds: 600));
    expect(policy.delayFor(3), const Duration(seconds: 1));
    expect(policy.delayFor(10), const Duration(seconds: 1));
    expect(
      policy.delayFor(1, retryAfter: const Duration(seconds: 20)),
      const Duration(seconds: 20),
    );
  });
}
