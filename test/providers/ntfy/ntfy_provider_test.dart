import 'dart:convert';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final target = NtfyTarget(topic: 'alerts');

  Future<(DeliveryResult, List<http.Request>)> send(
    NotifyMessage message, {
    NtfyConfig? config,
    NtfyOptions? options,
    http.Response Function(http.Request)? respond,
  }) async {
    final requests = <http.Request>[];
    final provider = NtfyProvider(
        id: 'ntfy',
        config: config,
        client: MockClient((r) async {
          requests.add(r);
          return respond?.call(r) ??
              http.Response(jsonEncode({'id': 'abc'}), 200);
        }));
    final result = await DartNotify(destinations: []).sendDirect(message,
        provider: provider, target: target, options: options);
    return (result, requests);
  }

  test('publishes JSON to the base URL with mapped priority', () async {
    final (result, requests) = await send(
        NotifyMessage(
            title: 'Disk', body: 'Full', priority: NotifyPriority.low),
        config: NtfyConfig(authToken: 'tk'),
        options:
            NtfyOptions(tags: ['warning'], delay: const Duration(minutes: 5)));
    expect(result.isFullyAccepted, isTrue);
    expect(result.messageId, 'abc');
    final request = requests.single;
    expect(request.url.toString(), 'https://ntfy.sh');
    expect(request.headers['authorization'], 'Bearer tk');
    expect(jsonDecode(request.body), {
      'topic': 'alerts',
      'message': 'Full',
      'title': 'Disk',
      'priority': 2,
      'tags': ['warning'],
      'delay': '5m',
    });
  });

  test('markdown prefers htmlBody; blank body falls back to it', () async {
    final (_, markdown) = await send(
        NotifyMessage(body: 'plain', htmlBody: '**md**'),
        options: NtfyOptions(markdown: true));
    final payload = jsonDecode(markdown.single.body) as Map;
    expect(payload['message'], '**md**');
    expect(payload['markdown'], isTrue);
    final (_, fallback) = await send(NotifyMessage(body: '', htmlBody: 'only'));
    expect(jsonDecode(fallback.single.body)['message'], 'only');
  });

  test('size limits are checked before any request', () async {
    final (title, none1) =
        await send(NotifyMessage(title: 'x' * 257, body: 'b'));
    expect(title.error?.code, 'ntfy_title_too_long');
    final (body, none2) = await send(NotifyMessage(body: 'ş' * 2049));
    expect(body.error?.code, 'ntfy_message_too_large');
    expect([...none1, ...none2], isEmpty);
  });

  test('429, server errors and transport failures', () async {
    final (limited, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response('', 429, headers: {'retry-after': '10'}));
    expect(limited.status, DeliveryStatus.failed);
    expect(limited.error?.code, 'ntfy_429');
    expect(limited.attempts, 1);
    final (server, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response('', 502));
    expect(server.status, DeliveryStatus.unknown);
    final (network, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => throw http.ClientException('down'));
    expect(network.error?.code, 'ntfy_network_error');
  });
}
