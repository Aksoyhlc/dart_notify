import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final target = DiscordTarget(
      webhookUrl: Uri.parse('https://discord.com/api/webhooks/1/token'));

  Future<(DeliveryResult, List<http.Request>)> send(
    NotifyMessage message, {
    DiscordOptions? options,
    http.Response Function(http.Request)? respond,
  }) async {
    final requests = <http.Request>[];
    final provider = DiscordProvider(
        id: 'discord',
        client: MockClient((r) async {
          requests.add(r);
          return respond?.call(r) ??
              http.Response(jsonEncode({'id': '99'}), 200);
        }));
    final result = await DartNotify(destinations: []).sendDirect(message,
        provider: provider, target: target, options: options);
    return (result, requests);
  }

  test('title is prepended to the content and wait=true returns the ID',
      () async {
    final (result, requests) =
        await send(NotifyMessage(title: 'Deploy', body: 'Done'));
    expect(result.isFullyAccepted, isTrue);
    expect(result.messageId, '99');
    expect(requests.single.url.queryParameters['wait'], 'true');
    final payload = jsonDecode(requests.single.body) as Map;
    expect(payload['content'], 'Deploy\nDone');
    expect(payload['allowed_mentions'], {'parse': <String>[]});
  });

  test('blank body falls back to htmlBody verbatim', () async {
    final (_, requests) =
        await send(NotifyMessage(body: '', htmlBody: '<b>Ready</b>'));
    expect(jsonDecode(requests.single.body)['content'], '<b>Ready</b>');
  });

  test('the 2000-character limit applies to title plus body', () async {
    final (result, requests) = await send(
        NotifyMessage(title: 'Title', body: 'x' * (2000 - 'Title\n'.length)));
    expect(result.isFullyAccepted, isTrue);
    final (rejected, none) = await send(
        NotifyMessage(title: 'Title', body: 'x' * (2001 - 'Title\n'.length)));
    expect(rejected.status, DeliveryStatus.failed);
    expect(rejected.error?.code, 'discord_content_too_long');
    expect(none, isEmpty);
    expect(requests, hasLength(1));
  });

  test('attachments are sent as multipart with payload_json', () async {
    final (result, requests) =
        await send(NotifyMessage(body: 'log', attachments: [
      NotifyAttachment(
          fileName: 'a.txt', bytes: Uint8List.fromList(utf8.encode('hi')))
    ]));
    expect(result.isFullyAccepted, isTrue);
    expect(requests.single.headers['content-type'],
        startsWith('multipart/form-data'));
    expect(requests.single.body, contains('name="payload_json"'));
    expect(requests.single.body, contains('name="files[0]"'));
  });

  test('a 200 without a message ID is unknown', () async {
    final (result, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response('{}', 200));
    expect(result.status, DeliveryStatus.unknown);
    expect(result.error?.code, 'discord_invalid_response');
  });

  test('429 reads retry_after from the JSON body', () async {
    final (result, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response(jsonEncode({'retry_after': 1.5}), 429));
    expect(result.status, DeliveryStatus.failed);
    expect(result.error?.code, 'discord_429');
    expect(result.error?.retryable, isTrue);
    expect(result.attempts, 1);
  });

  test('server errors are unknown and transport failures do not escape',
      () async {
    final (server, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response('', 502));
    expect(server.status, DeliveryStatus.unknown);
    expect(server.error?.code, 'discord_http_502');
    final (network, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => throw http.ClientException('down'));
    expect(network.status, DeliveryStatus.unknown);
    expect(network.error?.code, 'discord_network_error');
  });
}
