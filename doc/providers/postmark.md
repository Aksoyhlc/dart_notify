# Postmark

Use a Postmark **Server API Token** and a sender configured in that server's
account. The provider posts a single email per delivery.

```dart
final postmark = PostmarkProvider(
  id: 'postmark',
  config: PostmarkConfig(
    serverToken: Platform.environment['POSTMARK_SERVER_TOKEN']!,
    from: EmailAddress('orders@example.com', name: 'Orders'),
    messageStream: 'outbound',
  ),
);

final result = await notify.sendDirect(
  NotifyMessage(title: 'Your receipt', body: 'Thanks for your order.'),
  provider: postmark,
  target: EmailTarget(to: [EmailAddress('customer@example.net')]),
  options: EmailOptions(replyTo: [EmailAddress('support@example.com')]),
);
```

`title` is the subject. `body` and `htmlBody` supply the text and HTML parts.
`EmailTarget` requires at least one To address for Postmark and supports up
to 50 recipients across To, Cc and Bcc combined. Use one mailbox per
`EmailAddress`. Leave `messageStream` unset to use the server's default
transactional stream.

Use `NotifyMessage.attachments` for file bytes. Postmark limits each body part
to 5 MB and the total email to 10 MB including base64-encoded attachments.
The provider rejects blocked file extensions and oversized content before the
request. Postmark applies its final message size limit on the server.

An accepted result contains the Postmark `MessageID`. Common errors include
`postmark_auth`, `postmark_inactive_recipient`, `postmark_payload_limit` and
`postmark_message_stream`. The provider makes one attempt per delivery.
Call `postmark.close()` when finished.

[Email API](https://postmarkapp.com/developer/api/email-api) ·
[Size limits](https://postmarkapp.com/support/article/1056-what-are-the-attachment-and-email-size-limits) ·
[API errors](https://postmarkapp.com/developer/api/overview)
