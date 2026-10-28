# Delivery semantics

This page describes how `DartNotify` selects destinations, applies options,
limits concurrency, retries and reports outcomes. Provider-specific mappings
are in the [provider guides](providers/).

## Selection and options

`send` resolves explicit destination IDs (`to`) and named `groups`, removes
duplicate IDs and keeps the selection order in `DispatchReport.results`,
regardless of completion order. `sendDirect` delivers to a single provider and
target without registering a destination.

Targets carry recipient identity, options carry delivery settings and configs
carry credentials. Options registered on a destination are defaults. A per-send
override keyed by destination ID **replaces** the defaults for that call; the
two are never merged. Omitting an override keeps the defaults, and an empty
options object of the provider's type, such as `EmailOptions()`, clears them for
one send.

The whole call is rejected before any outbound request when it selects an
unknown destination, overrides a destination that is not selected, or passes an
options type the provider does not accept. Provider, target and options
compatibility is also checked when a `ProviderDestination` is constructed,
including when callers widen the generic types.

## Attachments

Attachments are message content: `NotifyMessage.attachments` carries the same
files to every selected destination. A destination whose provider reports
`supportsAttachments == false` fails with `attachment_unsupported` before
admission, with one attempt, zero elapsed time and no concurrency slot used.
SMTP, Resend, Discord and Telegram carry files; ntfy can fetch a remote file
through `NtfyOptions.attachUrl`.

## Outcomes and reports

| Status | Meaning |
| --- | --- |
| `accepted` | The upstream service fully accepted the request. |
| `partiallyAccepted` | Accepted for some recipients and rejected for others. |
| `skipped` | Nothing was sent, for example no eligible push subscription. |
| `failed` | The provider rejected the request. |
| `unknown` | Acceptance cannot be determined, including transport failures and malformed responses. |

`DeliveryResult` and `DispatchReport` both expose `isFullyAccepted` and
`hasAcceptedDeliveries`. A report is fully accepted only when it is nonempty and
every destination was fully accepted. `isPartiallyAccepted` means at least one
destination has acceptance while the report is not fully accepted.

Counts refer to **destinations**, not individual recipients. `acceptedCount`
includes full and partial acceptance; `fullyAcceptedCount`, `partialCount`,
`failedCount`, `unknownCount` and `skippedCount` separate the outcomes.
`hasFailures` is true when at least one result is `failed` or `unknown`. Check
`isFullyAccepted` when partial or skipped outcomes also need attention.

Each `DeliveryError` has a stable, sanitized `code`, a short message, an
optional `httpStatus` and a `retryable` flag. Error messages never contain
credentials, tokens or upstream response bodies.

## Unexpected errors

An unexpected exception inside a provider becomes an `unknown` result with the
code `unexpected_error`. The optional, synchronous `onUnexpectedError` callback
receives the original exception, stack trace, destination ID, provider ID and
attempt number. These values may contain secrets, so redact them before storing.
An exception thrown by the callback does not change the delivery outcome.

## Concurrency

`maxConcurrent` bounds logical deliveries across **all** `send` and `sendDirect`
calls on one `DartNotify` instance. Admission is FIFO, and a delivery keeps its
slot through retries and backoff. Separate dispatcher instances have separate
limits. This is a concurrency bound, not a requests-per-second rate limiter.
`DeliveryResult.elapsed` excludes time spent waiting for admission.

## Retries and idempotency

Each logical delivery gets a fresh UUIDv4 idempotency key, reused across its
attempts. A retry happens only when all of these hold:

- the status is `failed` or `unknown`;
- the error is marked retryable;
- the provider reports `supportsSafeRetry`;
- attempts remain under `RetryPolicy.maxAttempts` (3 by default).

Delays grow exponentially up to `RetryPolicy.maxDelay`; a valid `Retry-After`
overrides the computed delay. Returned responses and expected
`NotifyDeliveryException`s follow the same rules. Accepted and partially
accepted results are never retried.

OneSignal and Resend send the key upstream, and Webhook does so when its
idempotency header is configured, so their retries are safe. SMTP, Netgsm,
İletimerkezi, Verimor, Expo Push, Telegram, Discord, Slack, ntfy and Gotify make
one attempt: their APIs cannot deduplicate a repeated request, so a retry after
an ambiguous failure could send the notification twice.

A new `send` call is a new logical delivery with a new key. Persistent queues,
scheduling, deduplication across process restarts and global rate limits belong
to the host application.
