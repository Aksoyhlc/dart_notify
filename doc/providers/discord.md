# Discord

`DiscordProvider` posts to a channel webhook. In Discord, open
**Channel settings → Integrations → Webhooks**, create a webhook and copy its
URL. It already contains the credentials; keep it on the server.

```dart
final discord = DiscordProvider(
  id: 'discord',
  config: DiscordConfig(username: 'Monitoring', threadId: '123456789012345678'),
);

try {
  final result = await notify.sendDirect(
    NotifyMessage(body: 'RFID gateway offline'),
    provider: discord,
    target: DiscordTarget(
      webhookUrl: Uri.parse(Platform.environment['DISCORD_WEBHOOK_URL']!),
    ),
    options: DiscordOptions(
      embeds: [
        DiscordEmbed(
          title: 'Gateway alert',
          description: 'Last seen 4 minutes ago.',
          color: 0xE07A5F,
          fields: [DiscordEmbedField(name: 'Site', value: 'Warehouse 3')],
        ),
      ],
    ),
  );
  print('${result.status.name}: ${result.messageId}');
} finally {
  discord.close();
}
```

`DiscordTarget` requires an HTTPS `discord.com`/`discordapp.com` webhook URL
(including `ptb.` and `canary.` hosts) with an `/api/webhooks/` path. The
adapter always sends `?wait=true`, so accepted results carry the message ID.
Discord has no separate message title field, so a nonempty
`NotifyMessage.title` is prepended to the content on its own line. The
composed content is checked against the 2000-character limit; embed titles are
controlled separately by `DiscordOptions.embeds`.
When `body` is blank, `htmlBody` is used verbatim as the fallback text; Discord
does not render HTML, so pass a plain `body` for this channel.

## Options

| Dart option | Request field |
| --- | --- |
| `embeds` | `embeds` |
| `tts` | `tts` |
| `suppressEmbeds` | `flags: 4` |
| `allowedMentions` (default empty) | `allowed_mentions.parse` |

`allowedMentions` accepts `roles`, `users` and `everyone`. It defaults to an
empty list, so an alert containing `@everyone` cannot ping a server unless the
caller opts in.

## Limits and attachments

Content is limited to 2000 characters, 10 embeds and 6000 characters across
embeds; violations fail locally with `discord_content_too_long` or
`discord_embed_limit`. A message needs text or at least one embed.

Up to 10 files of 25 MB each are sent as `multipart/form-data` with a
`payload_json` part and `files[0…9]`. Larger sets fail with
`discord_attachment_limit`.

## Outcomes and retries

`200` returns the message object, `204` means accepted without a body. `429`
uses the body `retry_after` (seconds), falling back to the header; `400`, `401`,
`403`, `404` and `413` are `failed`; server errors are `unknown`.
`supportsSafeRetry` is false.

## Sources

- [Discord: Execute Webhook](https://discord.com/developers/docs/resources/webhook#execute-webhook)
