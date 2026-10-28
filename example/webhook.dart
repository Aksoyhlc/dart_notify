import 'dart:io';

import 'package:dart_notify/dart_notify.dart';

import 'utils/read_env.dart';

/// Set WEBHOOK_URL and WEBHOOK_TOKEN. Running sends a real HTTP notification.
Future<void> main() async {
  final webhook = WebhookProvider(
    id: 'webhook',
    config: WebhookConfig(
      headers: {'Authorization': 'Bearer ${readEnv('WEBHOOK_TOKEN')}'},
      payloadBuilder: (message) =>
          {'event': 'system.alert', 'text': message.body},
    ),
  );
  try {
    final result = await DartNotify(destinations: []).sendDirect(
      NotifyMessage(body: 'Webhook bağlantısı hazır.'),
      provider: webhook,
      target: WebhookTarget(Uri.parse(readEnv('WEBHOOK_URL'))),
    );
    stdout.writeln('${result.status.name}: ${result.error?.code}');
    if (!result.isFullyAccepted) exitCode = 1;
  } finally {
    webhook.close();
  }
}
