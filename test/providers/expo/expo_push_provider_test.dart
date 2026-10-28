import 'dart:convert';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  List<String> tokens(int count) =>
      [for (var i = 0; i < count; i++) 'ExpoPushToken[t$i]'];

  http.Response tickets(List<Map<String, Object?>> data) =>
      http.Response(jsonEncode({'data': data}), 200);

  Map<String, Object?> ok(int i) => {'status': 'ok', 'id': 'ticket-$i'};

  Future<(DeliveryResult, List<http.Request>)> send(
    int count,
    http.Response Function(http.Request request, int call) respond, {
    NotifyMessage? message,
    ExpoPushConfig config = const ExpoPushConfig(),
  }) async {
    final requests = <http.Request>[];
    final provider = ExpoPushProvider(
        id: 'expo',
        config: config,
        client: MockClient((r) async {
          requests.add(r);
          return respond(r, requests.length);
        }));
    final result = await DartNotify(destinations: []).sendDirect(
        message ?? NotifyMessage(title: 'Hi', body: 'There'),
        provider: provider,
        target: ExpoPushTarget(tokens: tokens(count)));
    return (result, requests);
  }

  List<Map<String, Object?>> okBatch(http.Request request) {
    final sent = jsonDecode(request.body) as List;
    return [for (var i = 0; i < sent.length; i++) ok(i)];
  }

  test('a single token is accepted with its ticket ID', () async {
    final (result, requests) = await send(1, (_, __) => tickets([ok(0)]),
        config: const ExpoPushConfig(accessToken: 'secret'));
    expect(result.isFullyAccepted, isTrue);
    expect(result.messageId, 'ticket-0');
    expect(requests.single.headers['authorization'], 'Bearer secret');
    final sent = jsonDecode(requests.single.body) as List;
    expect(sent.single, containsPair('to', 'ExpoPushToken[t0]'));
    expect(sent.single, containsPair('title', 'Hi'));
    expect(sent.single, containsPair('body', 'There'));
  });

  test('blank body falls back to htmlBody', () async {
    final (_, requests) = await send(1, (_, __) => tickets([ok(0)]),
        message: NotifyMessage(body: '', htmlBody: 'html'));
    expect((jsonDecode(requests.single.body) as List).single['body'], 'html');
  });

  test('more than 100 tokens are split into batches', () async {
    final (result, requests) = await send(150, (r, _) => tickets(okBatch(r)));
    expect(result.isFullyAccepted, isTrue);
    expect(result.messageId, isNull);
    expect([for (final r in requests) (jsonDecode(r.body) as List).length],
        [100, 50]);
  });

  test('mixed ticket results are partially accepted without leaking tokens',
      () async {
    final (result, _) = await send(
        2,
        (_, __) => tickets([
              ok(0),
              {
                'status': 'error',
                'message': 'ExpoPushToken[t1] is not registered',
                'details': {'error': 'DeviceNotRegistered'},
              },
            ]));
    expect(result.status, DeliveryStatus.partiallyAccepted);
    expect(result.error?.code, 'expo_device_not_registered');
    expect(result.error?.message, 'token[1]=expo_device_not_registered');
    expect(result.error?.message, isNot(contains('ExpoPushToken')));
  });

  test('a timeout after an accepted batch is returned, not thrown', () async {
    final (result, requests) = await send(150, (r, call) {
      if (call == 2) throw http.ClientException('reset');
      return tickets(okBatch(r));
    });
    expect(requests, hasLength(2));
    expect(result.status, DeliveryStatus.partiallyAccepted);
    expect(result.error?.code, 'expo_partial_batch');
    expect(result.error?.retryable, isFalse);
    expect(result.error?.message, contains('expo_network_error'));
    expect(result.error?.message, contains('accepted token indexes 0-99'));
    expect(result.error?.message,
        contains('uncertain or unsubmitted token indexes 100-149'));
  });

  test('a transport failure before any acceptance is unknown', () async {
    final (result, _) =
        await send(2, (_, __) => throw http.ClientException('down'));
    expect(result.status, DeliveryStatus.unknown);
    expect(result.error?.code, 'expo_network_error');
    expect(result.error?.message, contains('token indexes 0-1'));
    expect(result.attempts, 1);
  });

  test('a malformed ticket mid-batch keeps earlier acceptances', () async {
    final (result, _) = await send(
        3,
        (_, __) => tickets([
              ok(0),
              {'status': 'ok'},
              ok(2),
            ]));
    expect(result.status, DeliveryStatus.partiallyAccepted);
    expect(result.error?.code, 'expo_partial_batch');
    expect(result.error?.message, contains('accepted token indexes 0;'));
    expect(result.error?.message,
        contains('uncertain or unsubmitted token indexes 1-2'));
  });

  test('rate-limited tickets for every token are retryable failures', () async {
    final (result, _) = await send(
        2,
        (_, __) => tickets([
              for (var i = 0; i < 2; i++)
                {
                  'status': 'error',
                  'details': {'error': 'MessageRateExceeded'},
                },
            ]));
    expect(result.status, DeliveryStatus.failed);
    expect(result.error?.code, 'expo_message_rate_exceeded');
    expect(result.error?.retryable, isTrue);
  });

  test('HTTP failures map to failed, unknown and rate limited', () async {
    final (rejected, _) = await send(
        1,
        (_, __) => http.Response(
            jsonEncode({
              'errors': [
                {'code': 'PUSH_TOO_MANY_EXPERIENCE_IDS', 'message': 'x'}
              ]
            }),
            400));
    expect(rejected.status, DeliveryStatus.failed);
    expect(rejected.error?.code, 'expo_push_too_many_experience_ids');
    final (server, _) = await send(1, (_, __) => http.Response('', 503));
    expect(server.status, DeliveryStatus.unknown);
    final (limited, _) = await send(1, (_, __) => http.Response('', 429));
    expect(limited.error?.code, 'expo_429');
  });
}
