import 'dart:io';

import 'package:dart_notify/dart_notify.dart';

import 'utils/read_env.dart';

/// Set RESEND_API_KEY, RESEND_FROM and RESEND_TO.
/// Running this example sends a real email.
Future<void> main() async {
  final from = readEnv('RESEND_FROM');
  final resend = ResendProvider(
    id: 'resend',
    config: ResendConfig(
      apiKey: readEnv('RESEND_API_KEY'),
      from: EmailAddress(from, name: 'dart_notify'),
    ),
  );
  try {
    final result = await DartNotify(destinations: []).sendDirect(
      NotifyMessage(
        title: 'dart_notify',
        body: 'Resend bağlantısı hazır.',
        htmlBody: '<p>Resend bağlantısı <b>hazır</b>.</p>',
      ),
      provider: resend,
      target: EmailTarget(to: [EmailAddress(readEnv('RESEND_TO'))]),
      options: EmailOptions(replyTo: [EmailAddress(from)]),
    );
    stdout.writeln(
        '${result.status.name}: id=${result.messageId}, code=${result.error?.code}');
    if (!result.isFullyAccepted) exitCode = 1;
  } finally {
    resend.close();
  }
}
