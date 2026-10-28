import 'dart:io';

import 'package:dart_notify/dart_notify.dart';

import 'utils/read_env.dart';

/// Set VERIMOR_USERNAME, VERIMOR_PASSWORD, VERIMOR_SOURCE and VERIMOR_RECIPIENT.
/// Running this example sends a real SMS.
Future<void> main() async {
  final sms = VerimorProvider(
    id: 'verimor',
    config: VerimorConfig(
      username: readEnv('VERIMOR_USERNAME'),
      password: readEnv('VERIMOR_PASSWORD'),
      sourceAddr: readEnv('VERIMOR_SOURCE'),
    ),
  );
  try {
    final result = await DartNotify(destinations: []).sendDirect(
      NotifyMessage(body: 'dart_notify SMS bağlantısı hazır.'),
      provider: sms,
      target: VerimorTarget(numbers: [readEnv('VERIMOR_RECIPIENT')]),
      options: VerimorOptions(
        datacoding: VerimorDatacoding.gsmTurkish,
        customId: 'dart-notify-example',
      ),
    );
    stdout.writeln(
        '${result.status.name}: campaign=${result.messageId}, code=${result.error?.code}');
    if (!result.isFullyAccepted) exitCode = 1;
  } finally {
    sms.close();
  }
}
