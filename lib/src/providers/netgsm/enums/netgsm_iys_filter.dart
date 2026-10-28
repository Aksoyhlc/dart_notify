enum NetgsmIysFilter {
  informational('0'),
  commercialIndividual('11'),
  commercialBusiness('12');

  const NetgsmIysFilter(this.value);
  final String value;
}
