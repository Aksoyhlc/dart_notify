# Verimor

`VerimorProvider` sends SMS through the Verimor API v2 JSON endpoint. The
username is the numeric account (for example `908501234567`), the password is
the API password defined in the Verimor panel, and the server IP must be
allow-listed; otherwise the API answers `401`/`403`.

```dart
final sms = VerimorProvider(
  id: 'verimor',
  config: VerimorConfig(
    username: Platform.environment['VERIMOR_USERNAME']!,
    password: Platform.environment['VERIMOR_PASSWORD']!,
    sourceAddr: Platform.environment['VERIMOR_SOURCE']!,
  ),
);

try {
  final result = await notify.sendDirect(
    NotifyMessage(body: 'Siparişiniz kargoya verildi.'),
    provider: sms,
    target: VerimorTarget(numbers: ['5321234567']),
    options: VerimorOptions(
      datacoding: VerimorDatacoding.gsmTurkish,
      validFor: const Duration(hours: 48),
      customId: 'order-42',
    ),
  );
  print('${result.status.name}: ${result.messageId}');
} finally {
  sms.close();
}
```

The target deduplicates recipients and normalizes `5XXXXXXXXX`, `05XXXXXXXXX`,
`905XXXXXXXXX` and `+905XXXXXXXXX` to `905XXXXXXXXX`. Other country codes are
rejected by this adapter.

## Options

| Dart option | Request field |
| --- | --- |
| `datacoding` | `datacoding` (0 GSM basic, 1 GSM Turkish, 2 UCS2) |
| `validFor` (whole minutes, 1 minute – 48 hours) | `valid_for` (`HH:MM`) |
| `sendAt` | `send_at` (`yyyy-MM-ddTHH:mm:ss`) |
| `customId` (1–50 characters) | `custom_id` |
| `commercial` | `is_commercial` |
| `iysRecipientType` | `iys_recipient_type` (`BIREYSEL`/`TACIR`) |

One message entry is sent per recipient. `sendAt` is a Türkiye-local calendar
time; UTC values are rejected. Commercial sends require
`VerimorIysRecipientType`, otherwise the options constructor throws instead of
producing a legally ambiguous message.

## Outcomes and retries

A successful request returns `text/plain` with the numeric campaign ID, which
becomes `messageId`. HTTP 400 bodies are error tokens such as
`INSUFFICIENT_CREDITS` or `MISSING_MESSAGE`, normalized to
`verimor_<error>`. `401` is `verimor_unauthorized`, `403` is
`verimor_ip_not_allowed`, `429` is retryable, and server errors are `unknown`.
Only recognized Verimor error tokens are included in `DeliveryError.code`;
unknown response text is replaced with `verimor_unknown_error`. A malformed
2xx response is `unknown` because the campaign may have been accepted.

`custom_id` is tracking metadata for your own reports, not an idempotency key.
`supportsSafeRetry` is false; the dispatcher limiter is not a rate limiter, and
Verimor's per-minute ceiling belongs to the host application. Acceptance means
the campaign was queued, not that the handset received it.

## Sources

- [Verimor SMS API](https://developer.verimor.com.tr/smsapi)
- [Verimor SMS API user guide](https://github.com/verimor/SMS-API/blob/master/user_guide.md)
