# dart_notify

[![pub package](https://img.shields.io/pub/v/dart_notify.svg)](https://pub.dev/packages/dart_notify)
[![Dart CI](https://github.com/Aksoyhlc/dart_notify/actions/workflows/dart.yml/badge.svg)](https://github.com/Aksoyhlc/dart_notify/actions/workflows/dart.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Type-safe notifications for Dart backends. Send push, email, SMS and chat
messages through 13 providers, or your own, with one dispatcher and one result
model.

- **One API for every channel:** OneSignal and Expo push, SMTP and Resend email,
  Netgsm, İletimerkezi and Verimor SMS, Telegram, Discord, Slack, ntfy, Gotify
  and generic Webhook.
- **Type-safe routing:** each provider has its own target, options and config
  types; mismatches fail at compile time or before any request is sent.
- **Named destinations and groups:** register destinations once, then send to
  `to: ['ops-email']` or `groups: ['ops']`.
- **Honest outcomes:** `accepted`, `partiallyAccepted`, `skipped`, `failed` and
  `unknown`, with sanitized error codes that never echo credentials or response
  bodies.
- **Safe retries only:** automatic retries run only where the upstream API
  supports idempotency keys; a shared FIFO limiter bounds concurrent deliveries.
- **Attachments** for SMTP, Resend, Telegram and Discord, with provider limits
  checked before sending.

## Install

```sh
dart pub add dart_notify
```

```dart
import 'package:dart_notify/dart_notify.dart';
```

## Quick start

Send one message through one provider with `sendDirect`:

```dart
import 'dart:io';

import 'package:dart_notify/dart_notify.dart';

Future<void> main() async {
  final telegram = TelegramProvider(
    id: 'telegram',
    config: TelegramConfig(botToken: Platform.environment['TELEGRAM_BOT_TOKEN']!),
  );
  final notify = DartNotify(destinations: []);

  try {
    final result = await notify.sendDirect(
      NotifyMessage(title: 'Deploy finished', body: 'api v2.4.1 is live'),
      provider: telegram,
      target: TelegramTarget(chatId: '-1001234567890'),
    );
    print('${result.status.name} ${result.error?.code ?? ''}');
  } finally {
    telegram.close();
  }
}
```

Every provider follows the same pattern: a provider with its config, a target
for the recipients and optional per-send options.

## Destinations and groups

Register destinations when the same recipients receive notifications
repeatedly, then select them by ID or group:

```dart
final push = OneSignalProvider(
  id: 'push',
  config: OneSignalConfig(
    appId: Platform.environment['ONESIGNAL_APP_ID']!,
    apiKey: Platform.environment['ONESIGNAL_API_KEY']!,
  ),
);
final email = SmtpProvider(
  id: 'email',
  config: SmtpConfig(
    host: 'smtp.example.com',
    username: 'alerts@example.com',
    password: Platform.environment['SMTP_PASSWORD']!,
    from: EmailAddress('alerts@example.com', name: 'Monitoring'),
  ),
);

final notify = DartNotify(
  destinations: [
    ProviderDestination(
      id: 'ops-push',
      provider: push,
      target: OneSignalTarget.externalIds(['employee-42']),
      options: OneSignalOptions(ttl: Duration(hours: 1)),
    ),
    ProviderDestination(
      id: 'ops-email',
      provider: email,
      target: EmailTarget(to: [EmailAddress('ops@example.com')]),
    ),
  ],
  groups: {'ops': ['ops-push', 'ops-email']},
  maxConcurrent: 4,
);

final report = await notify.send(
  NotifyMessage(title: 'System alert', body: 'RFID gateway offline'),
  groups: ['ops'],
);
for (final result in report.results) {
  print('${result.destinationId}: ${result.status.name}');
}
```

Destination IDs selected more than once in a call are deduplicated, and results
follow selection order. Several instances of one provider can use different
accounts.

Options registered on a destination are defaults. A per-send override, keyed by
destination ID, **replaces** those defaults for one call; options are not
merged:

```dart
await notify.send(
  message,
  groups: ['ops'],
  options: {
    'ops-push': OneSignalOptions(ttl: Duration(minutes: 5)),
    'ops-email': EmailOptions(replyTo: [EmailAddress('support@example.com')]),
  },
);
```

Unknown destination IDs, overrides for unselected destinations and option types
that do not match the provider reject the whole call before any request.

## Providers

| Provider | Class | Channel | Attachments | Safe retry |
| --- | --- | --- | --- | --- |
| [OneSignal](doc/providers/onesignal.md) | `OneSignalProvider` | Push | No | Yes |
| [Expo Push](doc/providers/expo.md) | `ExpoPushProvider` | Push | No | No |
| [SMTP](doc/providers/smtp.md) | `SmtpProvider` | Email | Yes | No |
| [Resend](doc/providers/resend.md) | `ResendProvider` | Email | Yes | Yes |
| [Netgsm](doc/providers/netgsm.md) | `NetgsmProvider` | SMS | No | No |
| [İletimerkezi](doc/providers/iletimerkezi.md) | `IletimerkeziProvider` | SMS | No | No |
| [Verimor](doc/providers/verimor.md) | `VerimorProvider` | SMS | No | No |
| [Webhook](doc/providers/webhook.md) | `WebhookProvider` | HTTPS JSON | No | With idempotency header |
| [Telegram](doc/providers/telegram.md) | `TelegramProvider` | Chat | 1 file | No |
| [Discord](doc/providers/discord.md) | `DiscordProvider` | Chat | Up to 10 files | No |
| [Slack](doc/providers/slack.md) | `SlackProvider` | Chat | No | No |
| [ntfy](doc/providers/ntfy.md) | `NtfyProvider` | Self-hosted push | Remote URL | No |
| [Gotify](doc/providers/gotify.md) | `GotifyProvider` | Self-hosted push | No | No |

Each guide covers configuration, option mapping, limits and the error codes the
provider returns. Attachments live on `NotifyMessage.attachments`; a provider
that cannot carry files fails with `attachment_unsupported` before any request.

## Outcomes

| Status | Meaning |
| --- | --- |
| `accepted` | The upstream service fully accepted the request. |
| `partiallyAccepted` | Accepted for some recipients and rejected for others. |
| `skipped` | Nothing was sent, for example no eligible push subscription. |
| `failed` | The provider rejected the request. |
| `unknown` | Acceptance cannot be determined, such as after a timeout. |

`DeliveryResult` and `DispatchReport` both expose `isFullyAccepted` and
`hasAcceptedDeliveries`; the report adds per-status counts. Acceptance means the
upstream service took the request, not that a device or inbox received it.
Unexpected exceptions become a sanitized `unexpected_error`; the optional
`onUnexpectedError` callback receives the original error for your logs.

## Retries and concurrency

Each logical delivery gets an idempotency key that is reused across its attempts.
OneSignal, Resend and Webhook with a configured idempotency header retry
temporary failures according to `RetryPolicy` (3 attempts by default, exponential
backoff, `Retry-After` honoured). Every other provider makes one attempt, because
its API cannot deduplicate a repeated request.

`maxConcurrent` limits in-flight deliveries across all calls on one `DartNotify`
instance. It is a concurrency bound, not a requests-per-second rate limiter.
Durable queues, scheduling and deduplication across restarts belong to your
application. See [delivery semantics](doc/DELIVERY.md) for the full rules.

## Platform and credentials

dart_notify needs `dart:io`, so it runs on the Dart VM, in CLI tools and in
Flutter apps on Android, iOS and desktop, but not on the web. Provider API keys
grant send access to your account: keep them on a server you control. A mobile
app should call your backend, not embed provider credentials.

Call `close()` on HTTP-based providers when you no longer need them; it closes
the HTTP client the provider created, while an injected `http.Client` stays
yours to close.

## Custom providers

Extend `NotificationProvider<MyTarget, MyOptions>`, implement `id`,
`supportsSafeRetry` and `send`, and register it with `ProviderDestination`. The
dispatcher needs no changes. See [architecture](doc/ARCHITECTURE.md) for a
complete example.

## Examples

[`example/`](example/) contains runnable programs: `main.dart` (OneSignal and
SMTP), `resend.dart`, `netgsm.dart`, `iletimerkezi.dart`, `verimor.dart`,
`webhook.dart` and `ops_alerting.dart` (Telegram and ntfy). Each reads its
credentials from the environment variables listed at the top of the file and
sends real notifications.

## AI assistant skill

[`skills/dart-notify/`](skills/dart-notify/) is an
[Agent Skill](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview)
that teaches AI coding assistants how to use this package correctly: provider
classes, outcome handling, which providers may retry, and testing with
`MockClient`. To use it with Claude Code, copy the folder into your project's
`.claude/skills/` directory or into `~/.claude/skills/`.

## Stability

The public API is stable for the 1.x line; breaking changes require a new major
version. See the [changelog](CHANGELOG.md).

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for
the development checks and project layout rules.

## License

MIT. See [LICENSE](LICENSE).
