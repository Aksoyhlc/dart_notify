# Generic Webhook

`WebhookProvider` sends JSON to an application-owned HTTPS endpoint. Its target
contains the URL; config holds authentication headers, timeout and defaults;
options customize each send.

```dart
final webhook = WebhookProvider(
  id: 'events',
  config: WebhookConfig(
    headers: {'Authorization': 'Bearer ${Platform.environment['WEBHOOK_TOKEN']!}'},
    payloadBuilder: (message) => {
      'event': 'system.alert',
      'text': message.body,
      'metadata': message.data,
    },
  ),
);

try {
  await notify.sendDirect(
    NotifyMessage(body: 'Gateway offline', data: {'device': 'gateway-1'}),
    provider: webhook,
    target: WebhookTarget(Uri.parse('https://example.com/hooks/alerts')),
    options: WebhookOptions(headers: {'X-Trace-Id': 'trace-42'}),
  );
} finally {
  webhook.close();
}
```

Use `dart:io` and `package:dart_notify/dart_notify.dart`. `notify` is a
`DartNotify` instance. Multiple webhook destinations, groups and per-destination
option overrides use the existing dispatch API.

## Request format

The default is POST with `application/json; charset=utf-8`. `WebhookMethod.put`
and `WebhookMethod.patch` are also supported. Config defines the default method;
`WebhookOptions.method` overrides it for one send.

Without a builder, JSON includes `body`, `priority`, and, when present, `title`,
`htmlBody` and `data`. `WebhookOptions.payload` replaces both this default and
the builder output. A custom payload must be a JSON-serializable object.

Headers in options override config headers case-insensitively. Transport headers
such as Host, Content-Type, Content-Length and Transfer-Encoding are reserved.
Invalid names and CR/LF injection are rejected before sending. HTTPS is required;
URL userinfo and fragments are rejected. Redirects are not followed, preventing
headers from being forwarded to a different endpoint. Applications should treat
endpoint URLs as trusted configuration or enforce their own destination allowlist.

## Outcomes and idempotency

Any HTTP 2xx means the receiver accepted the HTTP request. This generic adapter
does not infer delivery from an arbitrary response body. HTTP 408/5xx, network
failures and timeouts have `unknown` acceptance. Other non-2xx responses are
`failed`. Results never contain raw server bodies or authentication material.

By default, requests are not retried: the receiver might already have processed
them. If the receiver guarantees deduplication through a particular header, opt in:

```dart
WebhookConfig(idempotencyHeader: 'Idempotency-Key');
```

This enables dispatcher retries on transport uncertainty, HTTP 408/429/5xx, within
the configured retry policy. `Retry-After` is honored. The dispatcher writes a
new key per logical delivery, stable across attempts; config/options cannot
replace that key. Do not enable this setting just because an endpoint accepts
the header: the receiver must actually deduplicate it.

The 15-second default timeout bounds waiting for both request and response body.
Timeouts do not prove the remote request was cancelled. Application-level repeat
calls get new keys. Call `close()` for internally created HTTP clients; injected
clients remain caller-owned. `example/webhook.dart` is a runnable example.

## Sources

- [IETF draft: The Idempotency-Key HTTP header field](https://datatracker.ietf.org/doc/draft-ietf-httpapi-idempotency-key-header/)
