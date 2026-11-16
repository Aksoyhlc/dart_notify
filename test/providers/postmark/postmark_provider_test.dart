import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../../support/http/provider_http_fixture.dart';

void main() {
  final recipient = EmailAddress('customer@example.com');
  late ProviderHttpFixture fixture;
  late PostmarkProvider provider;

  setUp(() {
    fixture = ProviderHttpFixture(
        '{"ErrorCode":0,"MessageID":"b7bc2f4a-e38e-4336-af7d-e6c392c2f817"}');
    provider = PostmarkProvider(
      id: 'postmark',
      config: PostmarkConfig(
        serverToken: 'server-token',
        from: EmailAddress('orders@example.com', name: 'Orders, Inc.'),
        messageStream: 'outbound',
      ),
      client: fixture.client,
    );
    addTearDown(fixture.client.close);
    addTearDown(provider.close);
  });

  Future<DeliveryResult> send(
    NotifyMessage message, {
    EmailTarget? target,
    EmailOptions? options,
  }) =>
      DartNotify(destinations: []).sendDirect(
        message,
        provider: provider,
        target: target ?? EmailTarget(to: [recipient]),
        options: options,
      );

  test('posts a single email with envelope, text, HTML and file bytes',
      () async {
    final result = await send(
      NotifyMessage(
        title: 'Sipariş',
        body: 'Hazır',
        htmlBody: '<p>Hazır</p>',
        attachments: [
          NotifyAttachment(
            fileName: 'order.txt',
            bytes: Uint8List.fromList([0, 65, 255]),
            contentType: 'text/plain',
          ),
        ],
      ),
      target: EmailTarget(
        to: [recipient, EmailAddress('other@example.com')],
        cc: [EmailAddress('sales@example.com')],
        bcc: [EmailAddress('audit@example.com')],
      ),
      options: EmailOptions(replyTo: [EmailAddress('reply@example.com')]),
    );

    expect(result.status, DeliveryStatus.accepted);
    expect(result.messageId, 'b7bc2f4a-e38e-4336-af7d-e6c392c2f817');
    final request = fixture.requests.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://api.postmarkapp.com/email');
    expect(request.followRedirects, isFalse);
    expect(request.headers['x-postmark-server-token'], 'server-token');
    expect(request.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(request.body), {
      'From': '"Orders, Inc." <orders@example.com>',
      'To': 'customer@example.com, other@example.com',
      'Cc': 'sales@example.com',
      'Bcc': 'audit@example.com',
      'ReplyTo': 'reply@example.com',
      'Subject': 'Sipariş',
      'TextBody': 'Hazır',
      'HtmlBody': '<p>Hazır</p>',
      'MessageStream': 'outbound',
      'Attachments': [
        {
          'Name': 'order.txt',
          'Content': 'AEH/',
          'ContentType': 'text/plain',
        },
      ],
    });
  });

  test('sends an HTML-only message without an empty text part', () async {
    final result =
        await send(NotifyMessage(body: '', htmlBody: '<b>Ready</b>'));

    expect(result.status, DeliveryStatus.accepted);
    final payload = jsonDecode(fixture.requests.single.body) as Map;
    expect(payload['HtmlBody'], '<b>Ready</b>');
    expect(payload, isNot(contains('TextBody')));
  });

  test('counts To, Cc and Bcc together and allows exactly 50', () async {
    final cc = [for (var i = 0; i < 48; i++) EmailAddress('cc$i@example.com')];
    final bcc = EmailAddress('audit@example.com');
    final message = NotifyMessage(body: 'Ready');

    final atLimit = await send(
      message,
      target: EmailTarget(to: [recipient], cc: cc, bcc: [bcc]),
    );
    final overLimit = await send(
      message,
      target: EmailTarget(
        to: [recipient],
        cc: cc,
        bcc: [bcc, EmailAddress('extra@example.com')],
      ),
    );

    expect(atLimit.status, DeliveryStatus.accepted);
    expect(overLimit.status, DeliveryStatus.failed);
    expect(overLimit.error?.code, 'postmark_recipient_limit');
    expect(fixture.requests, hasLength(1));
  });

  test('requires To and rejects multiple mailboxes in one address', () async {
    final noTo = await send(NotifyMessage(body: 'Ready'),
        target: EmailTarget(to: [], cc: [recipient]));
    final mailboxList = await send(
      NotifyMessage(body: 'Ready'),
      target: EmailTarget(
        to: [EmailAddress('customer@example.com, extra@example.com')],
      ),
    );

    expect(noTo.error?.code, 'postmark_recipient_required');
    expect(mailboxList.error?.code, 'postmark_invalid_address');
    expect(fixture.requests, isEmpty);
  });

  test('rejects blocked attachments and enforces the encoded size limit',
      () async {
    final blocked = await send(NotifyMessage(body: 'Ready', attachments: [
      NotifyAttachment(fileName: 'report.ExE', bytes: Uint8List(1)),
    ]));
    final tooLarge = await send(NotifyMessage(body: 'Ready', attachments: [
      NotifyAttachment(
          fileName: 'report.pdf', bytes: Uint8List(8 * 1024 * 1024)),
    ]));

    expect(blocked.error?.code, 'postmark_attachment_type');
    expect(tooLarge.error?.code, 'postmark_payload_limit');
    expect(fixture.requests, isEmpty);
  });

  test('sanitizes upstream rejection of an inactive recipient', () async {
    fixture.respond = (_) => http.Response(
        '{"ErrorCode":406,"Message":"Inactive customer@example.com"}', 422);

    final result = await send(NotifyMessage(body: 'Ready'));

    expect(result.status, DeliveryStatus.failed);
    expect(result.error?.code, 'postmark_inactive_recipient');
    expect(result.error?.httpStatus, 422);
    expect(result.error?.message, isNot(contains('customer@example.com')));
  });

  test('a success code without a message ID leaves acceptance unknown',
      () async {
    fixture.respond = (_) => http.Response('{"ErrorCode":0}', 200);

    final result = await send(NotifyMessage(body: 'Ready'));

    expect(result.status, DeliveryStatus.unknown);
    expect(result.error?.code, 'postmark_invalid_response');
  });
}
