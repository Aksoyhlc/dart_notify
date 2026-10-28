# Gotify

`GotifyProvider` posts to a self-hosted [Gotify](https://gotify.net) server. In
the Gotify web UI, create an application, then use its token as the target.
The application token identifies the destination; a separate client token is
only needed when a reverse proxy or the server requires authentication.

```dart
final gotify = GotifyProvider(
  id: 'gotify',
  config: GotifyConfig(
    baseUrl: Uri.parse('https://gotify.example.com'),
    clientToken: Platform.environment['GOTIFY_CLIENT_TOKEN'],
  ),
);

try {
  final result = await notify.sendDirect(
    NotifyMessage(title: 'Gateway', body: 'RFID gateway offline'),
    provider: gotify,
    target: GotifyTarget(appToken: Platform.environment['GOTIFY_APP_TOKEN']!),
    options: GotifyOptions(priority: 8, markdown: true),
  );
  print('${result.status.name}: ${result.messageId}');
} finally {
  gotify.close();
}
```

`GotifyConfig.baseUrl` must be HTTPS without userinfo or fragments. A subpath is
allowed for proxied deployments; `/message` is appended.

## Options

| Dart option | Request field |
| --- | --- |
| `priority` (0–10) | `priority` |
| `markdown` | `extras["client::display"]["contentType"]` |

Default priority follows `NotifyPriority`: low→2, normal→5, high→8. An explicit
priority wins and is range-checked when the options object is constructed.
`markdown: true` sends `text/markdown`, otherwise `text/plain`.

The app token is sent in the `X-Gotify-Key` header, never in the URL. If
`clientToken` is configured, it is sent separately as a Bearer authorization
token for reverse proxies that require their own authentication.

## Outcomes and retries

HTTP 200 returns the created message; `messageId` is its `id`. `400`, `401`,
`403` and `404` are `failed`; `429` is retryable with `Retry-After`; server
errors are `unknown`. Malformed success bodies are `unknown`.

Gotify's message API has no attachment field, so messages with attachments fail
with `attachment_unsupported` before any request. `supportsSafeRetry` is false.

## Sources

- [Gotify: Push messages](https://gotify.net/docs/pushmsg)
