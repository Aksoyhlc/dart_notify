enum NtfyPriority {
  min(1),
  low(2),
  defaultPriority(3),
  high(4),
  urgent(5);

  const NtfyPriority(this.value);

  final int value;
}
