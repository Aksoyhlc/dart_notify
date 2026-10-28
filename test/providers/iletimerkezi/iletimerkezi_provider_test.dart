import 'dart:convert';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final target = IletimerkeziTarget(numbers: ['05321234567']);

  http.Response envelope(int code, {Object? orderId = '123'}) => http.Response(
      jsonEncode({
        'response': {
          'status': {'code': code, 'message': 'secret upstream text'},
          if (orderId != null) 'order': {'id': orderId},
        }
      }),
      200);

  Future<(DeliveryResult, List<http.Request>)> send(
    NotifyMessage message, {
    IletimerkeziOptions? options,
    String sender = 'BRAND',
    http.Response Function(http.Request)? respond,
  }) async {
    final requests = <http.Request>[];
    final provider = IletimerkeziProvider(
        id: 'iletimerkezi',
        config: IletimerkeziConfig(key: 'k', hash: 'h', sender: sender),
        client: MockClient((r) async {
          requests.add(r);
          return respond?.call(r) ?? envelope(200);
        }));
    final result = await DartNotify(destinations: []).sendDirect(message,
        provider: provider, target: target, options: options);
    return (result, requests);
  }

  test('sends the v1 envelope and returns the order ID', () async {
    final (result, requests) = await send(NotifyMessage(body: 'Kod: 1234'),
        options: IletimerkeziOptions(
            iys: IletimerkeziIys.commercialIndividual,
            sendAt: DateTime(2026, 11, 2, 9, 5)));
    expect(result.isFullyAccepted, isTrue);
    expect(result.messageId, '123');
    final order =
        (jsonDecode(requests.single.body) as Map)['request']['order'] as Map;
    expect(order['sender'], 'BRAND');
    expect(order['iys'], '1');
    expect(order['iysList'], 'BIREYSEL');
    expect(order['sendDateTime'], '02/11/2026 09:05');
    expect(order['message'], {
      'text': 'Kod: 1234',
      'receipents': {
        'number': target.numbers,
      },
    });
  });

  test('a blank text body is rejected before any request', () async {
    final (result, requests) =
        await send(NotifyMessage(body: '', htmlBody: '<b>x</b>'));
    expect(result.error?.code, 'iletimerkezi_invalid_body');
    expect(requests, isEmpty);
  });

  test('APITEST sender requires transactional IYS', () async {
    await expectLater(
        send(NotifyMessage(body: 'x'),
            sender: 'APITEST',
            options:
                IletimerkeziOptions(iys: IletimerkeziIys.commercialBusiness)),
        throwsArgumentError);
  });

  test('a business rejection is sanitized', () async {
    final (result, _) =
        await send(NotifyMessage(body: 'x'), respond: (_) => envelope(451));
    expect(result.status, DeliveryStatus.failed);
    expect(result.error?.code, 'iletimerkezi_451');
    expect(result.error?.message, isNot(contains('secret')));
  });

  test('a success without an order ID or a malformed body is unknown',
      () async {
    final (missing, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => envelope(200, orderId: null));
    expect(missing.status, DeliveryStatus.unknown);
    expect(missing.error?.code, 'iletimerkezi_invalid_response');
    final (html, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response('<html>', 200));
    expect(html.status, DeliveryStatus.unknown);
  });

  test('HTTP and transport failures', () async {
    final (server, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response('', 502));
    expect(server.status, DeliveryStatus.unknown);
    final (limited, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response('', 429));
    expect(limited.error?.code, 'iletimerkezi_429');
    final (network, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => throw http.ClientException('down'));
    expect(network.status, DeliveryStatus.unknown);
    expect(network.error?.code, 'iletimerkezi_network_error');
    expect(network.attempts, 1);
  });
}
