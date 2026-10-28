import 'dart:io';

import 'package:dart_notify/dart_notify.dart';

import 'utils/read_env.dart';

/// Set NETGSM_USERNAME, NETGSM_PASSWORD, NETGSM_SENDER and NETGSM_RECIPIENT.
/// Running this example submits a real SMS.
Future<void> main() async {
  final sms = NetgsmProvider(
    id: 'netgsm',
    config: NetgsmConfig(
      username: readEnv('NETGSM_USERNAME'),
      password: readEnv('NETGSM_PASSWORD'),
      sender: readEnv('NETGSM_SENDER'),
      appName: 'dart_notify_example',
    ),
  );
  try {
    final result = await DartNotify(destinations: []).sendDirect(
      NotifyMessage(body: 'dart_notify SMS bağlantısı hazır.'),
      provider: sms,
      target: NetgsmTarget(numbers: [readEnv('NETGSM_RECIPIENT')]),
      options: NetgsmOptions(encoding: NetgsmEncoding.turkish),
    );
    stdout.writeln(
        '${result.status.name}: job=${result.messageId}, code=${result.error?.code}');
    if (!result.isFullyAccepted) exitCode = 1;
  } finally {
    sms.close();
  }
}
