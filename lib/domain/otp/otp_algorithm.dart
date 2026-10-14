// The crypto import is prefixed because this enum declares members named
// `sha1`, `sha256` and `sha512`, which would otherwise shadow the `Hash`
// constants of the same name that the package exports.
import 'package:crypto/crypto.dart' as crypto;

/// The HMAC hash function used to derive an OTP code.
///
/// RFC 6238 section 1.2 permits SHA-256 and SHA-512 in place of SHA-1, which is
/// what most services still use.
enum OtpAlgorithm {
  /// HMAC-SHA-1. The RFC 4226 default and the only algorithm Google
  /// Authenticator supports.
  sha1,

  /// HMAC-SHA-256.
  sha256,

  /// HMAC-SHA-512.
  sha512;

  /// The canonical name as it appears in an `otpauth://` URI.
  ///
  /// `otpauth://` uses the bare algorithm name without a hyphen, and the value
  /// is conventionally uppercase. Parsing is case-insensitive.
  String get uriName => switch (this) {
    OtpAlgorithm.sha1 => 'SHA1',
    OtpAlgorithm.sha256 => 'SHA256',
    OtpAlgorithm.sha512 => 'SHA512',
  };

  /// The HMAC hash implementation backing this algorithm.
  crypto.Hash get hash => switch (this) {
    OtpAlgorithm.sha1 => crypto.sha1,
    OtpAlgorithm.sha256 => crypto.sha256,
    OtpAlgorithm.sha512 => crypto.sha512,
  };

  /// Length in bytes of this algorithm's HMAC output.
  ///
  /// Not used by the truncation itself (which reads the offset from the last
  /// byte of whatever length the HMAC produces), but useful for tests and for
  /// asserting the digest really is the size we expect.
  int get macLength => switch (this) {
    OtpAlgorithm.sha1 => 20,
    OtpAlgorithm.sha256 => 32,
    OtpAlgorithm.sha512 => 64,
  };

  /// Parses an `otpauth://` algorithm name.
  ///
  /// Accepts `SHA1`, `sha1`, `SHA-1` and `SHA256`, because implementations in
  /// the wild are inconsistent about both case and hyphens. Returns null when
  /// the value is not recognised, so callers can decide whether to fall back to
  /// the default or reject the URI.
  static OtpAlgorithm? tryParse(String? value) {
    if (value == null) return null;
    // Normalise: strip separators and uppercase.
    final normalised = value.replaceAll(RegExp('[-_ ]'), '').toUpperCase();
    return switch (normalised) {
      'SHA1' => OtpAlgorithm.sha1,
      'SHA256' => OtpAlgorithm.sha256,
      'SHA512' => OtpAlgorithm.sha512,
      _ => null,
    };
  }

  /// Stable identifier used for persistence.
  String get id => name;

  /// Parses a persisted identifier, falling back to [OtpAlgorithm.sha1].
  static OtpAlgorithm fromId(String? id) => OtpAlgorithm.values.firstWhere(
    (value) => value.name == id,
    orElse: () => OtpAlgorithm.sha1,
  );
}
