void validateHttpsEndpoint(Uri endpoint) {
  if (endpoint.scheme != 'https' ||
      !endpoint.hasAuthority ||
      endpoint.host.isEmpty ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasFragment) {
    throw ArgumentError(
        'Endpoint must be an HTTPS URL without userinfo or fragments.');
  }
}
