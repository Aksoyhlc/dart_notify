# Slack

`SlackProvider` calls `chat.postMessage` with a bot or user token. The token
needs the `chat:write` scope and, when posting to a public channel the app is
not in, the app must be invited first.

```dart
final slack = SlackProvider(
  id: 'slack',
  config: SlackConfig(token: Platform.environment['SLACK_BOT_TOKEN']!),
);

try {
  final result = await notify.sendDirect(
    NotifyMessage(body: 'RFID gateway offline'),
    provider: slack,
    target: SlackTarget(channel: 'C0123456789'),
    options: SlackOptions(
      threadTs: '1737721534.260505',
      blocks: [
        {
          'type': 'section',
          'text': {'type': 'mrkdwn', 'text': '*Gateway*\nOffline for 4 minutes.'},
        },
      ],
    ),
  );
  print('${result.status.name}: ${result.messageId}');
} finally {
  slack.close();
}
```

`SlackTarget` accepts a channel ID (`C…`, `G…`, `D…`) or a name such as
`#ops`. The message body is used as the `text` fallback, which Slack shows in
notifications and to clients that cannot render blocks. A nonempty message
title is prepended on its own line because Slack has no separate title field.
When `body` is blank, `htmlBody` is used verbatim as the fallback text; Slack
does not render HTML, so pass a plain `body` for this channel.

## Options

| Dart option | Request field |
| --- | --- |
| `blocks` | `blocks` |
| `threadTs` | `thread_ts` |
| `mrkdwn` (default true) | `mrkdwn` |
| `unfurlLinks` / `unfurlMedia` | `unfurl_links` / `unfurl_media` |
| `username` / `iconEmoji` | `username` / `icon_emoji` |

Blocks are raw Block Kit maps, mirroring how OneSignal filters are passed
through. The package validates shape only: at most 50 entries, JSON-serializable,
and a nonblank text fallback whenever blocks are present. Text objects inside
blocks are capped at 3000 characters. Violations return `slack_invalid_blocks`.
Text is capped at 40 000 characters
(`slack_text_too_long`).

## Outcomes and retries

Slack answers HTTP 200 for both success and business errors. `ok: true` is
`accepted` with the message `ts`; `ok: false` is `failed` with
`slack_<error>` (`slack_channel_not_found`, `slack_not_in_channel`,
`slack_invalid_auth`). `429` uses `Retry-After`; server errors are `unknown`.

Attachments are not supported by this adapter: Slack file upload is a separate
multi-step flow with different scopes. Sending a message with attachments fails
with `attachment_unsupported` before any request. `supportsSafeRetry` is false.

## Sources

- [Slack: chat.postMessage](https://api.slack.com/methods/chat.postMessage)
- [Slack: Block Kit](https://docs.slack.dev/block-kit/)
