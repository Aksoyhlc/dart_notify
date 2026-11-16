# Twilio SMS

Create a Twilio API key and use the Account SID for the account that owns the
sender. Configure a Twilio number, short code or alphanumeric sender in
`from`, a Messaging Service in `messagingServiceSid`, or both to choose a
specific sender from the service's pool.

```dart
final twilio = TwilioProvider(
  id: 'twilio-sms',
  config: TwilioConfig(
    accountSid: Platform.environment['TWILIO_ACCOUNT_SID']!,
    apiKeySid: Platform.environment['TWILIO_API_KEY_SID']!,
    apiKeySecret: Platform.environment['TWILIO_API_KEY_SECRET']!,
    messagingServiceSid: Platform.environment['TWILIO_MESSAGING_SERVICE_SID']!,
  ),
);

final result = await notify.sendDirect(
  NotifyMessage(body: 'Your order is ready for pickup.'),
  provider: twilio,
  target: TwilioTarget(number: '+14155550123'),
  options: TwilioOptions(
    statusCallback: Uri.parse('https://app.example.com/twilio/status'),
  ),
);
```

`TwilioConfig.withAuthToken` supports Account SID and Auth Token credentials.
One request sends to one E.164 number. Text comes from `body` and is limited
to 1600 characters. Twilio can apply additional encoding and segment limits.
This adapter sends SMS through the global Twilio API.

The initial `queued` or `accepted` status yields the Message SID as
`messageId`. Twilio sends later status updates to your callback if configured.
Your application hosts the callback and validates Twilio's signature.
Common errors include `twilio_invalid_sender`, `twilio_invalid_recipient`,
`twilio_recipient_opted_out` and `twilio_rate_limited`. The provider makes one
attempt per delivery. Call `twilio.close()` when finished.

[Message resource](https://www.twilio.com/docs/messaging/api/message-resource) ·
[Authentication](https://www.twilio.com/docs/usage/requests-to-twilio) ·
[Status callbacks](https://www.twilio.com/docs/messaging/guides/outbound-message-status-in-status-callbacks)
