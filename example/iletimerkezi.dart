import 'dart:io';

import 'package:dart_notify/dart_notify.dart';

import 'utils/read_env.dart';

/// Set ILETIMERKEZI_API_KEY, ILETIMERKEZI_API_HASH, ILETIMERKEZI_SENDER and
/// ILETIMERKEZI_RECIPIENT. Running this example sends a real SMS.
Future<void> main() async {
  final sms = IletimerkeziProvider(
    id: 'iletimerkezi',
    config: IletimerkeziConfig(
      key: readEnv('ILETIMERKEZI_API_KEY'),
      hash: readEnv('ILETIMERKEZI_API_HASH'),
      sender: readEnv('ILETIMERKEZI_SENDER'),
    ),
  );
  try {
    final result = await DartNotify(destinations: []).sendDirect(
      NotifyMessage(body: 'dart_notify SMS bağlantısı hazır.'),
      provider: sms,
      target: IletimerkeziTarget(numbers: [readEnv('ILETIMERKEZI_RECIPIENT')]),
      options: IletimerkeziOptions(iys: IletimerkeziIys.transactional),
    );
    stdout.writeln(
        '${result.status.name}: order=${result.messageId}, code=${result.error?.code}');
    if (!result.isFullyAccepted) exitCode = 1;
  } finally {
    sms.close();
  }
}
