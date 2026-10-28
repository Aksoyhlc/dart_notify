enum VerimorIysRecipientType {
  individual('BIREYSEL'),
  business('TACIR');

  const VerimorIysRecipientType(this.wireValue);

  final String wireValue;
}
