import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final target = TelegramTarget(chatId: '-100123');
  final ok = jsonEncode({
    'ok': true,
    'result': {'message_id': 7},
  });

  Future<(DeliveryResult, List<http.Request>)> send(
    NotifyMessage message, {
    TelegramOptions? options,
    http.Response Function(http.Request)? respond,
  }) async {
    final requests = <http.Request>[];
    final provider = TelegramProvider(
        id: 'telegram',
        config: TelegramConfig(botToken: '123:abc'),
        client: MockClient((r) async {
          requests.add(r);
          return respond?.call(r) ?? http.Response(ok, 200);
        }));
    final result = await DartNotify(destinations: []).sendDirect(message,
        provider: provider, target: target, options: options);
    return (result, requests);
  }

  test('plain mode prepends the title unescaped', () async {
    final (result, requests) =
        await send(NotifyMessage(title: 'A <b> & c.', body: 'Done'));
    expect(result.isFullyAccepted, isTrue);
    expect(result.messageId, '7');
    expect(requests.single.url.path, '/bot123:abc/sendMessage');
    final payload = jsonDecode(requests.single.body) as Map;
    expect(payload['text'], 'A <b> & c.\nDone');
    expect(payload.containsKey('parse_mode'), isFalse);
  });

  test('HTML mode escapes the title and prefers htmlBody', () async {
    final (_, requests) = await send(
        NotifyMessage(title: 'A <b> & c', body: 'plain', htmlBody: '<i>x</i>'),
        options: TelegramOptions(parseMode: TelegramParseMode.html));
    final payload = jsonDecode(requests.single.body) as Map;
    expect(payload['text'], 'A &lt;b&gt; &amp; c\n<i>x</i>');
    expect(payload['parse_mode'], 'HTML');
  });

  test('MarkdownV2 mode escapes reserved characters in the title', () async {
    final (_, requests) = await send(
        NotifyMessage(title: 'v1.2_(beta)!', body: '*bold*'),
        options: TelegramOptions(parseMode: TelegramParseMode.markdownV2));
    expect(jsonDecode(requests.single.body)['text'],
        r'v1\.2\_\(beta\)\!' '\n*bold*');
  });

  test('the 4096-character limit applies to title plus body', () async {
    final (result, requests) = await send(
        NotifyMessage(title: 'T', body: 'x' * (4097 - 'T\n'.length)));
    expect(result.error?.code, 'telegram_message_too_long');
    expect(requests, isEmpty);
  });

  test('an attachment becomes a document with the composed caption', () async {
    final (result, requests) = await send(
        NotifyMessage(title: 'Report', body: 'attached', attachments: [
      NotifyAttachment(
          fileName: 'r.csv', bytes: Uint8List.fromList(utf8.encode('a,b')))
    ]));
    expect(result.isFullyAccepted, isTrue);
    expect(requests.single.url.path, '/bot123:abc/sendDocument');
    expect(requests.single.body, contains('Report\nattached'));
  });

  test('ok:true without a message ID is unknown', () async {
    final (result, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response(jsonEncode({'ok': true}), 200));
    expect(result.status, DeliveryStatus.unknown);
    expect(result.error?.code, 'telegram_invalid_response');
  });

  test('429 uses parameters.retry_after', () async {
    final (result, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response(
            jsonEncode({
              'ok': false,
              'error_code': 429,
              'parameters': {'retry_after': 3},
            }),
            429));
    expect(result.status, DeliveryStatus.failed);
    expect(result.error?.code, 'telegram_429');
    expect(result.error?.retryable, isTrue);
  });

  test('upstream rejection and transport failure are sanitized', () async {
    final (rejected, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response(
            jsonEncode({
              'ok': false,
              'error_code': 400,
              'description': 'Bad Request: chat 123:abc not found',
            }),
            400));
    expect(rejected.status, DeliveryStatus.failed);
    expect(rejected.error?.code, 'telegram_400');
    expect(rejected.error?.message, isNot(contains('123:abc')));
    final (network, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => throw http.ClientException('down'));
    expect(network.status, DeliveryStatus.unknown);
    expect(network.error?.code, 'telegram_network_error');
  });
}
