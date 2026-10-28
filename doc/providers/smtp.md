# SMTP

`SmtpProvider` sends email through any SMTP server using the
[mailer](https://pub.dev/packages/mailer) package. It shares `EmailTarget`,
`EmailAddress` and `EmailOptions` with the Resend provider.

```dart
final email = SmtpProvider(
  id: 'email',
  config: SmtpConfig(
    host: 'smtp.example.com',
    username: 'alerts@example.com',
    password: Platform.environment['SMTP_PASSWORD']!,
    from: EmailAddress('alerts@example.com', name: 'Monitoring'),
  ),
);

final result = await notify.sendDirect(
  NotifyMessage(
    title: 'Weekly report',
    body: 'The report is attached.',
    htmlBody: '<p>The report is <b>attached</b>.</p>',
    attachments: [
      NotifyAttachment(
        fileName: 'report.csv',
        bytes: reportBytes,
        contentType: 'text/csv',
      ),
    ],
  ),
  provider: email,
  target: EmailTarget(
    to: [EmailAddress('ops@example.com', name: 'Ops')],
    bcc: [EmailAddress('archive@example.com')],
  ),
  options: EmailOptions(replyTo: [EmailAddress('support@example.com')]),
);
```

## Connection security

| `SmtpConfig` | Behaviour |
| --- | --- |
| `security: SmtpSecurity.startTlsRequired` (default), port 587 | Requires STARTTLS; the send fails if the server does not offer it. |
| `security: SmtpSecurity.sslTls`, `port: 465` | Implicit TLS from the first byte. |
| `security: SmtpSecurity.none` | Permits plaintext; for trusted internal relays only. The transport may still upgrade if the server advertises STARTTLS. |

Certificates are always verified. `username` and `password` must be given
together or not at all. The default timeout is 20 seconds.

## Message mapping

`title` is the subject (`(no subject)` when absent), `body` is the plain-text
part and `htmlBody`, when present, the HTML part. `EmailTarget` takes `to`, `cc`
and `bcc`; at least one recipient is required. `EmailOptions.replyTo` sets the
`Reply-To` header. Attachments from `NotifyMessage.attachments` are added as
MIME parts; bound their size in your application, because SMTP servers enforce
their own limits.

## Outcomes and retries

| Failure | Status | Code |
| --- | --- | --- |
| Server accepted the message | `accepted` | |
| Authentication rejected | `failed` | `smtp_auth` |
| Message rejected as invalid | `failed` | `smtp_invalid_message` |
| Protocol error during the transaction | `unknown` | `smtp_protocol` |
| Other mailer error | `unknown` | `smtp_error` |
| Timeout | `unknown` | `smtp_timeout` |
| Network failure | `unknown` | `smtp_network` |

`supportsSafeRetry` is false. A connection can drop after the server accepted
the message, and SMTP has no idempotency key, so a retry could send a duplicate.
Each logical delivery is attempted once.

## Transport

The default `MailerSmtpTransport` opens and closes a connection for every send,
so the provider has no `close()` method. Pass a custom `SmtpTransport` to the
provider to reuse connections or to test without a server.

## Sources

- [mailer package](https://pub.dev/packages/mailer)
- [RFC 5321: Simple Mail Transfer Protocol](https://www.rfc-editor.org/rfc/rfc5321)
- [RFC 3207: SMTP Service Extension for Secure SMTP over TLS](https://www.rfc-editor.org/rfc/rfc3207)
