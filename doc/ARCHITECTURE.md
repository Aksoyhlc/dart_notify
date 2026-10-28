# Architecture

One Dart package with provider-independent dispatch and isolated adapters.

```text
lib/
  dart_notify.dart                         Public API exports
  src/
    core/
      enums/                               All core enums
      typedefs/                            Core callback signatures
      utils/                               Core utilities, including FIFO admission
      notification/                        Message, target and option contracts
      provider/                            Provider contract and attempt response
      routing/                             Destination contract and provider binding
      delivery/
        errors/                            Safe errors and expected exceptions
        diagnostics/                       Original failure context
        retry/                             Retry policy
      dispatch/                            Orchestrator and aggregate report
    providers/
      onesignal/
        enums/                             All OneSignal enums
        typedefs/                          HTTP client alias
        config/                            App credentials, endpoint and timeout
        targets/                           Targeting models
        options/                           Localization and delivery settings
        onesignal_provider.dart            OneSignal adapter
        onesignal.dart                     Provider exports
      smtp/
        enums/                             All SMTP enums
        config/                            SMTP connection settings
        transport/                         Transport contract and mailer adapter
        smtp_provider.dart                 SMTP adapter
        smtp.dart                          Provider exports
      resend/
        config/                            API key, sender and endpoint
        resend_provider.dart               Resend email API adapter
      netgsm/
        config/                            API credentials and SMS sender
        enums/                             Encoding and IYS filter modes
        targets/                           SMS recipients
        options/                           Encoding, IYS, schedule and reference
        utils/                             Phone and scheduling formatting
        netgsm_provider.dart               Standard SMS REST v2 adapter
      iletimerkezi/
        config/                            API key, hash and sender
        enums/                             IYS modes
        targets/                           Normalized Turkish recipients
        options/                           IYS mode and scheduling
        iletimerkezi_provider.dart         REST v1 JSON adapter
      verimor/
        config/                            Account, password and source address
        enums/                             Datacoding and IYS recipient types
        targets/                           Normalized Turkish recipients
        options/                           Datacoding, validity, scheduling and IYS
        verimor_provider.dart              SMS API v2 JSON adapter
      expo/
        config/                            Access token and endpoint
        enums/                             Push priorities
        targets/                           Expo push tokens
        options/                           Presentation and payload settings
        expo_push_provider.dart            Expo Push Service adapter
      telegram/
        config/                            Bot token, timeout and endpoint
        enums/                             Parse modes
        targets/                           Chat IDs and channel usernames
        options/                           Formatting, threading and silence
        telegram_provider.dart             Bot API sendMessage/sendDocument
      discord/
        config/                            Webhook overrides and thread
        targets/                           Webhook URL validation
        options/                           Embeds, mentions and flags
        discord_provider.dart              Channel webhook adapter
      slack/
        config/                            Bot token and endpoint
        targets/                           Channel IDs and names
        options/                           Block Kit, threads and unfurls
        slack_provider.dart                chat.postMessage adapter
      ntfy/
        config/                            Server URL and access token
        enums/                             Priorities
        targets/                           Topics
        options/                           Tags, actions, delay and remote attach
        utils/                             Delay formatting
        ntfy_provider.dart                 JSON publish adapter
      gotify/
        config/                            Server URL and client token
        targets/                           Application tokens
        options/                           Priority and markdown
        gotify_provider.dart               Self-hosted message adapter
      webhook/
        config/                            Headers, timeout and idempotency
        enums/                             HTTP methods
        typedefs/                          JSON payload builder
        targets/                           HTTPS endpoints
        options/                           Per-send payload, headers and method
        utils/                             Header validation and normalization
        webhook_provider.dart              Generic HTTPS JSON adapter
    shared/
      email/                               Email address, target and reply-to contracts
      transport/                           JSON, multipart and raw HTTP transports
      utils/                               UUID, HTTP Retry-After and TR phone helpers


test/                                      Mirrors lib/: core/, providers/<name>/ and
                                           support/ fakes; no test calls a live service
```

Every Dart implementation file has at most one class. Folders follow domain
responsibilities rather than collecting every model in a flat `core` directory.
`enums/`, `utils/` and `typedefs/` belong directly to the module root: `core/`,
`providers/<name>/`, or `shared/` as applicable. These folders
must not be nested inside notification, delivery, targets, config or transport.
Shared helpers contain no provider-specific policy. Test doubles are grouped by the feature they support.

The core depends on its own contracts and shared helpers. Providers depend on
core contracts, never the other way around. Config, targeting, options and
transport are separate provider concerns; adding another provider does not
require changing dispatcher or routing code. `lib/dart_notify.dart` keeps the
public import stable while exporting the relocated types.

## Contracts

`NotifyMessage` contains shared content. `NotificationTarget` identifies
recipients. `NotificationOptions` contains provider-specific delivery settings.
`EmailAddress`, `EmailTarget` and `EmailOptions` are shared by SMTP and Resend
and live under `shared/email`, not inside either provider. Attachments are
content: `NotifyMessage.attachments` holds `NotifyAttachment`
values, and providers declare `supportsAttachments` when the service accepts
files. SMTP reply-to stays an option; OneSignal targeting does not contain
localization, scheduling or presentation settings.

Providers extend `NotificationProvider<T, O>`. The base class checks concrete,
reified target and option types so widening a generic argument cannot silently
pair an SMTP target with a push provider. `ProviderDestination<T, O>` performs
these checks when constructed. The dispatcher works against `DeliveryDestination`
after pairing. It validates all per-send overrides before starting any send.

Destination options are defaults. A batch override is keyed by destination ID;
a direct send accepts typed options. Overrides replace defaults for one send and
do not mutate registered destinations. To clear defaults, pass an empty options
object of the correct provider type.

## Dispatch and errors

Selection resolves explicit destination IDs and groups, deduplicates destination
IDs, and preserves selection order in results. A shared FIFO limiter admits at
most `maxConcurrent` logical deliveries across every call on the same dispatcher.
A delivery keeps its slot through retries/backoff. Different dispatchers do not
share admission limits, even if they share a provider.

A message with attachments is rejected before admission when the destination's
provider reports `supportsAttachments == false`. The synthetic result is
`failed`/`attachment_unsupported` with one attempt and zero elapsed, so an
unsupported destination cannot delay supported ones in the same batch.

The dispatcher normalizes expected `NotifyDeliveryException` failures into
`ProviderResponse`, then makes a single retry decision. Retries require failed or
unknown status, a retryable error, a safe-retry provider and remaining attempts.
`Retry-After` works for returned responses and expected exceptions. Accepted or
partially accepted responses are never retried.

OneSignal uses a per-logical-delivery UUIDv4 key across attempts. SMTP opts out of
automatic retries because a connection can fail after acceptance. A new call is a
new logical delivery, with a new idempotency key.

Netgsm also opts out of retries: its `referansID` is documented for tracking,
without deduplication guarantees. Webhook retries only when its receiver's
idempotency header is explicitly configured. Both share `JsonHttpTransport`,
which enforces response timeouts, blocks redirects and owns only internal clients.

Telegram, Discord, Slack, ntfy and Gotify never retry: none of their APIs exposes
an idempotency key. Telegram and Discord switch to `MultipartHttpTransport` when
the message carries files; the other three reject attachments before any request.
Expo Push, İletimerkezi and Verimor also opt out: tickets, order IDs and campaign
IDs are tracking identifiers, not deduplication guarantees. Resend opts in: every
request carries the delivery's idempotency key as `Idempotency-Key`, so retries
are safe within the key's 24-hour window.
See [Netgsm](providers/netgsm.md), [Webhook](providers/webhook.md),
[Resend](providers/resend.md) and the ops provider guides for their request
mappings and acceptance semantics.

Unexpected exceptions return sanitized outcomes. An opt-in synchronous diagnostic
observer can inspect the original error and stack trace. These values may contain
secrets; applications control redaction. Observer failures do not affect dispatch.

`isFullyAccepted` and `hasAcceptedDeliveries` have identical meanings at result
and report level. Counts distinguish full acceptance, partial acceptance,
rejection, unknown acceptance and skipping. No status implies device/inbox delivery.

## Custom provider

Put the target and provider in separate files.

`audit_target.dart`:

```dart
import 'package:dart_notify/dart_notify.dart';

final class AuditTarget implements NotificationTarget {
  const AuditTarget(this.endpoint);
  final Uri endpoint;
}
```

`audit_provider.dart`:

```dart
import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'audit_target.dart';

final class AuditProvider
    extends NotificationProvider<AuditTarget, NoNotificationOptions> {
  AuditProvider(this.client);
  final http.Client client;

  @override
  String get id => 'internal-audit';

  @override
  bool get supportsSafeRetry => false;

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
      status: DeliveryStatus.failed,
      error: DeliveryError(
        code: 'audit_http_${response.statusCode}',
        message: 'Audit endpoint rejected the request.',
        httpStatus: response.statusCode,
      ),
    );
  }
}
```

Register a `ProviderDestination` with this provider and target. The dispatcher
needs no edits. The application owns the injected HTTP client and should use a
client configured with its timeout and endpoint policy.

## Scope

The package does not persist work, schedule jobs or manage an administrative UI.
Durable queues, deduplication across process restarts, global rate limits and
business-level fallback decisions belong to the host application.
