/// HMAC-based and time-based one-time password generation.
///
/// Implemented directly from RFC 4226 (HOTP) and RFC 6238 (TOTP) rather than
/// pulled from a package, so the behaviour is auditable and is proven against
/// the published test vectors in `test/domain/otp/`.
///
/// Everything here is a pure function over byte arrays: no Flutter, no I/O, no
/// clock access except where a timestamp is passed in explicitly. That makes the
/// whole module deterministic and unit-testable.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';

/// Digit counts permitted by the `otpauth://` convention.
///
/// RFC 4226 fixes six digits, but the wider ecosystem (and RFC 6238's own test
/// vectors) uses seven and eight as well.
const Set<int> kSupportedDigits = <int>{6, 7, 8};

/// Default number of digits when a URI does not specify any.
const int kDefaultDigits = 6;

/// Default TOTP time step in seconds, per RFC 6238 section 5.2.
const int kDefaultPeriod = 30;

/// Powers of ten used for truncation, indexed by digit count.
///
/// Precomputed so code generation does no arithmetic beyond a modulo.
const List<int> _powersOfTen = <int>[
  1,
  10,
  100,
  1000,
  10000,
  100000,
  1000000,
  10000000,
  100000000,
];

/// Thrown when an OTP cannot be generated from the supplied parameters.
///
/// The message is written for a person, matching the rest of the app's failures.
class OtpException implements Exception {
  /// Creates an exception with a user-facing [message].
  const new(this.message);

  /// A calm, plain-language explanation suitable for display.
  final String message;

  @override
  String toString() => 'OtpException: $message';
}

/// Computes the HOTP value for [counter] under [secret] (RFC 4226 section 5.3).
///
/// [secret] is the raw shared key — not the Base32 text. Decode it with
/// `Base32.decode` first.
///
/// Throws [OtpException] if the secret is empty or the digit count is not one of
/// [kSupportedDigits].
String hotp(
  Uint8List secret,
  int counter, {
  OtpAlgorithm algorithm = OtpAlgorithm.sha1,
  int digits = kDefaultDigits,
}) {
  if (secret.isEmpty) {
    throw const OtpException(
      'That account has no secret key, so a code cannot be generated.',
    );
  }
  if (!kSupportedDigits.contains(digits)) {
    throw OtpException(
      'A code can have 6, 7 or 8 digits, but this account is set to $digits.',
    );
  }
  if (counter < 0) {
    throw const OtpException('That account has an invalid counter value.');
  }

  final mac = _hmac(secret, algorithm, counter);
  final binary = _dynamicTruncate(mac);
  return _format(binary % _powersOfTen[digits], digits);
}

/// Computes the TOTP value for [time] under [secret] (RFC 6238 section 4.2).
///
/// [time] is passed in rather than read from the clock so the function stays
/// pure and testable against the RFC's fixed timestamps.
String totp(
  Uint8List secret,
  DateTime time, {
  OtpAlgorithm algorithm = OtpAlgorithm.sha1,
  int digits = kDefaultDigits,
  int period = kDefaultPeriod,
}) {
  if (period <= 0) {
    throw const OtpException(
      'The code interval must be a positive number of seconds.',
    );
  }
  return hotp(
    secret,
    totpCounter(time, period),
    algorithm: algorithm,
    digits: digits,
  );
}

/// Returns the HOTP counter corresponding to [time] for [period] seconds.
///
/// This is `floor(unixSeconds / period)`, the time-step number `T` from
/// RFC 6238. Exposed because the UI needs it to know when the code changes.
int totpCounter(DateTime time, [int period = kDefaultPeriod]) {
  if (period <= 0) {
    throw const OtpException(
      'The code interval must be a positive number of seconds.',
    );
  }
  final seconds = time.toUtc().millisecondsSinceEpoch ~/ 1000;
  // `~/` truncates toward zero; for pre-1970 timestamps that would round the
  // wrong way, so floor explicitly for negative values.
  return seconds >= 0 ? seconds ~/ period : ((seconds - period + 1) ~/ period);
}

/// Whole seconds remaining before the code for [time] expires.
///
/// Returns [period] exactly at a step boundary and approaches 0 just before the
/// next one. Never returns a value outside `1..period` for a positive period.
int totpSecondsRemaining(DateTime time, [int period = kDefaultPeriod]) {
  if (period <= 0) {
    throw const OtpException(
      'The code interval must be a positive number of seconds.',
    );
  }
  final seconds = time.toUtc().millisecondsSinceEpoch / 1000;
  final elapsed = seconds - (totpCounter(time, period) * period);
  final remaining = period - elapsed;
  // Clamp so sub-second jitter can never surface as 0 or period + 1.
  return remaining.ceil().clamp(1, period);
}

/// Fraction of the current period already elapsed, in `0.0..1.0`.
///
/// Drives the countdown indicator. 0.0 at the start of a step, approaching 1.0
/// just before it rolls over.
double totpProgress(DateTime time, [int period = kDefaultPeriod]) {
  if (period <= 0) {
    throw const OtpException(
      'The code interval must be a positive number of seconds.',
    );
  }
  final seconds = time.toUtc().millisecondsSinceEpoch / 1000;
  final elapsed = seconds - (totpCounter(time, period) * period);
  return (elapsed / period).clamp(0.0, 1.0);
}

/// Computes the raw HMAC digest for [counter].
Uint8List _hmac(Uint8List secret, OtpAlgorithm algorithm, int counter) {
  final message = _counterBytes(counter);
  final digest = Hmac(algorithm.hash, secret).convert(message);
  return Uint8List.fromList(digest.bytes);
}

/// Encodes [counter] as a big-endian 64-bit integer (RFC 4226 section 5.2).
///
/// Written by hand rather than with `ByteData.setUint64` because Dart's `int` is
/// a signed 64-bit value on native platforms, so the unsigned top half cannot be
/// represented; shifting byte by byte keeps the encoding correct for every value
/// a Dart `int` can hold.
Uint8List _counterBytes(int counter) {
  final bytes = Uint8List(8);
  var value = counter;
  for (var i = 7; i >= 0; i--) {
    bytes[i] = value & 0xFF;
    value = value >> 8;
  }
  return bytes;
}

/// Applies dynamic truncation (RFC 4226 section 5.4).
///
/// The low nibble of the final byte selects a four-byte window; the top bit of
/// that window is masked off so the result is always a positive 31-bit integer.
/// This works for any digest length, which is why SHA-256 and SHA-512 need no
/// special handling here.
int _dynamicTruncate(Uint8List mac) {
  final offset = mac[mac.length - 1] & 0x0F;
  return ((mac[offset] & 0x7F) << 24) |
      ((mac[offset + 1] & 0xFF) << 16) |
      ((mac[offset + 2] & 0xFF) << 8) |
      (mac[offset + 3] & 0xFF);
}

/// Left-pads [value] with zeroes to exactly [digits] characters.
///
/// Padding is essential: a code that truncates to 42 must display as `000042`,
/// and dropping the leading zeroes would produce a wrong — but plausible-looking
/// — code.
String _format(int value, int digits) => value.toString().padLeft(digits, '0');
