# Telegram

`TelegramProvider` sends messages through the Telegram Bot API. Create a bot
with [@BotFather](https://t.me/BotFather), then use the bot token with a chat ID
or public channel username.

```dart
final telegram = TelegramProvider(
  id: 'telegram',
  config: TelegramConfig(botToken: Platform.environment['TELEGRAM_BOT_TOKEN']!),
);

try {
  final result = await notify.sendDirect(
    NotifyMessage(title: 'Gateway', body: 'RFID gateway offline'),
    provider: telegram,
    target: TelegramTarget(chatId: '-1001234567890'),
    options: TelegramOptions(
      parseMode: TelegramParseMode.html,
      silent: true,
      threadId: 42,
    ),
  );
  print('${result.status.name}: ${result.messageId}');
} finally {
  telegram.close();
}
```

`TelegramTarget` accepts a numeric chat ID (negative for groups) or an
`@channelusername`. Telegram has no separate title field, so a nonempty
`NotifyMessage.title` is prepended to the body on its own line. The title is
escaped for the selected HTML or MarkdownV2 parse mode. The combined text is
checked against Telegram's text and caption limits. In `html` parse mode
`htmlBody` is preferred when present; in other modes it is used verbatim only
when `body` is blank, so pass a plain `body` unless you send HTML.

## Options

| Dart option | Request field |
| --- | --- |
| `parseMode` (`plain`, `markdownV2`, `html`) | `parse_mode` |
| `silent` | `disable_notification` |
| `protectContent` | `protect_content` |
| `threadId` | `message_thread_id` |
| `replyToMessageId` | `reply_to_message_id` |
| `disableLinkPreview` | `link_preview_options.is_disabled` |

## Attachments

Exactly one attachment is supported per send. It is uploaded with `sendDocument`
and the composed title and body become the caption. More than one
file, a file above 50 MB, or a caption above 1024 characters fails with
`telegram_attachment_limit` before any request.

Text longer than 4096 characters fails with `telegram_message_too_long`. The
adapter never truncates.

## Outcomes and retries

The Bot API returns HTTP 200 for business errors, so the `ok` field is
authoritative. `ok: false` produces `failed` with `telegram_<error_code>`; `429`
is retryable and uses `parameters.retry_after`; server errors and malformed
envelopes are `unknown`. `supportsSafeRetry` is false: an ambiguous retry can
duplicate a message. The request URL contains the bot token, so it is never
copied into errors or diagnostics.

## Sources

- [Telegram Bot API](https://core.telegram.org/bots/api)
