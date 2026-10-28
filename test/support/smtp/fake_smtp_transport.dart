import 'dart:async';

import 'package:dart_notify/dart_notify.dart';

final class FakeSmtpTransport implements SmtpTransport {
  FakeSmtpTransport({this.fail = false});
  final bool fail;
  int calls = 0;
  late EmailTarget seenTarget;
  late NotifyMessage seenMessage;
  EmailOptions? seenOptions;

  @override
  Future<void> send({
    required SmtpConfig config,
    required NotifyMessage message,
    required EmailTarget target,
    EmailOptions? options,
  }) async {
    calls++;
    seenTarget = target;
    seenMessage = message;
    seenOptions = options;
    if (fail) throw TimeoutException('connection lost');
  }
}
