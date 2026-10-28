# İletimerkezi

`IletimerkeziProvider` sends SMS through the İletimerkezi REST v1 JSON API.
Get the API key and hash from `panel.iletimerkezi.com` under
**Ayarlar → Güvenlik → API Erişimi**, and enable "API kullanımına izin ver".
Without that toggle every request returns `401`.

```dart
final sms = IletimerkeziProvider(
  id: 'iletimerkezi',
  config: IletimerkeziConfig(
    key: Platform.environment['ILETIMERKEZI_API_KEY']!,
    hash: Platform.environment['ILETIMERKEZI_API_HASH']!,
    sender: Platform.environment['ILETIMERKEZI_SENDER']!,
  ),
);

try {
  final result = await notify.sendDirect(
    NotifyMessage(body: 'Siparişiniz kargoya verildi.'),
    provider: sms,
    target: IletimerkeziTarget(numbers: ['05321234567', '+905321234567']),
    options: IletimerkeziOptions(iys: IletimerkeziIys.transactional),
  );
  print('${result.status.name}: ${result.messageId}');
} finally {
  sms.close();
}
```

The target deduplicates recipients and normalizes `5XXXXXXXXX`, `05XXXXXXXXX`,
`905XXXXXXXXX` and `+905XXXXXXXXX` to `905XXXXXXXXX`. Other country codes are
rejected; enable international mode in the panel and use a provider that models
it if you need them.

## Options

| Dart option | Request field |
| --- | --- |
| `IletimerkeziIys.transactional` (default) | `iys: "0"` |
| `IletimerkeziIys.commercialIndividual` | `iys: "1"`, `iysList: "BIREYSEL"` |
| `IletimerkeziIys.commercialBusiness` | `iys: "1"`, `iysList: "TACIR"` |
| `sendAt` | `sendDateTime` (`dd/MM/yyyy HH:mm`) |

`iys` is always sent: choose transactional for OTP, notifications and reminders,
commercial for marketing. `sendAt` is a Türkiye-local calendar time; UTC values
are rejected rather than silently reinterpreted. With the `APITEST` sender only
transactional mode is accepted.

## Outcomes and retries

`response.status.code` is authoritative even on HTTP 200. Code `200` with a
nonblank `response.order.id` is `accepted`; any other code is `failed` with
`iletimerkezi_<code>` (`401`, `451`, `452`, `466`, …). A success envelope with a
blank order ID is `unknown`.

`451` means an identical sender + recipient + text order was submitted recently.
It is a rejection, not deduplication, so it is never retried automatically.
`supportsSafeRetry` is false and SMS acceptance is not device delivery.

## Sources

- [İletimerkezi API: Send SMS](https://www.iletimerkezi.com/docs/api/send-sms)
