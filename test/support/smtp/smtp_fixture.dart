import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A local SMTP peer that captures actual envelopes and MIME output.
final class SmtpFixture {
  SmtpFixture._(this._server) {
    _server.listen((socket) => unawaited(_serve(socket)));
  }

  static Future<SmtpFixture> start() async =>
      SmtpFixture._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _server;
  final _sockets = <Socket>{};
  final _message = Completer<String>();
  final commands = <String>[];
  final errors = <Object>[];

  int get port => _server.port;
  Future<String> get message => _message.future;

  Future<void> _serve(Socket socket) async {
    _sockets.add(socket);
    socket.write('220 localhost ESMTP\r\n');
    var inData = false;
    final lines = <String>[];
    try {
      await for (final line in socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (inData) {
          if (line == '.') {
            inData = false;
            if (!_message.isCompleted) _message.complete(lines.join('\r\n'));
            socket.write('250 Queued\r\n');
          } else {
            lines.add(line.startsWith('..') ? line.substring(1) : line);
          }
          continue;
        }
        commands.add(line);
        if (line.startsWith('EHLO ')) {
          socket.write('250-localhost\r\n250 8BITMIME\r\n');
        } else if (line.startsWith('MAIL FROM:') ||
            line.startsWith('RCPT TO:')) {
          socket.write('250 OK\r\n');
        } else if (line == 'DATA') {
          inData = true;
          socket.write('354 End with a dot\r\n');
        } else if (line == 'QUIT') {
          socket.write('221 Bye\r\n');
          await socket.flush();
          break;
        } else {
          socket.write('500 Unsupported command\r\n');
        }
      }
    } catch (error) {
      errors.add(error);
    } finally {
      _sockets.remove(socket);
      socket.destroy();
    }
  }

  Future<void> close() async {
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    await _server.close();
  }
}
