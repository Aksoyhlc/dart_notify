# ntfy

`NtfyProvider` publishes JSON to [ntfy](https://ntfy.sh) or a self-hosted
server. A topic is the destination; anyone who knows it can subscribe unless the
server enforces access control.

```dart
final ntfy = NtfyProvider(
  id: 'ntfy',
  config: NtfyConfig(
    baseUrl: Uri.parse('https://ntfy.example.com'),
    authToken: Platform.environment['NTFY_TOKEN'],
  ),
);

try {
  final result = await notify.sendDirect(
    NotifyMessage(title: 'Gateway', body: 'RFID gateway offline'),
    provider: ntfy,
    target: NtfyTarget(topic: 'ops-alerts'),
    options: NtfyOptions(
      priority: NtfyPriority.high,
      tags: ['warning', 'robot'],
      click: Uri.parse('https://status.example.com'),
    ),
  );
  print('${result.status.name}: ${result.messageId}');
} finally {
  ntfy.close();
}
```

`NtfyConfig.baseUrl` defaults to `https://ntfy.sh` and must be HTTPS without a
path; topics belong to `NtfyTarget`. `authToken` is sent as a bearer token.

## Options

| Dart option | Request field |
| --- | --- |
| `priority` | `priority` (1–5) |
| `tags` | `tags` |
| `click` / `icon` | `click` / `icon` |
| `markdown` | `markdown` |
| `delay` | `delay` (`30m`, `1h`, `2d`, …) |
| `attachUrl` | `attach` (server-side fetch) |

Default priority follows `NotifyPriority`: low→2, normal→3, high→4. With
`markdown: true` the adapter uses `htmlBody` when present, otherwise `body`.

Limits are enforced locally: title above 256 characters fails with
`ntfy_title_too_long`, message above 4096 UTF-8 bytes with
`ntfy_message_too_large`.

`attachUrl` lets the ntfy server fetch a remote file. Local attachment bytes are
not supported by this adapter, so a message with attachments fails with
`attachment_unsupported`; upload the file elsewhere first and pass its URL.

## Outcomes and retries

HTTP 200 returns the published event; `messageId` is its `id`. A malformed
success body is `unknown`. `400`, `401`, `403`, `404` and `413` are `failed`;
`429` is retryable with `Retry-After`; server errors are `unknown`.
`supportsSafeRetry` is false.

## Sources

- [ntfy: Publishing](https://docs.ntfy.sh/publish/)
