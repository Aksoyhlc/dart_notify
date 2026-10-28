String normalizeNetgsmNumber(String input) {
  final number = input.trim();
  final normalized =
      number.startsWith('+') ? '00${number.substring(1)}' : number;
  if (!RegExp(r'^[0-9]{10,17}$').hasMatch(normalized)) {
    throw ArgumentError(
        'Netgsm recipients must be domestic or international phone numbers.');
  }
  return normalized;
}
