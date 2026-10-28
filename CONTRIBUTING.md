# Contributing

Thanks for helping improve dart_notify. Bug reports, provider requests and pull
requests are welcome on [GitHub](https://github.com/Aksoyhlc/dart_notify).

## Development checks

Run these before opening a pull request; CI runs the same commands:

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
```

Tests use injected HTTP clients (`MockClient`) and a local loopback SMTP peer.
They never need credentials and never contact a live service. New provider
behavior needs a test in `test/providers/<name>/`.

## Project layout

- Each implementation file contains at most one class.
- Core modules are grouped by responsibility: `notification/`, `provider/`,
  `routing/`, `delivery/` and `dispatch/`.
- A provider separates `config/`, `targets/`, `options/` and, when needed,
  `transport/`. Enums, typedefs and utilities live directly under the module
  root (`core/enums/`, `providers/<name>/enums/`), never inside feature folders.
- Only cross-module helpers live in `shared/`.
- Export new public types from `lib/dart_notify.dart`.

See [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) for the provider contract.

## Adding a provider

- Keep business errors in `ProviderResponse` with sanitized `<provider>_<code>`
  error codes; never copy credentials, tokens or raw response bodies into errors.
- Throw `NotifyDeliveryException` only for transport uncertainty.
- Set `supportsSafeRetry` to true only when the upstream API documents an
  idempotency key that the provider sends.
- Add a guide in `doc/providers/`, a row in the README provider table, an entry
  in `skills/dart-notify/references/providers.md` and a CHANGELOG entry.

## Security

Do not open a public issue for a vulnerability or a credential leak. Contact
the maintainer privately through the email address on the GitHub profile.
