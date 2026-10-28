# Netgsm SMS

`NetgsmProvider` sends standard SMS using REST v2 and HTTP Basic authentication.
Credentials are the Netgsm subscriber username and API sub-user password. The
sender must be an approved 3–11-character message header on that account.

```dart
final sms = NetgsmProvider(
  id: 'sms',
  config: NetgsmConfig(
    username: Platform.environment['NETGSM_USERNAME']!,
    password: Platform.environment['NETGSM_PASSWORD']!,
    sender: 'MYAPP',
    appName: 'my_service',
  ),
);

try {
  final result = await notify.sendDirect(
    NotifyMessage(body: 'Siparişiniz kargoya verildi.'),
    provider: sms,
    target: NetgsmTarget(numbers: ['5321234567', '+421123456789']),
    options: NetgsmOptions(
      encoding: NetgsmEncoding.turkish,
      iysFilter: NetgsmIysFilter.informational,
      referenceId: 'order-42',
    ),
  );
  print('${result.status.name}: ${result.messageId}');
} finally {
  sms.close();
}
```

Use `dart:io` and `package:dart_notify/dart_notify.dart`. `notify` is a
`DartNotify` instance; registered destinations and groups work identically to
other providers. The adapter sends `NotifyMessage.body`; title, HTML, data and
priority are not SMS text and are not appended automatically.

`NetgsmTarget` deduplicates numbers. Domestic numbers use Netgsm notation such
as `5321234567`. A leading `+` becomes `00` for international submission. Other
formatting such as embedded spaces or parentheses is rejected.

## Options

| Dart option | Request value |
| --- | --- |
| `NetgsmEncoding.utf8` (default) | `UTF-8` |
| `NetgsmEncoding.turkish` | `TR` |
| `NetgsmEncoding.unicode` | `UNICODE` |
| `NetgsmIysFilter.informational` (default) | `0` |
| `NetgsmIysFilter.commercialIndividual` | `11` |
| `NetgsmIysFilter.commercialBusiness` | `12` |

Choose the IYS setting for the content you send; the adapter does not infer it.
`appName` and `partnerCode` are optional config fields. A per-send `referenceId`
is serialized as `referansID` for tracking, not used as an idempotency guarantee.

`startAt` and `stopAt` set scheduled submission using `ddMMyyyyHHmm`. Their
calendar fields are interpreted as Netgsm-local wall time, at minute precision;
the adapter performs no implicit host/UTC conversion. Supply the intended
calendar time explicitly. If both are set, stop must be later than start.

```dart
NetgsmOptions(
  encoding: NetgsmEncoding.turkish,
  startAt: DateTime(2026, 11, 3, 9, 5),
  stopAt: DateTime(2026, 11, 3, 21, 5),
);
```

## Outcomes and retries

The default endpoint is `https://api.netgsm.com.tr/sms/rest/v2/send`. Code `00`
and a nonempty string `jobid` mean upstream acceptance. The job ID remains a
string, including long IDs. Codes `01` and `02` with a job ID also mean acceptance,
with a sanitized schedule-adjustment warning in `result.error`.

Other numeric API codes produce `failed`, including errors carried by HTTP 406.
The result contains `netgsm_<code>`; raw server descriptions are never exposed.
Malformed success bodies, network failures, timeouts and HTTP 5xx are `unknown`.

SMS is never retried automatically. A lost response may follow successful
submission, and the documented reference ID does not guarantee deduplication.
API acceptance is not handset delivery. Querying reports, balance, inbox,
templates, OTP-specific endpoints, voice and IYS management is outside this
notification adapter.

The default timeout is 15 seconds. Call `close()` for internally created HTTP
clients. Injected `http.Client` instances remain caller-owned. The standalone
example is `example/netgsm.dart`; running it sends a real SMS.

## Sources

- [Netgsm API documentation](https://www.netgsm.com.tr/dokuman/)
