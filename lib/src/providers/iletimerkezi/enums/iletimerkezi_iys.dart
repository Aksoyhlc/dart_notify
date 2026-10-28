enum IletimerkeziIys {
  transactional('0', null),
  commercialIndividual('1', 'BIREYSEL'),
  commercialBusiness('1', 'TACIR');

  const IletimerkeziIys(this.wireValue, this.recipientType);

  final String wireValue;
  final String? recipientType;
}
