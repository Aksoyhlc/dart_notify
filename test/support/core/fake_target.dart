import 'package:dart_notify/dart_notify.dart';

final class FakeTarget implements NotificationTarget {
  const FakeTarget(this.value);
  final String value;
}
