enum ExpoPriority {
  defaultPriority('default'),
  normal('normal'),
  high('high');

  const ExpoPriority(this.wireValue);

  final String wireValue;
}
