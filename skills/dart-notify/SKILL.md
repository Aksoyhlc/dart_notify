---
name: dart-notify
description: Write correct Dart code with the dart_notify package (pub.dev) to send push, email, SMS and chat notifications through OneSignal, Expo Push, SMTP, Resend, Netgsm, İletimerkezi, Verimor, Webhook, Telegram, Discord, Slack, ntfy or Gotify. Use this skill whenever a Dart, Dart Frog, Serverpod, shelf or Flutter project depends on dart_notify or wants to add notifications, alerts, OTP/SMS, transactional email or chat-ops messages from Dart, even if the user only says "send an SMS from my backend", "notify the team on Slack" or "add push notifications" without naming the package. Also use it when handling DeliveryResult or DispatchReport, retries, attachments, or writing tests or a custom provider for dart_notify.
---

# dart_notify

dart_notify sends notifications from Dart through many providers with one
dispatcher (`DartNotify`) and one result model. Everything is exported from a
single import:

```dart
import 'package:dart_notify/dart_notify.dart';
```

Add it with `dart pub add dart_notify`. It needs `dart:io`, so it runs on the
Dart VM, CLI tools, servers and Flutter mobile/desktop, but not on the web.

## The mental model

Every send combines four things. Keeping them apart is what makes the API
type-safe, so put each piece of data in the right place:

| Piece | Holds | Example |
| --- | --- | --- |
| **Provider + config** | Credentials, endpoint, timeout | `SlackProvider(id: 'slack', config: SlackConfig(token: ...))` |
| **Target** | Who receives it | `SlackTarget(channel: '#ops')` |
| **Options** (optional) | Per-provider delivery settings | `SlackOptions(threadTs: '...')` |
| **`NotifyMessage`** | Provider-independent content | `NotifyMessage(title: ..., body: ..., htmlBody: ..., attachments: ...)` |

A provider only accepts its own target and options types; mixing them fails at
compile time or when the destination is built. Look up the exact constructor
names in [references/providers.md](references/providers.md) before writing
provider code: the class names are not always guessable (`ExpoPushProvider`,
`EmailTarget` shared by SMTP and Resend, `OneSignalTarget.externalIds`).

## Two ways to send

**One-off send** with `sendDirect` when the recipient changes per call (a user's
phone number, an order's email):

```dart
final notify = DartNotify(destinations: []);
final result = await notify.sendDirect(
  NotifyMessage(body: 'Your code is 482913'),
  provider: sms,
  target: NetgsmTarget(numbers: [user.phone]),
);
```

**Registered destinations and groups** when the same recipients get alerts
repeatedly (an ops channel, an on-call email):

```dart
final notify = DartNotify(
  destinations: [
    ProviderDestination(id: 'ops-slack', provider: slack, target: SlackTarget(channel: '#ops')),
    ProviderDestination(id: 'ops-mail', provider: mail, target: EmailTarget(to: [EmailAddress('ops@example.com')])),
  ],
  groups: {'ops': ['ops-slack', 'ops-mail']},
  maxConcurrent: 4,
);
final report = await notify.send(NotifyMessage(title: 'Disk full', body: 'db-1 at 95%'), groups: ['ops']);
```

`send` takes `to: [...]` (destination IDs) and/or `groups: [...]`. Per-send
`options: {'ops-slack': SlackOptions(...)}` **replace** that destination's
default options for one call; they are not merged. Unknown IDs or mismatched
option types throw before anything is sent.

Create one `DartNotify` and the providers once (at startup or in a service) and
reuse them; `maxConcurrent` only limits work within one instance.

## Reading the outcome

`send`/`sendDirect` return results instead of throwing for delivery problems,
so the code must inspect them. A missing `try/catch` is not the bug; ignoring
the status is.

| Status | Meaning | Typical reaction |
| --- | --- | --- |
| `accepted` | Upstream took the request | done |
| `partiallyAccepted` | Some recipients rejected | log `error.message` (lists indexes, never tokens) |
| `skipped` | Nothing sent (e.g. no push subscription) | usually fine, maybe log |
| `failed` | Provider rejected it | fix input/credentials; check `error.code` |
| `unknown` | Can't tell (timeout, 5xx, malformed reply) | do **not** blindly resend; it may have been delivered |

`DeliveryResult` has `status`, `messageId`, `attempts`, `elapsed` and
`error` (`code`, `message`, `httpStatus`, `retryable`). `DispatchReport` has
`results`, `isFullyAccepted`, `hasAcceptedDeliveries`, `hasFailures` and
per-status counts. Error codes are stable strings like `slack_channel_not_found`
or `verimor_insufficient_credits`; branch on `code`, not on `message`.
Acceptance never means the device or inbox received it.

## Retries: let the package decide

Each delivery gets an idempotency key that is reused across its attempts. Only
providers whose API deduplicates by that key retry automatically: **OneSignal,
Resend, and Webhook when `WebhookConfig.idempotencyHeader` is set**. Configure
them with `DartNotify(retryPolicy: RetryPolicy(maxAttempts: 5))`.

Every other provider (SMTP, all SMS providers, Expo, Telegram, Discord, Slack,
ntfy, Gotify) makes exactly one attempt on purpose: after a timeout the message
may already be delivered, and a second request would send a duplicate SMS or
email. So do not wrap `send` in your own retry loop for these providers. If the
application needs at-least-once delivery, persist the job in its own queue and
accept the duplicate risk explicitly, ideally only for `failed` with
`error.retryable == true` (for example a 429).

## Credentials and lifecycle

- Read API keys, tokens and passwords from environment variables or a secret
  store; never hard-code them, and never ship provider credentials inside a
  Flutter app. A mobile app calls your backend, and the backend uses dart_notify.
- HTTP-based providers own an HTTP client: call `provider.close()` on shutdown
  (or in `finally` for scripts). An injected `client:` stays yours to close.
  `SmtpProvider` has no `close()`; it opens a connection per send.
- The `onUnexpectedError` callback on `DartNotify` receives raw exceptions that
  may contain secrets; redact before logging.

## Content rules that surprise people

- `title` is optional. Chat providers without a title field (Telegram, Discord,
  Slack) prepend it to the text on its own line; email uses it as the subject.
- `body` is required unless `htmlBody` is set. SMS providers and OneSignal need a
  non-blank plain `body`. Discord, Slack and Telegram (non-HTML mode) send
  `htmlBody` verbatim when `body` is blank, so always give a plain `body` there.
- Telegram HTML mode (`TelegramOptions(parseMode: TelegramParseMode.html)`) uses
  `htmlBody` when present; the title is escaped for you, the body is not.
- Attachments go on `NotifyMessage.attachments` as `NotifyAttachment(fileName:,
  bytes: Uint8List, contentType:)`. Only SMTP, Resend, Telegram (1 file) and
  Discord (up to 10) accept them; other destinations fail with
  `attachment_unsupported`. ntfy can link a remote file via `NtfyOptions.attachUrl`.
- SMS numbers: İletimerkezi and Verimor accept Turkish mobiles such as
  `0532 123 45 67`, `+90532...` or `532...` and normalize them to
  `905321234567`. Netgsm takes 10–17 digits without spaces (a leading `+`
  becomes `00`) and also allows international numbers. An invalid number throws
  `ArgumentError` when the target is built, so validate user input first.
- Scheduled SMS times (`sendAt`, `startAt`) are Türkiye-local `DateTime`s, not
  UTC. Commercial (İYS) sends need the recipient-type option.

## Testing code that uses dart_notify

Never hit real services in tests. Every HTTP provider accepts
`client: MockClient(...)` from `package:http/testing.dart`, and `SmtpProvider`
accepts `transport:` with a fake `SmtpTransport`:

```dart
final slack = SlackProvider(
  id: 'slack',
  config: SlackConfig(token: 'xoxb-test'),
  client: MockClient((request) async =>
      http.Response(jsonEncode({'ok': true, 'ts': '1.2'}), 200)),
);
final result = await DartNotify(destinations: [])
    .sendDirect(NotifyMessage(body: 'hi'), provider: slack, target: SlackTarget(channel: 'C123'));
expect(result.status, DeliveryStatus.accepted);
```

To test retries without waiting, pass `wait: (_) async {}` to `DartNotify`.

## Custom providers

For a service the package does not cover, extend
`NotificationProvider<MyTarget, MyOptions>` (use `NoNotificationOptions` when
there are no options), implement `id`, `supportsSafeRetry` and `send`, and return
a `ProviderResponse`. Set `supportsSafeRetry` to true only if the API
deduplicates on `context.idempotencyKey`. Override `supportsAttachments` if it
accepts files. Register it with `ProviderDestination` like any built-in provider.
See the "Custom providers" section of
[references/providers.md](references/providers.md) for a full skeleton.

## Before you finish

Check the code you wrote against these: correct target/options classes for the
provider, credentials from the environment, `close()` on HTTP providers, the
returned status actually inspected (with `unknown` not treated as failure to
resend), no hand-rolled retry loop around non-idempotent providers, and tests
using `MockClient` or a fake transport.
