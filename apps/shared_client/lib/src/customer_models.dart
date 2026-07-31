/// A customer who has chosen to make an account.
///
/// Optional throughout: the booking and ordering flows work with no account
/// at all, keyed by the reference on the device. This exists so a history
/// survives a lost phone and favourites follow the person rather than the
/// handset.
class CustomerAccount {
  const CustomerAccount({
    required this.id,
    required this.username,
    required this.name,
  });

  final int id;
  final String username;

  /// What to greet them by — their given name, or the username if they gave
  /// nothing else.
  final String name;

  /// Just the first word, for a greeting. "Bonsoir, Mariama Diallo" reads
  /// like a summons.
  String get firstName {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return username;
    return trimmed.split(' ').first;
  }

  factory CustomerAccount.fromJson(Map<String, dynamic> json) =>
      CustomerAccount(
        id: json['id'] as int,
        username: json['username'] as String? ?? '',
        name: json['name'] as String? ??
            json['first_name'] as String? ??
            json['username'] as String? ??
            '',
      );
}

/// A token and who it belongs to, as signup and sign-in both return.
class CustomerSession {
  const CustomerSession({required this.token, required this.customer});

  final String token;
  final CustomerAccount customer;

  factory CustomerSession.fromJson(Map<String, dynamic> json) =>
      CustomerSession(
        token: json['token'] as String,
        customer: CustomerAccount.fromJson(
          json['user'] as Map<String, dynamic>,
        ),
      );
}
