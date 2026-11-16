enum PushoverPriority {
  lowest(-2),
  low(-1),
  normal(0),
  high(1),
  emergency(2);

  const PushoverPriority(this.value);

  final int value;
}
