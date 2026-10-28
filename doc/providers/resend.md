# Resend

`ResendProvider` sends email through the Resend API. It shares `EmailTarget`,
`EmailAddress` and `EmailOptions` with the SMTP provider, so the same message and
recipient model works with either transport.

```dart
final resend = ResendProvider(
  id: 'resend',
  config: ResendConfig(
    apiKey: Platform.environment['RESEND_API_KEY']!,
    from: EmailAddress('alerts@example.com', name: 'Monitoring'),
  ),
);

try {
  final result = await notify.sendDirect(
    NotifyMessage(
      title: 'System alert',
      body: 'RFID gateway offline',
      htmlBody: '<p>RFID gateway <b>offline</b></p>',
    ),
    provider: resend,
    target: EmailTarget(
      to: [EmailAddress('ops@example.com')],
      cc: [EmailAddress('oncall@example.com')],
    ),
    options: EmailOptions(
      replyTo: [EmailAddress('support@example.com')],
    ),
  );
  print('${result.status.name}: ${result.messageId}');
} finally {
  resend.close();
}
```

The sender domain must be verified in Resend. A test key can only send to your
own address until a domain is verified. A nonblank `NotifyMessage.body` is sent as
`text`; `htmlBody`, when present, becomes `html`.

## Mapping

| Dart | Resend field |
| --- | --- |
| `ResendConfig.from` | `from` |
| `EmailTarget.to` | `to` |
| `EmailTarget.cc` | `cc` |
| `EmailTarget.bcc` | `bcc` |
| `NotifyMessage.title` | `subject`, or `(no subject)` |
| `NotifyMessage.body` | `text` |
| `NotifyMessage.htmlBody` | `html` |
| `EmailOptions.replyTo` | `reply_to` |
| `NotifyAttachment` | `attachments` as base64 `content` |

`to` accepts at most 50 recipients. A target without a `to` recipient fails with
`resend_recipient_required` before any request. Attachments are base64 encoded;
the package rejects a total above 40 MB after encoding with
`resend_attachment_limit`.

## Outcomes and retries

A 2xx response with an `id` is `accepted`. A 2xx without an `id` is `unknown`.
Validation, authentication, permission and malformed-request responses are
`failed` without retry. Server errors and transport failures are `unknown` and
retryable.

Every request carries `Idempotency-Key` from the delivery context, so
`supportsSafeRetry` is true. Resend keeps keys for 24 hours and returns `409`
when the same key is still in progress or was reused with a different payload:

| Response | Code | Retry |
| --- | --- | --- |
| `429 rate_limit_exceeded` | `resend_rate_limited` | yes, with `Retry-After` |
| `429 daily_quota_exceeded`, `monthly_quota_exceeded` | `resend_quota_exceeded` | no |
| `409 concurrent_idempotent_requests` | `resend_idempotent_in_progress` | yes |
| `409 invalid_idempotent_request` | `resend_idempotent_conflict` | no |
| `400`, `422` | `resend_validation` | no |
| `401` | `resend_auth` | no |
| `403` | `resend_forbidden` | no |
| `5xx` | `resend_http_<status>` | yes |

The default rate limit is 10 requests per second per team. The package does not
add a rate limiter; `maxConcurrent` bounds in-flight work, not requests per
second. Error messages are sanitized and never copy the response body.

Call `close()` when finished. It closes only the HTTP client the provider
created; an injected client stays caller-owned.

## Sources

- [Resend: Send email](https://resend.com/docs/api-reference/emails/send-email)
- [Resend: Idempotency keys](https://resend.com/docs/dashboard/emails/idempotency-keys)
