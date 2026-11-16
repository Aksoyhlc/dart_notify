import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../../support/http/provider_http_fixture.dart';

void main() {
  final target = WhatsAppTarget(number: '905321234567');
  late ProviderHttpFixture fixture;
  late WhatsAppProvider provider;

  setUp(() {
    fixture = ProviderHttpFixture('{"messages":[{"id":"wamid.123"}]}');
    provider = WhatsAppProvider(
      id: 'whatsapp',
      config: WhatsAppConfig(
        phoneNumberId: '106540352242922',
        accessToken: 'example-token',
        graphApiVersion: 'v25.0',
        messagingAccountId: '123456',
      ),
      client: fixture.client,
    );
    addTearDown(fixture.client.close);
    addTearDown(provider.close);
  });

  Future<DeliveryResult> send(NotifyMessage message,
          {WhatsAppOptions? options}) =>
      DartNotify(destinations: []).sendDirect(
        message,
        provider: provider,
        target: target,
        options: options,
      );

  test('sends text with link preview and explicit Messaging account', () async {
    const body = 'Sipariş hazır https://example.com/order';
    final result = await send(
      NotifyMessage(body: body),
      options: const WhatsAppOptions.text(previewUrl: true),
    );

    expect(result.status, DeliveryStatus.accepted);
    expect(result.messageId, 'wamid.123');
    final request = fixture.requests.single;
    expect(request.method, 'POST');
    expect(request.url.toString(),
        'https://graph.facebook.com/v25.0/106540352242922/messages');
    expect(request.followRedirects, isFalse);
    expect(request.headers['authorization'], 'Bearer example-token');
    expect(jsonDecode(request.body), {
      'messaging_product': 'whatsapp',
      'recipient_type': 'individual',
      'to': '+905321234567',
      'messaging_account_id': '123456',
      'type': 'text',
      'text': {'body': body, 'preview_url': true},
    });
  });

  test('sends named header and body parameters and retains a held message ID',
      () async {
    fixture.respond = (_) => http.Response(
        '{"messages":[{"id":"wamid.held","message_status":"held_for_quality_assessment"}]}',
        200);
    final result = await send(
      NotifyMessage(body: 'Fallback for other channels'),
      options: WhatsAppOptions.template(
        name: 'order_ready',
        languageCode: 'tr',
        headerParameter: WhatsAppTemplateParameter.named('store', 'Merkez'),
        bodyParameters: [WhatsAppTemplateParameter.named('order_id', 'A42')],
      ),
    );

    expect(result.status, DeliveryStatus.accepted);
    expect(result.messageId, 'wamid.held');
    final payload = jsonDecode(fixture.requests.single.body) as Map;
    expect(payload['type'], 'template');
    expect(payload, isNot(contains('text')));
    expect(payload['template'], {
      'name': 'order_ready',
      'language': {'code': 'tr'},
      'components': [
        {
          'type': 'header',
          'parameters': [
            {'type': 'text', 'parameter_name': 'store', 'text': 'Merkez'},
          ],
        },
        {
          'type': 'body',
          'parameters': [
            {'type': 'text', 'parameter_name': 'order_id', 'text': 'A42'},
          ],
        },
      ],
    });
  });

  test('positional parameters preserve order and omit parameter names',
      () async {
    final result = await send(
      NotifyMessage(body: 'Fallback for other channels'),
      options: WhatsAppOptions.template(
        name: 'order_ready',
        languageCode: 'en_US',
        bodyParameters: [
          WhatsAppTemplateParameter.positional('A42'),
          WhatsAppTemplateParameter.positional('Merkez'),
        ],
      ),
    );

    expect(result.status, DeliveryStatus.accepted);
    final payload = jsonDecode(fixture.requests.single.body) as Map;
    expect(payload['template']['components'], [
      {
        'type': 'body',
        'parameters': [
          {'type': 'text', 'text': 'A42'},
          {'type': 'text', 'text': 'Merkez'},
        ],
      },
    ]);
  });

  test('rejects mixed and duplicate named template parameters', () {
    final named = WhatsAppTemplateParameter.named('order_id', 'A42');
    expect(
      () => WhatsAppOptions.template(
        name: 'order_ready',
        languageCode: 'en_US',
        bodyParameters: [named, WhatsAppTemplateParameter.positional('Merkez')],
      ),
      throwsArgumentError,
    );
    expect(
      () => WhatsAppOptions.template(
        name: 'order_ready',
        languageCode: 'en_US',
        bodyParameters: [named, named],
      ),
      throwsArgumentError,
    );
  });

  test('rejects text over the limit and files before any HTTP request',
      () async {
    final tooLong = await send(NotifyMessage(body: 'x' * 4097));
    final noText =
        await send(NotifyMessage(body: '', htmlBody: '<b>Ready</b>'));
    final file = await send(NotifyMessage(body: 'Ready', attachments: [
      NotifyAttachment(fileName: 'report.pdf', bytes: Uint8List(1)),
    ]));

    expect(tooLong.error?.code, 'whatsapp_body_limit');
    expect(noText.error?.code, 'whatsapp_body_required');
    expect(file.error?.code, 'attachment_unsupported');
    expect(fixture.requests, isEmpty);
  });

  test('closed window and template parameter failures have actionable codes',
      () async {
    fixture.respond = (_) => http.Response(
        '{"error":{"code":131047,"message":"Conversation with +905321234567"}}',
        400);
    final closed = await send(NotifyMessage(body: 'Ready'));
    fixture.respond = (_) => http.Response('{"error":{"code":132012}}', 400);
    final badParameters = await send(
      NotifyMessage(body: 'Ready'),
      options:
          WhatsAppOptions.template(name: 'order_ready', languageCode: 'tr'),
    );

    expect(closed.status, DeliveryStatus.failed);
    expect(closed.error?.code, 'whatsapp_template_required');
    expect(closed.error?.message, isNot(contains(target.number)));
    expect(badParameters.status, DeliveryStatus.failed);
    expect(badParameters.error?.code, 'whatsapp_template_parameters');
    final template = jsonDecode(fixture.requests.last.body)['template'] as Map;
    expect(template, isNot(contains('components')));
  });
}
