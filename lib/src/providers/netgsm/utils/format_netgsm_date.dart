/// Uses caller-supplied calendar fields as Netgsm-local wall time.
String formatNetgsmDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}${two(value.month)}${value.year.toString().padLeft(4, '0')}'
      '${two(value.hour)}${two(value.minute)}';
}
