import 'dart:io';

import 'package:dart_notify/dart_notify.dart';

import 'utils/read_env.dart';

/// Before running, set: ONESIGNAL_APP_ID, ONESIGNAL_API_KEY, SMTP_HOST,
/// SMTP_USERNAME, SMTP_PASSWORD, FROM_EMAIL, TO_EMAIL, ONESIGNAL_EXTERNAL_ID.
Future<void> main() async {
  final push = OneSignalProvider(
    id: 'onesignal',
    config: OneSignalConfig(
      appId: readEnv('ONESIGNAL_APP_ID'),
      apiKey: readEnv('ONESIGNAL_API_KEY'),
    ),
  );
  final smtp = SmtpProvider(
    id: 'smtp',
    config: SmtpConfig(
      host: readEnv('SMTP_HOST'),
      username: readEnv('SMTP_USERNAME'),
      password: readEnv('SMTP_PASSWORD'),
      from: EmailAddress(readEnv('FROM_EMAIL'), name: 'Monitoring'),
    ),
  );

  try {
    final notify = DartNotify(
      destinations: [
        ProviderDestination(
          id: 'it-push',
          provider: push,
          target: OneSignalTarget.externalIds([
            readEnv('ONESIGNAL_EXTERNAL_ID'),
          ]),
        ),
        ProviderDestination(
          id: 'it-email',
          provider: smtp,
          target: EmailTarget(to: [EmailAddress(readEnv('TO_EMAIL'))]),
        ),
      ],
      groups: {
        'it': ['it-push', 'it-email']
      },
    );

    final report = await notify.send(
      NotifyMessage(
        title: 'Monitoring Alert',
        body: 'RFID Gateway is offline.',
        priority: NotifyPriority.high,
        data: {'deviceId': 'FX9600-01'},
      ),
      groups: ['it'],
    );

    for (final result in report.results) {
      stdout.writeln(
        '${result.destinationId}: ${result.status.name} '
        '(attempts=${result.attempts}, code=${result.error?.code})',
      );
    }
    if (!report.isFullyAccepted) exitCode = 1;
  } finally {
    push.close();
  }
}
