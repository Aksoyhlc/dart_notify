# OneSignal

`OneSignalProvider` creates push notifications through the OneSignal Create
Notification API. Use the app ID and a REST API key from the OneSignal
dashboard; keep the key on your server.

```dart
final push = OneSignalProvider(
  id: 'push',
  config: OneSignalConfig(
    appId: Platform.environment['ONESIGNAL_APP_ID']!,
    apiKey: Platform.environment['ONESIGNAL_API_KEY']!,
  ),
);

try {
  final result = await notify.sendDirect(
    NotifyMessage(
      title: 'Order shipped',
      body: 'Your order is on the way.',
      priority: NotifyPriority.high,
      data: {'orderId': 42},
    ),
    provider: push,
    target: OneSignalTarget.externalIds(['user-42']),
    options: OneSignalOptions(
      language: 'tr',
      localizedBodies: {'tr': 'Siparişiniz yola çıktı.'},
      collapseId: 'order-42',
      ttl: const Duration(hours: 1),
    ),
  );
  print('${result.status.name}: ${result.messageId}');
} finally {
  push.close();
}
```

## Targets

Each constructor selects one targeting mode, so modes cannot be mixed:

| Constructor | Request field |
| --- | --- |
| `OneSignalTarget.externalIds(ids)` | `include_aliases.external_id` |
| `OneSignalTarget.onesignalIds(ids)` | `include_aliases.onesignal_id` |
| `OneSignalTarget.aliases(key, ids)` | `include_aliases.<key>` |
| `OneSignalTarget.subscriptionIds(ids)` | `include_subscription_ids` |
| `OneSignalTarget.segments(included, excluded: ...)` | `included_segments`, `excluded_segments` |
| `OneSignalTarget.filters(filters)` | `filters` |

ID lists accept 1–20,000 nonblank, deduplicated values. Filters are raw
OneSignal filter maps (1–200 entries) and are passed through unchanged; check
their fields against the current OneSignal documentation.

## Message and options

`NotifyMessage.body` becomes `contents` and `title` becomes `headings`, both
under `en` and the selected `language`. `localizedTitles` and `localizedBodies`
add or override languages. `data` is sent as the notification's `data`.
`NotifyPriority.high` maps to priority 10; low and normal map to 5. A blank
`body` fails with `invalid_push_body`, because a push needs plain text.

| Dart option | Request field |
| --- | --- |
| `bigPicture` | `big_picture` |
| `webImage` | `chrome_web_image` |
| `androidChannelId` | `android_channel_id` |
| `url` (HTTPS) | `url` |
| `appUrl` | `app_url` |
| `webUrl` (HTTPS) | `web_url` |
| `collapseId` | `collapse_id` |
| `ttl` (0–28 days) | `ttl` in seconds |
| `sendAfter` | `send_after` (UTC ISO 8601) |

Attachments are not supported; a message with attachments fails with
`attachment_unsupported` before any request.

## Outcomes and retries

| Response | Status | Code |
| --- | --- | --- |
| 2xx with an `id` and no `errors` | `accepted` | |
| 2xx with an `id` and `errors` | `partiallyAccepted` | `onesignal_partial_rejection` |
| 2xx without an `id` | `skipped` | `onesignal_no_recipients` |
| Malformed 2xx | `unknown` | `onesignal_invalid_response` |
| 408, 429, 5xx | `failed`, retryable | `onesignal_http_<status>` |
| Other non-2xx | `failed` | `onesignal_http_<status>` |
| Timeout or connection failure | `unknown`, retryable | `onesignal_timeout`, `onesignal_network_error` |

Every request carries the delivery's `idempotency_key`, reused across attempts,
so `supportsSafeRetry` is true and temporary failures are retried according to
the dispatcher's `RetryPolicy`. `Retry-After` is honoured. A skipped result
usually means none of the targeted users has an eligible push subscription.

The default timeout is 15 seconds. Call `close()` to close the HTTP client the
provider created; an injected `http.Client` stays caller-owned.

## Sources

- [OneSignal: Create notification](https://documentation.onesignal.com/reference/push-notification)
