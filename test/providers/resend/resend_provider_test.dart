import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final from = EmailAddress('alerts@example.com', name: 'Alerts');
  final defaultTarget = EmailTarget(to: [EmailAddress('ops@example.com')]);

  Future<(DeliveryResult, List<http.Request>)> send(
    NotifyMessage message, {
    ResendConfig? config,
    EmailTarget? emailTarget,
    EmailOptions? options,
    int maxAttempts = 1,
    http.Response Function(http.Request request, int call)? respond,
  }) async {
    final requests = <http.Request>[];
    final provider = ResendProvider(
      id: 'resend',
      config: config ?? ResendConfig(apiKey: 're_secret', from: from),
      client: MockClient((request) async {
        requests.add(request);
        return respond?.call(request, requests.length) ??
            http.Response(jsonEncode({'id': 'email-1'}), 200);
      }),
    );
    final result = await DartNotify(
      destinations: [],
      retryPolicy: RetryPolicy(maxAttempts: maxAttempts),
      wait: (_) async {},
    ).sendDirect(
      message,
      provider: provider,
      target: emailTarget ?? defaultTarget,
      options: options,
    );
    return (result, requests);
  }

  test('maps the message, recipients and reply-to', () async {
    final (result, requests) = await send(
      NotifyMessage(title: 'Deploy', body: 'Done', htmlBody: '<b>Done</b>'),
      emailTarget: EmailTarget(
        to: [EmailAddress('ops@example.com', name: 'Ops')],
        cc: [EmailAddress('cc@example.com')],
        bcc: [EmailAddress('bcc@example.com')],
      ),
      options: EmailOptions(replyTo: [EmailAddress('support@example.com')]),
    );

    expect(result.isFullyAccepted, isTrue);
    expect(result.messageId, 'email-1');
    final request = requests.single;
    expect(request.url, Uri.parse('https://api.resend.com/emails'));
    expect(request.headers['authorization'], 'Bearer re_secret');
    expect(request.headers['idempotency-key'], isNotEmpty);
    final payload = jsonDecode(request.body) as Map;
    expect(payload['from'], 'Alerts <alerts@example.com>');
    expect(payload['to'], ['Ops <ops@example.com>']);
    expect(payload['cc'], ['cc@example.com']);
    expect(payload['bcc'], ['bcc@example.com']);
    expect(payload['subject'], 'Deploy');
    expect(payload['text'], 'Done');
    expect(payload['html'], '<b>Done</b>');
    expect(payload['reply_to'], ['support@example.com']);
  });

  test('a blank body omits text and sends only html', () async {
    final (_, requests) =
        await send(NotifyMessage(body: '', htmlBody: '<b>Ready</b>'));
    final payload = jsonDecode(requests.single.body) as Map;
    expect(payload.containsKey('text'), isFalse);
    expect(payload['html'], '<b>Ready</b>');
    expect(payload['subject'], '(no subject)');
  });

  test('attachments are base64 encoded with their content type', () async {
    final (result, requests) = await send(NotifyMessage(
      body: 'report',
      attachments: [
        NotifyAttachment(
          fileName: 'a.txt',
          bytes: Uint8List.fromList(utf8.encode('hi')),
          contentType: 'text/plain',
        ),
      ],
    ));

    expect(result.isFullyAccepted, isTrue);
    final payload = jsonDecode(requests.single.body) as Map;
    expect(payload['attachments'], [
      {
        'filename': 'a.txt',
        'content': base64Encode(utf8.encode('hi')),
        'content_type': 'text/plain',
      },
    ]);
  });

  test('more than 50 to-recipients fail before any request', () async {
    final (result, requests) = await send(
      NotifyMessage(body: 'x'),
      emailTarget: EmailTarget(to: [
        for (var i = 0; i < 51; i++) EmailAddress('u$i@example.com'),
      ]),
    );

    expect(result.status, DeliveryStatus.failed);
    expect(result.error?.code, 'resend_recipient_limit');
    expect(requests, isEmpty);
  });

  test('a cc-only target fails before any request', () async {
    final (result, requests) = await send(
      NotifyMessage(body: 'x'),
      emailTarget: EmailTarget(
        to: [],
        cc: [EmailAddress('cc@example.com')],
      ),
    );

    expect(result.status, DeliveryStatus.failed);
    expect(result.error?.code, 'resend_recipient_required');
    expect(requests, isEmpty);
  });

  test('a success without an ID is unknown', () async {
    final (result, _) = await send(
      NotifyMessage(body: 'x'),
      respond: (_, __) => http.Response('{}', 200),
    );

    expect(result.status, DeliveryStatus.unknown);
    expect(result.error?.code, 'resend_invalid_response');
  });

  test('a rate limit is retryable and reads Retry-After', () async {
    final (result, _) = await send(
      NotifyMessage(body: 'x'),
      respond: (_, __) => http.Response(
        jsonEncode({'name': 'rate_limit_exceeded'}),
        429,
        headers: {'retry-after': '2'},
      ),
    );

    expect(result.status, DeliveryStatus.failed);
    expect(result.error?.code, 'resend_rate_limited');
    expect(result.error?.retryable, isTrue);
    expect(result.attempts, 1);
  });

  test('quota limits are not retried', () async {
    final (result, _) = await send(
      NotifyMessage(body: 'x'),
      respond: (_, __) => http.Response(
        jsonEncode({'name': 'daily_quota_exceeded'}),
        429,
      ),
    );

    expect(result.error?.code, 'resend_quota_exceeded');
    expect(result.error?.retryable, isFalse);
  });

  test('idempotency conflicts separate retryable and terminal cases', () async {
    final (retryable, _) = await send(
      NotifyMessage(body: 'x'),
      respond: (_, __) => http.Response(
        jsonEncode({'name': 'concurrent_idempotent_requests'}),
        409,
      ),
    );
    expect(retryable.error?.code, 'resend_idempotent_in_progress');
    expect(retryable.error?.retryable, isTrue);

    final (terminal, _) = await send(
      NotifyMessage(body: 'x'),
      respond: (_, __) => http.Response(
        jsonEncode({'name': 'invalid_idempotent_request'}),
        409,
      ),
    );
    expect(terminal.error?.code, 'resend_idempotent_conflict');
    expect(terminal.error?.retryable, isFalse);
  });

  test('validation, auth and server errors map without leaking the body',
      () async {
    final (validation, _) = await send(
      NotifyMessage(body: 'x'),
      respond: (_, __) => http.Response(
        jsonEncode({'name': 'validation_error', 'message': 'secret'}),
        422,
      ),
    );
    expect(validation.status, DeliveryStatus.failed);
    expect(validation.error?.code, 'resend_validation');
    expect(validation.error?.message, isNot(contains('secret')));

    final (auth, _) = await send(
      NotifyMessage(body: 'x'),
      respond: (_, __) => http.Response('', 401),
    );
    expect(auth.error?.code, 'resend_auth');

    final (server, _) = await send(
      NotifyMessage(body: 'x'),
      respond: (_, __) => http.Response('', 503),
    );
    expect(server.status, DeliveryStatus.unknown);
    expect(server.error?.code, 'resend_http_503');
    expect(server.error?.retryable, isTrue);
  });

  test('transport failures become retryable unknown results', () async {
    final (result, _) = await send(
      NotifyMessage(body: 'x'),
      respond: (_, __) => throw http.ClientException('down'),
    );

    expect(result.status, DeliveryStatus.unknown);
    expect(result.error?.code, 'resend_network_error');
    expect(result.error?.retryable, isTrue);
  });

  test('retries reuse the same idempotency key', () async {
    final (result, requests) = await send(
      NotifyMessage(body: 'x'),
      maxAttempts: 2,
      respond: (_, call) => call == 1
          ? http.Response('', 503)
          : http.Response(jsonEncode({'id': 'email-2'}), 200),
    );

    expect(requests, hasLength(2));
    expect(requests[0].headers['idempotency-key'],
        requests[1].headers['idempotency-key']);
    expect(result.isFullyAccepted, isTrue);
    expect(result.messageId, 'email-2');
    expect(result.attempts, 2);
  });

  test('config and endpoint validation reject invalid values', () {
    expect(
      () => ResendConfig(apiKey: ' ', from: EmailAddress('a@b.c')),
      throwsArgumentError,
    );
    expect(
      () => ResendConfig(
        apiKey: 're_key',
        from: EmailAddress('a@b.c'),
        timeout: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(
      () => ResendProvider(
        id: 'resend',
        config: ResendConfig(
          apiKey: 're_key',
          from: EmailAddress('a@b.c'),
          endpoint: Uri.parse('http://api.resend.com/emails'),
        ),
        client: MockClient((_) async => http.Response('', 200)),
      ),
      throwsArgumentError,
    );
  });
}
