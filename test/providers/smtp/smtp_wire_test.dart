import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_notify/dart_notify.dart';
import 'package:test/test.dart';

import '../../support/smtp/smtp_fixture.dart';
import '../../support/smtp/utils/mime.dart';

void main() {
  test('mailer submits recipients, reply-to, HTML and binary attachments',
      () async {
    final fixture = await SmtpFixture.start();
    addTearDown(fixture.close);
    final provider = SmtpProvider(
      id: 'local-smtp',
      config: SmtpConfig(
        host: '127.0.0.1',
        port: fixture.port,
        security: SmtpSecurity.none,
        from: EmailAddress('from@example.com', name: 'Monitor'),
        timeout: const Duration(seconds: 3),
      ),
    );
    final result = await DartNotify(destinations: []).sendDirect(
      NotifyMessage(
        title: 'Report',
        body: 'Fallback',
        htmlBody: '<b>HTML</b>',
        attachments: [
          NotifyAttachment(
            fileName: 'report.bin',
            bytes: Uint8List.fromList([65, 66]),
          )
        ],
      ),
      provider: provider,
      target: EmailTarget(
        to: [EmailAddress('to@example.com')],
        cc: [EmailAddress('cc@example.com')],
        bcc: [EmailAddress('hidden@example.com')],
      ),
      options: EmailOptions(
        replyTo: [EmailAddress('reply@example.com')],
      ),
    );
    expect(result.status, DeliveryStatus.accepted);
    final mime = await fixture.message.timeout(const Duration(seconds: 5));
    expect(
        fixture.commands,
        containsAll([
          'MAIL FROM:<from@example.com>',
          'RCPT TO:<to@example.com>',
          'RCPT TO:<cc@example.com>',
          'RCPT TO:<hidden@example.com>',
        ]));
    expect(
        mime,
        contains(
            RegExp(r'reply-to:.*reply@example.com', caseSensitive: false)));
    expect(
        utf8.decode(readBase64MimePart(mime, 'text/plain')).trim(), 'Fallback');
    expect(utf8.decode(readBase64MimePart(mime, 'text/html')).trim(),
        '<b>HTML</b>');
    expect(mime, contains('report.bin'));
    expect(readBase64MimePart(mime, 'application/octet-stream'), [65, 66]);
    expect(mime, isNot(contains('hidden@example.com')));
    expect(fixture.errors, isEmpty);
  });

  test('default STARTTLS requirement prevents submission to a plaintext server',
      () async {
    final fixture = await SmtpFixture.start();
    addTearDown(fixture.close);
    final provider = SmtpProvider(
      id: 'secure-smtp',
      config: SmtpConfig(
        host: '127.0.0.1',
        port: fixture.port,
        from: EmailAddress('from@example.com'),
        timeout: const Duration(seconds: 3),
      ),
    );
    final result = await DartNotify(destinations: []).sendDirect(
      NotifyMessage(body: 'Alert'),
      provider: provider,
      target: EmailTarget(to: [EmailAddress('to@example.com')]),
    );
    expect(result.isFullyAccepted, isFalse);
    expect(result.attempts, 1);
    expect(
        fixture.commands.any((line) => line.startsWith('MAIL FROM:')), isFalse);
  });
}
