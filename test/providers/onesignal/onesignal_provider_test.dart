import 'dart:convert';
import 'dart:io';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final message = NotifyMessage(title: 'Warning', body: 'CPU > 90%');
  OneSignalProvider provider(http.Client client) => OneSignalProvider(
        id: 'os',
        config: OneSignalConfig(appId: 'app-test', apiKey: 'secret-test'),
        client: client,
      );

  test('correct endpoint, auth, targeting, priority and idempotency', () async {
    late Map<String, dynamic> sent;
    final client = MockClient((request) async {
      expect(request.url.toString(),
          'https://api.onesignal.com/notifications?c=push');
      expect(request.headers['authorization'], 'Key secret-test');
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"id":"notification-1"}', 200);
    });
    final os = provider(client);
    final notify = DartNotify(destinations: [
      ProviderDestination(
        id: 'push',
        provider: os,
        target: OneSignalTarget.externalIds(['42']),
      ),
    ]);
    final result = (await notify.send(message, to: ['push'])).results.single;
    expect(result.status, DeliveryStatus.accepted);
    expect(result.messageId, 'notification-1');
    expect(sent['app_id'], 'app-test');
    expect(sent['target_channel'], 'push');
    expect((sent['include_aliases'] as Map)['external_id'], ['42']);
    expect((sent['headings'] as Map)['en'], 'Warning');
    expect((sent['contents'] as Map)['en'], 'CPU > 90%');
    expect(sent['idempotency_key'], isA<String>());
    expect((sent['idempotency_key'] as String).length, 36);
  });

  test('HTTP 200 no ID is skipped, not accepted', () async {
    final os = provider(MockClient((_) async =>
        http.Response('{"id":null,"errors":["No subscribers"]}', 200)));
    final report = await DartNotify(destinations: [
      ProviderDestination(
          id: 'p',
          provider: os,
          target: OneSignalTarget.externalIds(['missing'])),
    ]).send(message, to: ['p']);
    expect(report.results.single.status, DeliveryStatus.skipped);
    expect(report.isFullyAccepted, false);
  });

  test('HTTP 200 id plus errors is partially accepted', () async {
    final os = provider(MockClient((_) async =>
        http.Response('{"id":"ok","errors":{"invalid_aliases":["x"]}}', 200)));
    final result = await DartNotify(destinations: [
      ProviderDestination(
          id: 'p',
          provider: os,
          target: OneSignalTarget.externalIds(['x', 'y'])),
    ]).send(message, to: ['p']);
    expect(result.results.single.status, DeliveryStatus.partiallyAccepted);
    expect(result.results.single.messageId, 'ok');
    expect(result.hasFailures, isFalse);
    expect(result.isFullyAccepted, isFalse);
    expect(result.partialCount, 1);
  });

  test('429 retry preserves idempotency key, 401 does not retry', () async {
    final keys = <String>[];
    var calls = 0;
    final os = provider(MockClient((request) async {
      keys.add((jsonDecode(request.body) as Map)['idempotency_key'] as String);
      calls++;
      if (calls == 1) {
        return http.Response('rate limit', 429, headers: {'retry-after': '0'});
      }
      return http.Response('{"id":"success"}', 200);
    }));
    final report = await DartNotify(destinations: [
      ProviderDestination(
          id: 'push', provider: os, target: OneSignalTarget.externalIds(['x'])),
    ]).send(message, to: ['push']);
    expect(report.results.single.attempts, 2);
    expect(keys[0], keys[1]);
    expect(report.isFullyAccepted, isTrue);

    var authCalls = 0;
    final unauthorized = provider(MockClient((_) async {
      authCalls++;
      return http.Response('unauthorized', 401);
    }));
    final authReport = await DartNotify(destinations: [
      ProviderDestination(
          id: 'unauthorized',
          provider: unauthorized,
          target: OneSignalTarget.externalIds(['x'])),
    ]).send(message, to: ['unauthorized']);
    expect(authCalls, 1);
    expect(authReport.results.single.error!.httpStatus, 401);
  });

  test('mutually exclusive target mappings', () {
    expect(OneSignalTarget.subscriptionIds(['s']).toJson(), {
      'include_subscription_ids': ['s']
    });
    expect(OneSignalTarget.segments(['it'], excluded: ['inactive']).toJson(), {
      'included_segments': ['it'],
      'excluded_segments': ['inactive']
    });
    expect(
        OneSignalTarget.filters([
          {'field': 'tag', 'key': 'role', 'value': 'it'}
        ]).toJson(),
        {
          'filters': [
            {'field': 'tag', 'key': 'role', 'value': 'it'}
          ]
        });
  });

  test('empty and oversized target lists rejected', () {
    expect(() => OneSignalTarget.externalIds([]), throwsArgumentError);
    expect(
        () =>
            OneSignalTarget.subscriptionIds(List.generate(20001, (i) => '$i')),
        throwsArgumentError);
  });

  test('low priority uses the supported normal OneSignal priority', () async {
    final os = provider(MockClient((request) async {
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['priority'], 5);
      return http.Response('{"id":"low-priority"}', 200);
    }));
    final result = await DartNotify(destinations: []).sendDirect(
      NotifyMessage(body: 'Background alert', priority: NotifyPriority.low),
      provider: os,
      target: OneSignalTarget.externalIds(['42']),
    );
    expect(result.status, DeliveryStatus.accepted);
  });

  for (final body in ['{}', '{"id":42}', '{"id":"ok","errors":false}']) {
    test('malformed success envelope is unknown: $body', () async {
      final os = provider(MockClient((_) async => http.Response(body, 200)));
      final result = await DartNotify(destinations: []).sendDirect(
        message,
        provider: os,
        target: OneSignalTarget.externalIds(['42']),
      );
      expect(result.status, DeliveryStatus.unknown);
      expect(result.error?.code, 'onesignal_invalid_response');
    });
  }

  test('HTTP-date Retry-After overrides the normal retry delay', () async {
    var attempts = 0;
    final delays = <Duration>[];
    final retryDate =
        HttpDate.format(DateTime.now().toUtc().add(const Duration(days: 1)));
    final os = provider(MockClient((_) async {
      attempts++;
      if (attempts == 1) {
        return http.Response('Unavailable', 503,
            headers: {'retry-after': retryDate});
      }
      return http.Response('{"id":"recovered"}', 200);
    }));
    final result = await DartNotify(
      destinations: [],
      wait: (delay) async => delays.add(delay),
    ).sendDirect(message,
        provider: os, target: OneSignalTarget.externalIds(['42']));
    expect(result.isFullyAccepted, isTrue);
    expect(result.attempts, 2);
    expect(delays.single, greaterThan(const Duration(hours: 23)));
    expect(delays.single, lessThanOrEqualTo(const Duration(days: 1)));
  });

  test('an explicit empty notification ID is skipped', () async {
    final os = provider(MockClient((_) async =>
        http.Response('{"id":"","errors":["No subscribers"]}', 200)));
    final result = await DartNotify(destinations: []).sendDirect(
      message,
      provider: os,
      target: OneSignalTarget.externalIds(['missing']),
    );
    expect(result.status, DeliveryStatus.skipped);
    expect(result.error?.code, 'onesignal_no_recipients');
  });

  test('permanent transport uncertainty stops at the configured attempt limit',
      () async {
    final keys = <String>[];
    final os = provider(MockClient((request) async {
      keys.add((jsonDecode(request.body) as Map)['idempotency_key'] as String);
      throw http.ClientException('private network details');
    }));
    final result = await DartNotify(
      destinations: [],
      retryPolicy: RetryPolicy(maxAttempts: 2),
      wait: (_) async {},
    ).sendDirect(message,
        provider: os, target: OneSignalTarget.externalIds(['42']));
    expect(result.status, DeliveryStatus.unknown);
    expect(result.error?.code, 'onesignal_network_error');
    expect(result.attempts, 2);
    expect(keys, hasLength(2));
    expect(keys[0], keys[1]);
  });
}
