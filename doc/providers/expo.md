# Expo Push

`ExpoPushProvider` sends push notifications directly through the Expo Push
Service for Expo-managed apps, without OneSignal. Tokens come from
`expo-notifications` in the mobile app; the server only needs them.

```dart
final expo = ExpoPushProvider(
  id: 'expo',
  config: ExpoPushConfig(
    accessToken: Platform.environment['EXPO_ACCESS_TOKEN'], // optional
  ),
);

try {
  final result = await notify.sendDirect(
    NotifyMessage(title: 'System alert', body: 'RFID gateway offline'),
    provider: expo,
    target: ExpoPushTarget(tokens: [
      'ExpoPushToken[xxxxxxxxxxxxxxxxxxxxxx]',
      'ExponentPushToken[yyyyyyyyyyyyyyyyyyyy]',
    ]),
    options: ExpoPushOptions(
      sound: 'default',
      channelId: 'alerts',
      priority: ExpoPriority.high,
      data: {'gateway': 'rfid-3'},
    ),
  );
  print('${result.status.name}: ${result.messageId}');
} finally {
  expo.close();
}
```

`ExpoPushTarget` deduplicates tokens and rejects anything that is not
`ExpoPushToken[...]` or `ExponentPushToken[...]`. `accessToken` enables Expo's
enhanced security mode and is sent as a bearer token.

## Options

| Dart option | Request field |
| --- | --- |
| `sound` | `sound` |
| `badge` | `badge` |
| `channelId` | `channelId` |
| `categoryId` | `categoryId` |
| `ttl` | `ttl` (seconds) |
| `expiration` | `expiration` (epoch seconds) |
| `priority` | `priority` |
| `subtitle` | `subtitle` |
| `mutableContent` | `mutableContent` |
| `data` | `data` |

`priority` is not derived from `NotifyPriority`; Expo's `high` changes delivery
urgency and Android throttling, so it stays an explicit opt-in.

## Batching and outcomes

Each token becomes its own message object, so tickets map 1:1 to tokens.
Requests are split into chunks of 100. Every ticket `ok` is `accepted`; a mix of
`ok` and `error` tickets is `partiallyAccepted`; all errors are `failed`. A
malformed envelope, a missing `data` array or a 5xx is `unknown`. If a later
chunk times out or fails after earlier chunks were accepted, the result is
`partiallyAccepted` with `expo_partial_batch`, listing accepted, failed and
uncertain token indexes. Transport failures are returned, not thrown.

Ticket errors are reported as `expo_<error>` (`expo_device_not_registered`,
`expo_message_too_big`, `expo_message_rate_exceeded`,
`expo_invalid_credentials`). The error message lists zero-based token indexes,
never the tokens themselves. `messageId` is the ticket ID for a single-token
target and `null` for fan-out.

`supportsSafeRetry` is false. Expo returns tickets, not idempotency keys, so a
retry after an ambiguous failure can duplicate a notification. Receipt polling
(`getReceipts`) is intentionally out of scope: it needs ticket IDs persisted for
at least 15 minutes, which belongs to the host application's queue. Drop tokens
that report `DeviceNotRegistered` from your own store.

Attachments are not supported by the Expo Push Service; a message with files
fails with `attachment_unsupported`.

## Sources

- [Expo: Send notifications with the Expo Push Service](https://docs.expo.dev/push-notifications/sending-notifications/)
