/// Normalizes a Turkish mobile number to `90XXXXXXXXXX` (12 digits).
///
/// Accepts `5XXXXXXXXX`, `05XXXXXXXXX`, `905XXXXXXXXX` and `+905XXXXXXXXX`,
/// ignoring spaces, dashes and parentheses. Other country codes are rejected.
String normalizeTrPhoneNumber(String input) {
  final compact = input.replaceAll(RegExp(r'[\s\-()]'), '');
  String digits;
  if (compact.startsWith('+90')) {
    digits = compact.substring(3);
  } else if (compact.length == 12 && compact.startsWith('90')) {
    digits = compact.substring(2);
  } else if (compact.length == 11 && compact.startsWith('0')) {
    digits = compact.substring(1);
  } else {
    digits = compact;
  }
  if (digits.length != 10 ||
      !digits.startsWith('5') ||
      !RegExp(r'^[0-9]{10}$').hasMatch(digits)) {
    throw ArgumentError(
        'Turkish mobile numbers must look like 5XXXXXXXXX or +905XXXXXXXXX.');
  }
  return '90$digits';
}
