# Provider reference

Constructor cheat sheet for every built-in provider. All HTTP providers accept
an optional `client: http.Client` (for tests or custom clients) and have
`close()`. Full guides live in the package's `doc/providers/` folder.

## Contents

- [Push: OneSignal, Expo, Pushover](#push)
- [Email: SMTP, Resend, Postmark](#email)
- [SMS: Netgsm, İletimerkezi, Verimor, Twilio](#sms)
- [Chat: Telegram, Discord, Slack, WhatsApp](#chat)
- [Self-hosted push: ntfy, Gotify](#self-hosted-push)
- [Webhook](#webhook)
- [Custom providers](#custom-providers)

## Push

### OneSignal (safe retry)

```dart
final push = OneSignalProvider(
  id: 'push',
  config: OneSignalConfig(appId: env('ONESIGNAL_APP_ID'), apiKey: env('ONESIGNAL_API_KEY')),
);
```

- Targets (one mode each): `OneSignalTarget.externalIds([...])`,
  `.onesignalIds([...])`, `.aliases('key', [...])`, `.subscriptionIds([...])`,
  `.segments(['Subscribed Users'], excluded: [...])`, `.filters([{...}])`.
- `OneSignalOptions(language: 'tr', localizedTitles: {...}, localizedBodies: {...},
  bigPicture: Uri, androidChannelId: '...', url: Uri /* https */, appUrl: Uri,
  collapseId: '...', ttl: Duration /* ≤ 28 days */, sendAfter: DateTime)`.
- `NotifyMessage.data` is sent as the push `data`; `NotifyPriority.high` → 10.
- Blank `body` → `invalid_push_body`. No eligible subscriber → `skipped`
  (`onesignal_no_recipients`).

### Expo Push

```dart
final expo = ExpoPushProvider(
  id: 'expo',
  config: ExpoPushConfig(accessToken: env('EXPO_ACCESS_TOKEN')), // token optional
);
```

- Target: `ExpoPushTarget(tokens: ['ExponentPushToken[...]', ...])`; split into
  batches of 100 automatically.
- `ExpoPushOptions(sound: 'default', badge: 1, channelId: '...', ttl: Duration,
  priority: ExpoPriority.high, subtitle: '...', data: {...})`.
- Ticket errors become `expo_device_not_registered` etc.; remove those tokens
  from your store. Mixed results → `partiallyAccepted`, message lists token
  indexes (never tokens).

### Pushover

```dart
final push = PushoverProvider(
  id: 'pushover',
  config: PushoverConfig(appToken: env('PUSHOVER_APP_TOKEN')),
);
PushoverTarget(userKey: env('PUSHOVER_USER_KEY'), devices: ['phone']);
PushoverOptions(
  priority: PushoverPriority.emergency,
  retryEvery: Duration(minutes: 1),
  expireAfter: Duration(minutes: 30),
);
```

Accepts one image of up to 5,242,880 bytes. Emergency sends return the Pushover
receipt as `messageId`. Pushover itself handles emergency repetitions.

## Email

`EmailAddress('a@b.com', name: 'Name')`, `EmailTarget(to: [...], cc: [...],
bcc: [...])` and `EmailOptions(replyTo: [...])` are shared by all three providers.
`title` → subject, `body` → text, `htmlBody` → HTML part.

### SMTP

```dart
final mail = SmtpProvider(
  id: 'mail',
  config: SmtpConfig(
    host: 'smtp.example.com',
    port: 587,                                // default
    security: SmtpSecurity.startTlsRequired,  // or sslTls (465), none
    username: env('SMTP_USER'),
    password: env('SMTP_PASSWORD'),
    from: EmailAddress('alerts@example.com', name: 'Alerts'),
  ),
  // transport: FakeSmtpTransport(), // for tests
);
```

No `close()`; codes `smtp_auth`, `smtp_invalid_message` (failed),
`smtp_timeout`, `smtp_network`, `smtp_protocol` (unknown).

### Resend (safe retry)

```dart
final resend = ResendProvider(
  id: 'resend',
  config: ResendConfig(apiKey: env('RESEND_API_KEY'), from: EmailAddress('alerts@example.com')),
);
```

At least one `to` recipient (max 50); attachments ≤ 40 MB after base64.
Codes: `resend_rate_limited` (retried), `resend_quota_exceeded`,
`resend_validation`, `resend_auth`, `resend_forbidden`.

### Postmark

```dart
final email = PostmarkProvider(
  id: 'postmark',
  config: PostmarkConfig(
    serverToken: env('POSTMARK_SERVER_TOKEN'),
    from: EmailAddress('alerts@example.com'),
    messageStream: 'outbound',
  ),
);
```

Requires at least one To recipient and supports up to 50 recipients across
To, Cc and Bcc. Attachments count toward the 10 MB limit after base64 encoding.

## SMS

All four reject a blank `body` and make a single attempt.

### Netgsm

```dart
final sms = NetgsmProvider(
  id: 'sms',
  config: NetgsmConfig(username: env('NETGSM_USER'), password: env('NETGSM_PASS'), sender: 'BRAND'),
);
// target
NetgsmTarget(numbers: ['5321234567']);
// options
NetgsmOptions(
  encoding: NetgsmEncoding.turkish,                 // or unicode; default utf8
  iysFilter: NetgsmIysFilter.commercialIndividual,  // default informational
  startAt: DateTime(2026, 11, 2, 9, 0),             // Türkiye-local
  referenceId: 'order-42',
);
```

### İletimerkezi

```dart
final sms = IletimerkeziProvider(
  id: 'sms',
  config: IletimerkeziConfig(key: env('ILETIMERKEZI_KEY'), hash: env('ILETIMERKEZI_HASH'), sender: 'BRAND'),
);
IletimerkeziTarget(numbers: ['0532 123 45 67']);
IletimerkeziOptions(iys: IletimerkeziIys.commercialIndividual, sendAt: DateTime(...));
```

`IletimerkeziIys`: `transactional` (default), `commercialIndividual`,
`commercialBusiness`. The `APITEST` sender only allows `transactional`.

### Verimor

```dart
final sms = VerimorProvider(
  id: 'sms',
  config: VerimorConfig(username: '908501234567', password: env('VERIMOR_PASS'), sourceAddr: 'BRAND'),
);
VerimorTarget(numbers: ['+905321234567']);
VerimorOptions(
  datacoding: VerimorDatacoding.gsmTurkish,   // gsmBasic default, ucs2
  validFor: Duration(hours: 24),              // whole minutes, 1 min – 48 h
  sendAt: DateTime(...),                      // Türkiye-local
  customId: 'order-42',                       // ≤ 50 chars, not an idempotency key
  commercial: true,
  iysRecipientType: VerimorIysRecipientType.individual, // required when commercial
);
```

Codes such as `verimor_insufficient_credits`; unknown upstream text becomes
`verimor_unknown_error`.

### Twilio

```dart
final sms = TwilioProvider(
  id: 'twilio-sms',
  config: TwilioConfig(
    accountSid: env('TWILIO_ACCOUNT_SID'),
    apiKeySid: env('TWILIO_API_KEY_SID'),
    apiKeySecret: env('TWILIO_API_KEY_SECRET'),
    from: '+14155550123',
  ),
);
TwilioTarget(number: '+14155550124');
```

Use `from`, `messagingServiceSid` or both. Account SID and Auth Token
credentials use `TwilioConfig.withAuthToken`. `TwilioOptions(statusCallback:)`
sets an HTTPS delivery status callback.

## Chat

### Telegram

```dart
final tg = TelegramProvider(id: 'tg', config: TelegramConfig(botToken: env('TELEGRAM_BOT_TOKEN')));
TelegramTarget(chatId: '-1001234567890'); // or '@channelname'
TelegramOptions(
  parseMode: TelegramParseMode.html,  // plain (default), markdownV2, html
  silent: true, protectContent: false, threadId: 42, replyToMessageId: 7,
  disableLinkPreview: true,
);
```

Text ≤ 4096 characters; one attachment (≤ 50 MB) is sent as a document with a
caption ≤ 1024 characters.

### Discord

```dart
final discord = DiscordProvider(
  id: 'discord',
  config: DiscordConfig(username: 'Alerts', threadId: '123456789012'), // all optional
);
DiscordTarget(webhookUrl: Uri.parse(env('DISCORD_WEBHOOK_URL')));
DiscordOptions(
  embeds: [DiscordEmbed(title: 'Deploy', description: '...', color: 0x2ECC71,
      fields: [DiscordEmbedField(name: 'Version', value: '2.4.1', inline: true)])],
  allowedMentions: ['users'],  // default: no pings
);
```

Content ≤ 2000 characters, ≤ 10 embeds, ≤ 10 files of 25 MB.

### Slack

```dart
final slack = SlackProvider(id: 'slack', config: SlackConfig(token: env('SLACK_BOT_TOKEN')));
SlackTarget(channel: 'C0123456789'); // or '#ops'
SlackOptions(
  blocks: [{'type': 'section', 'text': {'type': 'mrkdwn', 'text': '*Deploy* done'}}],
  threadTs: '1712345678.000100', unfurlLinks: false,
);
```

The message text is the notification fallback and is required when blocks are
used; ≤ 50 blocks, block text ≤ 3000 characters. The bot must be invited to the
channel, otherwise `slack_not_in_channel` / `slack_channel_not_found`.

### WhatsApp

```dart
final chat = WhatsAppProvider(
  id: 'whatsapp',
  config: WhatsAppConfig(
    phoneNumberId: env('WHATSAPP_PHONE_NUMBER_ID'),
    accessToken: env('WHATSAPP_ACCESS_TOKEN'),
    graphApiVersion: env('META_GRAPH_API_VERSION'),
  ),
);
WhatsAppTarget(number: '+905321234567');
WhatsAppOptions.template(
  name: 'order_ready',
  languageCode: 'en_US',
  bodyParameters: [WhatsAppTemplateParameter.positional('A123')],
);
```

`WhatsAppOptions.text(previewUrl: true)` sends the plain body within the
customer service window. Template mode supports named or positional header
and body text parameters. Use an approved template outside the window.

## Self-hosted push

### ntfy

```dart
final ntfy = NtfyProvider(id: 'ntfy', config: NtfyConfig(authToken: env('NTFY_TOKEN'))); // baseUrl defaults to https://ntfy.sh
NtfyTarget(topic: 'ops-alerts');
NtfyOptions(priority: NtfyPriority.high, tags: ['warning'], click: Uri.parse('...'),
    markdown: true, delay: Duration(minutes: 30), attachUrl: Uri.parse('https://.../report.pdf'));
```

### Gotify

```dart
final gotify = GotifyProvider(
  id: 'gotify',
  config: GotifyConfig(baseUrl: Uri.parse('https://push.example.com')),
);
GotifyTarget(appToken: env('GOTIFY_APP_TOKEN'));
GotifyOptions(priority: 8, markdown: true);
```

## Webhook

```dart
final hook = WebhookProvider(
  id: 'hook',
  config: WebhookConfig(
    headers: {'Authorization': 'Bearer ${env('HOOK_TOKEN')}'},
    method: WebhookMethod.post,
    idempotencyHeader: 'Idempotency-Key', // enables safe retries
    payloadBuilder: (message) => {'text': message.body}, // optional custom JSON
  ),
);
WebhookTarget(Uri.parse('https://example.com/hooks/alerts')); // HTTPS only
WebhookOptions(payload: {...}, headers: {...}, method: WebhookMethod.put);
```

Without a custom builder the JSON is `{title, body, htmlBody, priority, data}`.
Redirects are not followed.

## Custom providers

```dart
final class AuditTarget implements NotificationTarget {
  const AuditTarget(this.endpoint);
  final Uri endpoint;
}

final class AuditProvider extends NotificationProvider<AuditTarget, NoNotificationOptions> {
  AuditProvider(this.client);
  final http.Client client;

  @override
  String get id => 'audit';

  @override
  bool get supportsSafeRetry => false; // true only if the API dedupes on context.idempotencyKey

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required AuditTarget target,
    required DeliveryContext context,
    NoNotificationOptions? options,
  }) async {
    final response = await client.post(target.endpoint, body: message.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return const ProviderResponse.accepted();
    }
    return ProviderResponse(
      status: response.statusCode >= 500 ? DeliveryStatus.unknown : DeliveryStatus.failed,
      error: DeliveryError(
        code: 'audit_http_${response.statusCode}',
        message: 'Audit endpoint returned HTTP ${response.statusCode}.',
        httpStatus: response.statusCode,
        retryable: response.statusCode == 429 || response.statusCode >= 500,
      ),
    );
  }
}
```

Keep error messages free of credentials and response bodies. Throw
`NotifyDeliveryException` only for transport uncertainty (timeouts, dropped
connections); return `ProviderResponse` for everything the upstream answered.
