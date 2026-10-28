import 'dart:async';

import 'package:dart_notify/dart_notify.dart';
import 'package:test/test.dart';

import '../../support/core/fake_provider.dart';
import '../../support/core/fake_target.dart';
import '../../support/core/utils/destination.dart';

void main() {
  final message = NotifyMessage(body: 'Alert');

  test('widened provider target mismatches fail at construction', () {
    expect(
      () => ProviderDestination<NotificationTarget, NotificationOptions>(
        id: 'invalid',
        provider: FakeProvider(id: 'fake'),
        target: EmailTarget(to: [EmailAddress('ops@example.com')]),
      ),
      throwsArgumentError,
    );
  });

  test('concurrent batch and direct sends share the same delivery limit',
      () async {
    var active = 0;
    var peak = 0;
    final entered = Completer<void>();
    final release = Completer<void>();
    final provider = FakeProvider(
      id: 'blocking',
      behavior: (_) async {
        active++;
        if (active > peak) peak = active;
        if (active == 2 && !entered.isCompleted) entered.complete();
        await release.future;
        active--;
        return const ProviderResponse.accepted();
      },
    );
    final notify = DartNotify(
      destinations: [dest('a', provider), dest('b', provider)],
      maxConcurrent: 2,
    );
    final first = notify.send(message, to: ['a', 'b']);
    await entered.future;
    final second = notify.send(message, to: ['b', 'a']);
    final direct = notify.sendDirect(
      message,
      provider: provider,
      target: const FakeTarget('direct'),
    );
    await Future<void>.delayed(Duration.zero);
    final peakWhileBlocked = peak;
    release.complete();
    final reports = await Future.wait([first, second]);
    final directResult = await direct;
    expect(peakWhileBlocked, 2);
    expect(peak, 2);
    expect(reports.expand((r) => r.results), hasLength(4));
    expect(directResult.status, DeliveryStatus.accepted);
  });

  test('partial acceptance is not full success for an individual delivery',
      () async {
    final provider = FakeProvider(
      id: 'partial',
      behavior: (_) async => const ProviderResponse(
        status: DeliveryStatus.partiallyAccepted,
      ),
    );
    final report = await DartNotify(destinations: [dest('a', provider)])
        .send(message, to: ['a']);
    expect(report.results.single.isFullyAccepted, isFalse);
  });

  test('returned unknown responses honor Retry-After and preserve idempotency',
      () async {
    final provider = FakeProvider(
      id: 'retry',
      behavior: (context) async => context.attempt == 1
          ? const ProviderResponse(
              status: DeliveryStatus.unknown,
              error: DeliveryError(
                  code: 'lost', message: 'Lost response', retryable: true),
              retryAfter: Duration(seconds: 7),
            )
          : const ProviderResponse.accepted(messageId: 'recovered'),
    );
    final delays = <Duration>[];
    final report = await DartNotify(
      destinations: [dest('a', provider)],
      wait: (delay) async => delays.add(delay),
    ).send(message, to: ['a']);
    expect(report.isFullyAccepted, isTrue);
    expect(report.results.single.messageId, 'recovered');
    expect(report.results.single.attempts, 2);
    expect(delays, [const Duration(seconds: 7)]);
    expect(provider.calls[0].idempotencyKey, provider.calls[1].idempotencyKey);
  });

  test('accepted and partially accepted responses are never retried', () async {
    for (final status in [
      DeliveryStatus.accepted,
      DeliveryStatus.partiallyAccepted
    ]) {
      final provider = FakeProvider(
        id: 'accepted',
        behavior: (_) async => ProviderResponse(
          status: status,
          error: const DeliveryError(
              code: 'hint', message: 'Warning', retryable: true),
        ),
      );
      final result = await DartNotify(destinations: []).sendDirect(
        message,
        provider: provider,
        target: const FakeTarget('user'),
      );
      expect(result.status, status);
      expect(result.attempts, 1);
    }
  });

  test('a retrying delivery retains its slot until all attempts finish',
      () async {
    final waiting = Completer<void>();
    final release = Completer<void>();
    final provider = FakeProvider(
      id: 'retry',
      behavior: (context) async => context.attempt == 1
          ? const ProviderResponse(
              status: DeliveryStatus.failed,
              error:
                  DeliveryError(code: 'busy', message: 'Busy', retryable: true),
            )
          : const ProviderResponse.accepted(),
    );
    final notify = DartNotify(
      destinations: [dest('a', provider)],
      maxConcurrent: 1,
      wait: (_) async {
        if (!waiting.isCompleted) waiting.complete();
        await release.future;
      },
    );
    final first = notify.send(message, to: ['a']);
    await waiting.future;
    final second = notify.sendDirect(
      message,
      provider: provider,
      target: const FakeTarget('second'),
    );
    await Future<void>.delayed(Duration.zero);
    final callsWhileWaiting = provider.calls.length;
    release.complete();
    await first;
    await second;
    expect(callsWhileWaiting, 1);
    expect(provider.calls.map((c) => c.attempt), [1, 2, 1, 2]);
    expect(provider.calls[0].idempotencyKey, provider.calls[1].idempotencyKey);
    expect(provider.calls[2].idempotencyKey,
        isNot(provider.calls[0].idempotencyKey));
  });

  test(
      'unexpected diagnostics preserve the cause without exposing it in reports',
      () async {
    final cause = StateError('secret-api-key');
    final stack = StackTrace.fromString('original-provider-stack');
    final diagnostics = <DeliveryDiagnostic>[];
    final provider = FakeProvider(
      id: 'broken',
      behavior: (_) async => Error.throwWithStackTrace(cause, stack),
    );
    final notify = DartNotify(
      destinations: [dest('alerts', provider)],
      onUnexpectedError: diagnostics.add,
    );
    final report = await notify.send(message, to: ['alerts']);
    final diagnostic = diagnostics.single;
    expect(diagnostic.error, same(cause));
    expect(diagnostic.stackTrace.toString(), 'original-provider-stack');
    expect(diagnostic.destinationId, 'alerts');
    expect(diagnostic.providerId, 'broken');
    expect(diagnostic.attempt, 1);
    expect(report.results.single.error?.code, 'unexpected_error');
    expect(report.results.single.error.toString(),
        isNot(contains('secret-api-key')));
  });

  test(
      'diagnostic observer failures release slots and do not stop queued sends',
      () async {
    final broken = FakeProvider(
        id: 'broken', behavior: (_) async => throw StateError('bug'));
    final healthy = FakeProvider(id: 'healthy');
    final notify = DartNotify(
      destinations: [dest('broken', broken), dest('healthy', healthy)],
      maxConcurrent: 1,
      onUnexpectedError: (_) => throw StateError('observer bug'),
    );
    final first = notify.send(message, to: ['broken']);
    final second = notify.sendDirect(
      message,
      provider: healthy,
      target: const FakeTarget('second'),
    );
    expect((await first).results.single.status, DeliveryStatus.unknown);
    expect((await second).isFullyAccepted, isTrue);
  });

  test('expected provider rejections do not trigger unexpected diagnostics',
      () async {
    final diagnostics = <DeliveryDiagnostic>[];
    final provider = FakeProvider(
      id: 'rejected',
      behavior: (_) async => throw const NotifyDeliveryException(
        status: DeliveryStatus.failed,
        error: DeliveryError(code: 'unauthorized', message: 'Unauthorized'),
      ),
    );
    final result = await DartNotify(
      destinations: [],
      onUnexpectedError: diagnostics.add,
    ).sendDirect(message, provider: provider, target: const FakeTarget('user'));
    expect(result.status, DeliveryStatus.failed);
    expect(diagnostics, isEmpty);
  });

  test('queued batch and direct sends are admitted in FIFO order', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final starts = <String>[];
    final blocker = FakeProvider(
        id: 'block',
        behavior: (_) async {
          starts.add('block');
          entered.complete();
          await release.future;
          return const ProviderResponse.accepted();
        });
    FakeProvider recording(String id) => FakeProvider(
        id: id,
        behavior: (_) async {
          starts.add(id);
          return const ProviderResponse.accepted();
        });
    final notify = DartNotify(
        destinations: [dest('batch', recording('batch'))], maxConcurrent: 1);
    final first = notify.sendDirect(message,
        provider: blocker, target: const FakeTarget('block'));
    await entered.future;
    final second = notify.sendDirect(message,
        provider: recording('second'), target: const FakeTarget('second'));
    final batch = notify.send(message, to: ['batch']);
    final last = notify.sendDirect(message,
        provider: recording('last'), target: const FakeTarget('last'));
    release.complete();
    await Future.wait<Object>([first, second, batch, last]);
    expect(starts, ['block', 'second', 'batch', 'last']);
  });
}
