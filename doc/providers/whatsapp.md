# WhatsApp Cloud API

Configure a registered WhatsApp Business phone number, its **Phone Number ID**,
and a Meta access token with `whatsapp_business_messaging` permission. Set
`graphApiVersion` to a supported Graph API version for your integration.
Store the token on your backend.
Set `messagingAccountId` when the token can send from multiple Messaging
accounts on the same business phone number.

```dart
final whatsapp = WhatsAppProvider(
  id: 'whatsapp',
  config: WhatsAppConfig(
    phoneNumberId: Platform.environment['WHATSAPP_PHONE_NUMBER_ID']!,
    accessToken: Platform.environment['WHATSAPP_ACCESS_TOKEN']!,
    graphApiVersion: Platform.environment['META_GRAPH_API_VERSION']!,
  ),
);
final target = WhatsAppTarget(number: '+905321234567');

final result = await notify.sendDirect(
  NotifyMessage(body: 'Your order is ready for pickup.'),
  provider: whatsapp,
  target: target,
  options: WhatsAppOptions.template(
    name: 'order_ready',
    languageCode: 'en_US',
    bodyParameters: [WhatsAppTemplateParameter.positional('A123')],
  ),
);
```

Use `WhatsAppOptions.text(previewUrl: true)` for a free-form `body` of up to
4096 characters. An incoming message or eligible call opens or resets the
24-hour customer service window. Outside it, use a template approved in the
language you plan to send. Follow Meta's messaging and consent rules for the use case.

Template mode renders the Meta template with its supplied parameters. The
`NotifyMessage.body` in the example supplies content for any other destination
that receives the same notification. The `headerParameter` and
`bodyParameters` entries support text placeholders. Use
`WhatsAppTemplateParameter.named('order_id', 'A123')` if the template was
created with named parameters. Preserve the approved template's parameter
names, order and language.

`messageId` contains Meta's message ID, including when Meta holds the message
for quality assessment. Use your own Meta status webhook to track delivery.
Common errors include `whatsapp_auth`, `whatsapp_template_required`,
`whatsapp_template_not_found`, `whatsapp_template_parameters` and
`whatsapp_rate_limited`. The provider makes one attempt per delivery. Call
`whatsapp.close()` when finished.

[Send messages API](https://developers.facebook.com/docs/whatsapp/cloud-api/reference/messages) ·
[Messaging accounts](https://developers.facebook.com/documentation/business-messaging/whatsapp/account-model-evolution/messaging/) ·
[Cloud API overview](https://developers.facebook.com/documentation/business-messaging/whatsapp/overview) ·
[Error codes](https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/)
