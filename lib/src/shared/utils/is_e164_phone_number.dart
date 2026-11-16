final _e164 = RegExp(r'^\+[1-9][0-9]{1,14}$');

bool isE164PhoneNumber(String number) => _e164.hasMatch(number);
