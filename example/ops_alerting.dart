import 'dart:io';

import 'package:dart_notify/dart_notify.dart';

import 'utils/read_env.dart';

/// Set TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID and NTFY_TOPIC.
/// Running this example sends real notifications.
Future<void> main() async {
  final telegram = TelegramProvider(
    id: 'telegram',
    config: TelegramConfig(botToken: readEnv('TELEGRAM_BOT_TOKEN')),
  );
  final ntfy = NtfyProvider(id: 'ntfy');
  try {
    final notify = DartNotify(destinations: [
      ProviderDestination(
        id: 'ops-telegram',
        provider: telegram,
        target: TelegramTarget(chatId: readEnv('TELEGRAM_CHAT_ID')),
        options: TelegramOptions(parseMode: TelegramParseMode.html),
      ),
      ProviderDestination(
        id: 'ops-ntfy',
        provider: ntfy,
        target: NtfyTarget(topic: readEnv('NTFY_TOPIC')),
        options: NtfyOptions(priority: NtfyPriority.high, tags: ['robot']),
      ),
    ]);
    final report = await notify.send(
      NotifyMessage(
          title: 'dart_notify', body: 'Ops alerting bağlantısı hazır.'),
      groups: const [],
      to: const ['ops-telegram', 'ops-ntfy'],
    );
    for (final result in report.results) {
      stdout.writeln(
          '${result.destinationId}: ${result.status.name} ${result.error?.code ?? ''}');
    }
    if (!report.isFullyAccepted) exitCode = 1;
  } finally {
    telegram.close();
    ntfy.close();
  }
}
