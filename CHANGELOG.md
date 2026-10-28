## 1.0.0

Initial public release.

- Unified dispatch across OneSignal, Expo Push, SMTP, Resend, Netgsm,
  İletimerkezi, Verimor, Webhook, Telegram, Discord, Slack, ntfy and Gotify,
  plus custom providers.
- Typed targets, options and configs with compile-time and runtime compatibility
  checks; destination IDs, groups and per-send option overrides.
- FIFO concurrency limiting, retry policies with exponential backoff and
  `Retry-After`, safe-retry gating and per-delivery idempotency keys.
- Attachments for SMTP, Resend, Discord and Telegram, with provider-specific
  limits enforced before dispatch; remote attachment URLs for ntfy.
- Turkish SMS helpers: phone normalization, İYS modes and scheduled sends for
  Netgsm, İletimerkezi and Verimor.
- Resend uses `Idempotency-Key` for safe retries and maps rate limits,
  idempotency conflicts and validation failures to sanitized error codes.
- Sanitized delivery errors, opt-in diagnostic callbacks and aggregate reports
  that distinguish accepted, partial, skipped, failed and unknown outcomes.
- Durable queues, job scheduling and cross-process deduplication remain the host
  application's responsibility.
