import 'dart:typed_data';

import 'package:dart_notify/dart_notify.dart';
import 'package:test/test.dart';

import '../../support/smtp/fake_smtp_transport.dart';

void main() {
  final config = SmtpConfig(
    host: 'smtp.example.com',
    from: EmailAddress('sender@example.com'),
    username: 'user',
    password: 'password',
  );

  test('email can use cc/bcc/reply-to and binary attachments', () async {
    final fake = FakeSmtpTransport();
    final smtp = SmtpProvider(id: 'smtp', config: config, transport: fake);
    final result = await DartNotify(destinations: [
      ProviderDestination(
        id: 'email',
        provider: smtp,
        target: EmailTarget(
          to: [EmailAddress('to@example.com')],
          cc: [EmailAddress('cc@example.com')],
          bcc: [EmailAddress('bcc@example.com')],
        ),
        options: EmailOptions(
          replyTo: [EmailAddress('reply@example.com')],
        ),
      ),
    ]).send(
        NotifyMessage(
          body: 'Fallback',
          htmlBody: '<b>HTML</b>',
          attachments: [
            NotifyAttachment(
              fileName: 'report.txt',
              bytes: Uint8List.fromList([65, 66]),
              contentType: 'text/plain',
            )
          ],
        ),
        to: ['email']);
    expect(result.isFullyAccepted, isTrue);
    expect(fake.calls, 1);
    expect(fake.seenMessage.attachments.single.bytes, [65, 66]);
    expect(fake.seenMessage.htmlBody, '<b>HTML</b>');
  });

  test('SMTP timeout is unknown and is NOT automatically retried', () async {
    final fake = FakeSmtpTransport(fail: true);
    final smtp = SmtpProvider(id: 'smtp', config: config, transport: fake);
    final report = await DartNotify(destinations: [
      ProviderDestination(
          id: 'email',
          provider: smtp,
          target: EmailTarget(to: [EmailAddress('receiver@example.com')])),
    ]).send(NotifyMessage(body: 'hello'), to: ['email']);
    expect(report.results.single.status, DeliveryStatus.unknown);
    expect(fake.calls, 1);
  });

  test('TLS default and invalid credentials rejected', () {
    expect(config.security, SmtpSecurity.startTlsRequired);
    expect(
        () => SmtpConfig(
              host: 'smtp.example.com',
              from: EmailAddress('sender@example.com'),
              username: 'user',
            ),
        throwsArgumentError);
  });
}
