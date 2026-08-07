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
    this.phone = '',
    this.email = '',
    this.canResetPassword = false,
  });

  final int id;
  final String username;

  /// What is on file, so the profile form shows it rather than an empty box
  /// that looks like nothing was ever saved.
  final String phone;
  final String email;

  /// False when the account has neither a phone nor an email, so a forgotten
  /// password would lock them out. The app warns while there is time to fix it.
  final bool canResetPassword;

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
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String? ?? '',
        canResetPassword: json['can_reset_password'] as bool? ?? false,
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

/// What came back from asking for a reset code.
///
/// [sentTo] is masked by the server — enough for the right person to
/// recognise, not enough for anyone else to use. It is null when no account
/// matched, because the answer is deliberately the same either way.
class PasswordResetRequest {
  const PasswordResetRequest({
    required this.detail,
    this.channel,
    this.sentTo,
  });

  final String detail;

  /// 'sms' or 'email', or null when nothing was actually sent.
  final String? channel;
  final String? sentTo;

  bool get wasSent => channel != null;

  factory PasswordResetRequest.fromJson(Map<String, dynamic> json) =>
      PasswordResetRequest(
        detail: json['detail'] as String? ?? '',
        channel: json['channel'] as String?,
        sentTo: json['sent_to'] as String?,
      );
}
/// One dish in the cross-venue feed, carrying the venue it came from.
///
/// Not a [MenuItem]: that model belongs to a venue already on screen and has
/// no need to name it. This one is read the other way round — the dish is
/// what caught the eye and the venue is the answer to "where do I get it".
class FeaturedItem {
  const FeaturedItem({
    required this.id,
    required this.name,
    required this.price,
    required this.establishmentId,
    required this.establishmentName,
    this.description = '',
    this.imageUrl,
    this.city = '',
  });

  final int id;
  final String name;
  final String description;

  /// A string, not a number: it is set in the mono face and shown exactly as
  /// the server sent it, like every other price in these apps.
  final String price;
  final String? imageUrl;

  final int establishmentId;
  final String establishmentName;
  final String city;

  factory FeaturedItem.fromJson(Map<String, dynamic> json) => FeaturedItem(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        price: json['price'] as String? ?? '',
        imageUrl: json['image'] as String?,
        establishmentId: json['establishment'] as int,
        establishmentName: json['establishment_name'] as String? ?? '',
        city: json['city'] as String? ?? '',
      );
}
