import 'dart:io';

String readEnv(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('Missing environment variable: $name');
  }
  return value;
}
