import 'dart:async';
import 'dart:collection';

/// Caps concurrent work at [limit] and queues the rest in FIFO order.
final class DeliveryLimiter {
  DeliveryLimiter(this.limit);

  final int limit;
  final _waiting = Queue<Completer<void>>();
  var _active = 0;

  Future<T> run<T>(Future<T> Function() deliver) async {
    if (_active < limit) {
      _active++;
    } else {
      final admitted = Completer<void>();
      _waiting.addLast(admitted);
      await admitted.future;
    }
    try {
      return await deliver();
    } finally {
      if (_waiting.isEmpty) {
        _active--;
      } else {
        // Hand the occupied slot directly to the oldest waiting delivery.
        _waiting.removeFirst().complete();
      }
    }
  }
}
