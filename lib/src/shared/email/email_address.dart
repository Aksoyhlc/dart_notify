final class EmailAddress {
  EmailAddress(this.address, {this.name}) {
    if (address.trim().isEmpty ||
        address.contains('\n') ||
        address.contains('\r') ||
        !address.contains('@')) {
      throw ArgumentError.value(address, 'address', 'Invalid email address.');
    }
    if (name != null && (name!.contains('\n') || name!.contains('\r'))) {
      throw ArgumentError('Invalid display name.');
    }
  }

  final String address;
  final String? name;
}
