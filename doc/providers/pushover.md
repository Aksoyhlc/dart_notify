# Pushover

Register a Pushover application for an app token. Each destination uses one
user or group key. Add `devices` to target named devices where Pushover honors
device selection. Pushover can fall back to all active devices for a user if a
requested device is no longer valid.

```dart
final pushover = PushoverProvider(
  id: 'pushover',
  config: PushoverConfig(appToken: Platform.environment['PUSHOVER_APP_TOKEN']!),
);

final result = await notify.sendDirect(
  NotifyMessage(title: 'Backup failed', body: 'The database backup did not finish.'),
  provider: pushover,
  target: PushoverTarget(userKey: Platform.environment['PUSHOVER_USER_KEY']!),
  options: PushoverOptions(
    priority: PushoverPriority.emergency,
    retryEvery: Duration(minutes: 1),
    expireAfter: Duration(minutes: 30),
  ),
);
```

Titles allow 250 characters and messages allow 1024. With `html: true`, the
provider uses `htmlBody` when available and otherwise formats `body` as
Pushover HTML. Other options include `sound`, `url`, `urlTitle` and `ttl`.
One image of up to 5,242,880 bytes can be attached via
`NotifyMessage.attachments` with its image MIME type.

`NotifyPriority.high` maps to Pushover's high priority, which bypasses quiet
hours. Emergency priority must be explicit and requires a retry interval of at
least 30 seconds and an expiry of at most 10,800 seconds. Pushover repeats
emergency messages until acknowledgement or expiry. You can supply
`acknowledgementCallback` to receive acknowledgement at an HTTPS endpoint.

`messageId` contains the response's request ID, or the receipt for an
emergency send. HTTP 429 maps to `pushover_quota_exceeded`. The provider
makes one attempt per delivery. Call `pushover.close()` when finished.

[Pushover Message API](https://pushover.net/api)
