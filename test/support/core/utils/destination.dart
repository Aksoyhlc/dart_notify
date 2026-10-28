import 'package:dart_notify/dart_notify.dart';

import '../fake_provider.dart';
import '../fake_target.dart';

ProviderDestination<FakeTarget, NoNotificationOptions> dest(
        String name, FakeProvider p) =>
    ProviderDestination(
        id: name, provider: p, target: const FakeTarget('user'));
