import 'package:dart_notify/dart_notify.dart';
import 'package:test/test.dart';

import '../../support/core/fake_provider.dart';
import '../../support/core/fake_target.dart';
import '../../support/core/utils/destination.dart';

void main() {
  final message = NotifyMessage(title: 'Alert', body: 'Server down');

  test('multi-destination dispatch preserves order', () async {
    final a = FakeProvider(id: 'a');
    final b = FakeProvider(id: 'b');
    final notify = DartNotify(destinations: [dest('push', a), dest('mail', b)]);
    final report = await notify.send(message, to: ['mail', 'push']);
    expect(report.results.map((r) => r.destinationId), ['mail', 'push']);
    expect(report.isFullyAccepted, isTrue);
    expect(a.calls.length, 1);
    expect(b.calls.length, 1);
  });

  test('same group + explicit destination only dispatches once', () async {
    final p = FakeProvider(id: 'push');
    final notify = DartNotify(
      destinations: [dest('one', p)],
      groups: {
        'team': ['one']
      },
    );
    final report = await notify.send(message, to: ['one'], groups: ['team']);
    expect(report.results, hasLength(1));
    expect(p.calls, hasLength(1));
  });

  test('invalid group/destination prevents sending anything', () async {
    final p = FakeProvider(id: 'p');
    final notify = DartNotify(destinations: [dest('one', p)]);
    await expectLater(
      notify.send(message, to: ['one', 'unknown']),
      throwsArgumentError,
    );
    expect(p.calls, isEmpty);
  });

  test('duplicate destination IDs rejected', () {
    final p = FakeProvider(id: 'p');
    expect(() => DartNotify(destinations: [dest('a', p), dest('a', p)]),
        throwsArgumentError);
  });

  test('at least one target required', () async {
    final notify = DartNotify(destinations: []);
    await expectLater(notify.send(message), throwsArgumentError);
  });

  test('provider error does not block other providers', () async {
    final fail = FakeProvider(
      id: 'fail',
      behavior: (_) async => const ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(code: 'bad', message: 'Rejected'),
      ),
    );
    final ok = FakeProvider(id: 'ok');
    final notify = DartNotify(destinations: [dest('a', fail), dest('b', ok)]);
    final report = await notify.send(message, to: ['a', 'b']);
    expect(report.isPartiallyAccepted, isTrue);
    expect(report.acceptedCount, 1);
    expect(report.failedCount, 1);
  });

  test('idempotency key stable over retries, unique across sends', () async {
    final p = FakeProvider(
      id: 'push',
      behavior: (context) async {
        if (context.attempt == 1) {
          throw const NotifyDeliveryException(
            status: DeliveryStatus.failed,
            error: DeliveryError(
              code: '429',
              message: 'Throttle',
              retryable: true,
            ),
          );
        }
        return const ProviderResponse.accepted();
      },
    );
    final delays = <Duration>[];
    final notify = DartNotify(
      destinations: [dest('d', p)],
      retryPolicy: RetryPolicy(maxAttempts: 2),
      wait: (d) async => delays.add(d),
    );
    final one = await notify.send(message, to: ['d']);
    expect(one.results.single.attempts, 2);
    expect(p.calls[0].idempotencyKey, p.calls[1].idempotencyKey);
    expect(delays, hasLength(1));
    await notify.send(message, to: ['d']);
    expect(p.calls[2].idempotencyKey, isNot(p.calls[0].idempotencyKey));
  });

  test('unsafe provider is not retried even if error is retryable', () async {
    final p = FakeProvider(
      id: 'smtp',
      retrySafe: false,
      behavior: (_) async => throw const NotifyDeliveryException(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'connection_lost',
          message: 'Unknown',
          retryable: true,
        ),
      ),
    );
    final notify = DartNotify(destinations: [dest('email', p)]);
    final report = await notify.send(message, to: ['email']);
    expect(p.calls, hasLength(1));
    expect(report.results.single.status, DeliveryStatus.unknown);
  });

  test('unexpected exception is sanitized', () async {
    final p = FakeProvider(
      id: 'custom',
      behavior: (_) async => throw StateError('private-api-key-123'),
    );
    final notify = DartNotify(destinations: [dest('target', p)]);
    final result = (await notify.send(message, to: ['target'])).results.single;
    expect(result.error!.message, isNot(contains('private-api-key')));
    expect(result.status, DeliveryStatus.unknown);
  });

  test('direct send supports typed targets without registration', () async {
    final p = FakeProvider(id: 'custom');
    final notify = DartNotify(destinations: []);
    final result = await notify.sendDirect(
      message,
      provider: p,
      target: const FakeTarget('dynamic-user'),
    );
    expect(result.isFullyAccepted, isTrue);
    expect(result.destinationId, 'direct');
  });
}
