import 'dart:convert';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final target = SlackTarget(channel: 'C123');

  Future<(DeliveryResult, List<http.Request>)> send(
    NotifyMessage message, {
    SlackOptions? options,
    http.Response Function(http.Request)? respond,
  }) async {
    final requests = <http.Request>[];
    final provider = SlackProvider(
        id: 'slack',
        config: SlackConfig(token: 'xoxb-secret'),
        client: MockClient((r) async {
          requests.add(r);
          return respond?.call(r) ??
              http.Response(jsonEncode({'ok': true, 'ts': '1.2'}), 200);
        }));
    final result = await DartNotify(destinations: []).sendDirect(message,
        provider: provider, target: target, options: options);
    return (result, requests);
  }

  test('title is prepended to text and the token is a Bearer header', () async {
    final (result, requests) =
        await send(NotifyMessage(title: 'Deploy', body: 'Done'));
    expect(result.isFullyAccepted, isTrue);
    expect(result.messageId, '1.2');
    expect(requests.single.headers['authorization'], 'Bearer xoxb-secret');
    final payload = jsonDecode(requests.single.body) as Map;
    expect(payload['channel'], 'C123');
    expect(payload['text'], 'Deploy\nDone');
  });

  test('blank body falls back to htmlBody verbatim', () async {
    final (_, requests) =
        await send(NotifyMessage(body: '', htmlBody: '<b>Ready</b>'));
    expect(jsonDecode(requests.single.body)['text'], '<b>Ready</b>');
  });

  test('oversized block text is rejected before any request', () async {
    final (result, requests) = await send(NotifyMessage(body: 'fallback'),
        options: SlackOptions(blocks: [
          {
            'type': 'section',
            'text': {'type': 'mrkdwn', 'text': 'x' * 3001},
          }
        ]));
    expect(result.status, DeliveryStatus.failed);
    expect(result.error?.code, 'slack_invalid_blocks');
    expect(requests, isEmpty);
  });

  test('block text at the limit is sent', () async {
    final (result, requests) = await send(NotifyMessage(body: 'fallback'),
        options: SlackOptions(blocks: [
          {
            'type': 'section',
            'text': {'type': 'mrkdwn', 'text': 'x' * 3000},
          }
        ]));
    expect(result.isFullyAccepted, isTrue);
    expect(jsonDecode(requests.single.body)['blocks'], hasLength(1));
  });

  test('ok:false is a sanitized failure', () async {
    final (result, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response(
            jsonEncode({'ok': false, 'error': 'channel_not_found'}), 200));
    expect(result.status, DeliveryStatus.failed);
    expect(result.error?.code, 'slack_channel_not_found');
  });

  test('server errors are unknown and transport failures do not escape',
      () async {
    final (server, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response('', 503));
    expect(server.status, DeliveryStatus.unknown);
    final (network, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => throw http.ClientException('down'));
    expect(network.status, DeliveryStatus.unknown);
    expect(network.error?.code, 'slack_network_error');
    expect(network.attempts, 1);
  });
}
