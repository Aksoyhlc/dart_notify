import 'dart:convert';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final target = VerimorTarget(numbers: ['05321234567', '05331234567']);

  Future<(DeliveryResult, List<http.Request>)> send(
    NotifyMessage message, {
    VerimorOptions? options,
    http.Response Function(http.Request)? respond,
  }) async {
    final requests = <http.Request>[];
    final provider = VerimorProvider(
        id: 'verimor',
        config: VerimorConfig(
            username: '908501234567', password: 'pw', sourceAddr: 'BRAND'),
        client: MockClient((r) async {
          requests.add(r);
          return respond?.call(r) ?? http.Response('987654', 200);
        }));
    final result = await DartNotify(destinations: []).sendDirect(message,
        provider: provider, target: target, options: options);
    return (result, requests);
  }

  test('sends one message per recipient and returns the campaign ID', () async {
    final (result, requests) = await send(NotifyMessage(body: 'Kod: 1'),
        options: VerimorOptions(
            datacoding: VerimorDatacoding.gsmTurkish,
            validFor: const Duration(hours: 2, minutes: 30),
            sendAt: DateTime(2026, 11, 2, 9, 5, 7),
            customId: 'order-42',
            commercial: true,
            iysRecipientType: VerimorIysRecipientType.business));
    expect(result.isFullyAccepted, isTrue);
    expect(result.messageId, '987654');
    final payload = jsonDecode(requests.single.body) as Map;
    expect(payload['datacoding'], 1);
    expect(payload['valid_for'], '02:30');
    expect(payload['send_at'], '2026-11-02T09:05:07');
    expect(payload['custom_id'], 'order-42');
    expect(payload['is_commercial'], isTrue);
    expect(payload['iys_recipient_type'], 'TACIR');
    expect(payload['messages'], [
      for (final number in target.numbers) {'msg': 'Kod: 1', 'dest': number},
    ]);
  });

  test('options enforce whole minutes and a 50-character customId', () {
    expect(() => VerimorOptions(validFor: const Duration(seconds: 90)),
        throwsArgumentError);
    expect(VerimorOptions(customId: 'x' * 50).customId, hasLength(50));
    expect(() => VerimorOptions(customId: 'x' * 51), throwsArgumentError);
    expect(() => VerimorOptions(commercial: true), throwsArgumentError);
  });

  test('known error tokens are mapped, unknown text is not leaked', () async {
    final (known, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response('INSUFFICIENT_CREDITS', 400));
    expect(known.status, DeliveryStatus.failed);
    expect(known.error?.code, 'verimor_insufficient_credits');
    final (unknown, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response('user pw 908501234567 bad', 400));
    expect(unknown.error?.code, 'verimor_unknown_error');
    expect(unknown.error?.message, isNot(contains('908501234567')));
  });

  test('a non-numeric 2xx body is unknown, not failed', () async {
    final (result, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response('<html>maintenance</html>', 200));
    expect(result.status, DeliveryStatus.unknown);
    expect(result.error?.code, 'verimor_invalid_success_response');
  });

  test('status-specific failures', () async {
    final cases = {
      401: (DeliveryStatus.failed, 'verimor_unauthorized'),
      403: (DeliveryStatus.failed, 'verimor_ip_not_allowed'),
      429: (DeliveryStatus.failed, 'verimor_429'),
      503: (DeliveryStatus.unknown, 'verimor_http_503'),
    };
    for (final MapEntry(key: status, value: (expected, code))
        in cases.entries) {
      final (result, _) = await send(NotifyMessage(body: 'x'),
          respond: (_) => http.Response('', status));
      expect(result.status, expected, reason: '$status');
      expect(result.error?.code, code, reason: '$status');
    }
  });

  test('blank body and transport failure', () async {
    final (blank, requests) =
        await send(NotifyMessage(body: '', htmlBody: '<b>x</b>'));
    expect(blank.error?.code, 'verimor_invalid_body');
    expect(requests, isEmpty);
    final (network, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => throw http.ClientException('down'));
    expect(network.status, DeliveryStatus.unknown);
    expect(network.error?.code, 'verimor_network_error');
  });
}
