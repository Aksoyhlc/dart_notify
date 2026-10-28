import 'dart:convert';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final target = GotifyTarget(appToken: 'app-token');

  Future<(DeliveryResult, List<http.Request>)> send(
    NotifyMessage message, {
    GotifyConfig? config,
    GotifyOptions? options,
    http.Response Function(http.Request)? respond,
  }) async {
    final requests = <http.Request>[];
    final provider = GotifyProvider(
        id: 'gotify',
        config: config ??
            GotifyConfig(
                baseUrl: Uri.parse('https://push.example.com/gotify/')),
        client: MockClient((r) async {
          requests.add(r);
          return respond?.call(r) ?? http.Response(jsonEncode({'id': 5}), 200);
        }));
    final result = await DartNotify(destinations: []).sendDirect(message,
        provider: provider, target: target, options: options);
    return (result, requests);
  }

  test('app token goes in X-Gotify-Key, never in the URL', () async {
    final (result, requests) = await send(NotifyMessage(
        title: 'Disk', body: 'Full', priority: NotifyPriority.high));
    expect(result.isFullyAccepted, isTrue);
    expect(result.messageId, '5');
    final request = requests.single;
    expect(request.url.toString(), 'https://push.example.com/gotify/message');
    expect(request.headers['x-gotify-key'], 'app-token');
    expect(request.headers.containsKey('authorization'), isFalse);
    final payload = jsonDecode(request.body) as Map;
    expect(payload['title'], 'Disk');
    expect(payload['message'], 'Full');
    expect(payload['priority'], 8);
  });

  test('client token is sent separately as a Bearer token', () async {
    final (_, requests) = await send(NotifyMessage(body: 'x'),
        config: GotifyConfig(
            baseUrl: Uri.parse('https://push.example.com?tenant=a'),
            clientToken: 'proxy'));
    final request = requests.single;
    expect(request.url.toString(), 'https://push.example.com/message?tenant=a');
    expect(request.headers['x-gotify-key'], 'app-token');
    expect(request.headers['authorization'], 'Bearer proxy');
  });

  test('blank body falls back to htmlBody and markdown sets content type',
      () async {
    final (_, requests) = await send(NotifyMessage(body: '', htmlBody: '**x**'),
        options: GotifyOptions(markdown: true, priority: 1));
    final payload = jsonDecode(requests.single.body) as Map;
    expect(payload['message'], '**x**');
    expect(payload['priority'], 1);
    expect(payload['extras'], {
      'client::display': {'contentType': 'text/markdown'}
    });
  });

  test('a success without an ID is unknown', () async {
    final (result, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response('{}', 200));
    expect(result.status, DeliveryStatus.unknown);
    expect(result.error?.code, 'gotify_invalid_response');
  });

  test('client errors fail, server errors and timeouts are unknown', () async {
    final (rejected, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response('{"error":"Unauthorized"}', 401));
    expect(rejected.status, DeliveryStatus.failed);
    expect(rejected.error?.code, 'gotify_http_401');
    final (server, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => http.Response('', 500));
    expect(server.status, DeliveryStatus.unknown);
    final (network, _) = await send(NotifyMessage(body: 'x'),
        respond: (_) => throw http.ClientException('down'));
    expect(network.status, DeliveryStatus.unknown);
    expect(network.error?.code, 'gotify_network_error');
  });
}
