/// Which one-time-password scheme an account uses.
///
/// The two differ only in what drives the HMAC counter: TOTP derives it from
/// the clock, HOTP from a stored counter the user advances by hand.
enum OtpType {
  /// Time-based, RFC 6238. The common case.
  totp,

  /// Counter-based, RFC 4226.
  hotp;

  /// Stable identifier used for persistence.
  String get id => name;

  /// Parses a persisted identifier, falling back to [OtpType.totp].
  static OtpType fromId(String? id) => OtpType.values.firstWhere(
    (value) => value.name == id,
    orElse: () => OtpType.totp,
  );
}
