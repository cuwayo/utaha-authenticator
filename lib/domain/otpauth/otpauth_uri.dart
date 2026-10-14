import 'dart:typed_data';

import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/core/utils/base32.dart';
import 'package:utaha_authenticator/domain/otp/otp.dart';
import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';
import 'package:utaha_authenticator/domain/otp/otp_type.dart';

/// The result of parsing an `otpauth://` provisioning URI.
///
/// The secret is returned as raw bytes rather than a string so the caller can
/// store it and then wipe it with `zero()`. The caller owns [secret] and is
/// responsible for zeroing it.
class ParsedOtpAuth {
  /// Creates a parsed provisioning URI.
  new({
    required this.secret,
    required this.accountName,
    this.issuer,
    this.type = OtpType.totp,
    this.algorithm = OtpAlgorithm.sha1,
    this.digits = kDefaultDigits,
    this.period = kDefaultPeriod,
    this.counter,
  });

  /// Raw secret key bytes. The caller must zero these when finished.
  final Uint8List secret;

  /// The user's account name for the service.
  final String accountName;

  /// The service name, when the URI supplied one.
  final String? issuer;

  /// Time-based or counter-based.
  final OtpType type;

  /// HMAC hash function.
  final OtpAlgorithm algorithm;

  /// Number of digits in a generated code.
  final int digits;

  /// TOTP time step in seconds.
  final int period;

  /// HOTP counter, present only for [OtpType.hotp].
  final int? counter;

  /// Never prints the secret.
  @override
  String toString() =>
      'ParsedOtpAuth(issuer: $issuer, accountName: $accountName, '
      'type: ${type.name}, algorithm: ${algorithm.name}, digits: $digits, '
      'period: $period, counter: $counter)';
}

/// Parses and writes `otpauth://` provisioning URIs.
///
/// The format is the de-facto standard introduced by Google Authenticator and
/// now implemented by every authenticator app:
///
/// ```text
/// otpauth://TYPE/LABEL?PARAMETERS
/// ```
///
/// Parsing is deliberately forgiving about the things that vary between issuers
/// (parameter case, `SHA-1` versus `SHA1`, `%3A` versus a literal colon) and
/// strict about the things that would produce a wrong code (a malformed secret,
/// an unsupported digit count, a missing HOTP counter).
abstract final class OtpAuthUri {
  /// Parses [uri] into its component parts.
  ///
  /// Throws [InvalidOtpAuthUriFailure] with a user-facing message when the URI
  /// cannot be used.
  static ParsedOtpAuth parse(String uri) {
    final Uri parsed;
    try {
      parsed = Uri.parse(uri.trim());
    } on FormatException catch (error) {
      throw InvalidOtpAuthUriFailure(
        'That QR code could not be read. It may be damaged.',
        cause: error,
      );
    }

    if (parsed.scheme.toLowerCase() != 'otpauth') {
      throw const InvalidOtpAuthUriFailure(
        'That is not an authenticator code. Look for a QR code that starts '
        'with "otpauth://".',
      );
    }

    final type = _parseType(parsed.host);
    final parameters = _lowercasedParameters(parsed);

    final secret = _parseSecret(parameters['secret']);
    final digits = _parseDigits(parameters['digits']);
    final period = _parsePeriod(parameters['period']);
    final algorithm = _parseAlgorithm(parameters['algorithm']);
    final counter = _parseCounter(parameters['counter'], type);

    // The label carries the account name, optionally prefixed with the issuer.
    final label = _decodeLabel(parsed.path);

    // The `issuer` parameter is authoritative when present; the label prefix is
    // a fallback for the many generators that omit the parameter.
    final issuerParameter = _blankToNull(parameters['issuer']);

    final String? issuer;
    final String accountName;

    if (issuerParameter != null) {
      issuer = issuerParameter;
      // Strip the issuer prefix from the label rather than trusting the
      // split-on-first-colon result. When the issuer itself contains a colon,
      // the split would otherwise consume part of the issuer and leave the
      // remainder glued to the front of the account name.
      final prefix = '$issuerParameter:';
      if (label.startsWith(prefix)) {
        accountName = label.substring(prefix.length).trim();
      } else if (label == issuerParameter) {
        // The label was just the issuer, e.g. "otpauth://totp/Acme?issuer=Acme".
        accountName = '';
      } else {
        // No usable prefix — the label is the account name on its own.
        accountName = _splitLabel(label).accountName;
      }
    } else {
      final split = _splitLabel(label);
      issuer = split.issuer;
      accountName = split.accountName;
    }

    if (accountName.isEmpty && issuer == null) {
      // Without either, the account would show up as an unnamed row the user
      // cannot identify. Reject it rather than creating something useless.
      throw const InvalidOtpAuthUriFailure(
        'That QR code does not include an account name, so it cannot be added.',
      );
    }

    return ParsedOtpAuth(
      secret: secret,
      accountName: accountName.isEmpty ? issuer! : accountName,
      issuer: issuer,
      type: type,
      algorithm: algorithm,
      digits: digits,
      period: period,
      counter: counter,
    );
  }

  /// Builds an `otpauth://` URI for the given parameters.
  ///
  /// [secret] is the raw key; it is Base32-encoded for the URI. Used when
  /// exporting plain-text lists, where the caller has already warned the user
  /// that the output is unencrypted.
  static String build({
    required Uint8List secret,
    required String accountName,
    String? issuer,
    OtpType type = OtpType.totp,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
    int digits = kDefaultDigits,
    int period = kDefaultPeriod,
    int? counter,
  }) {
    if (secret.isEmpty) {
      throw const InvalidOtpAuthUriFailure(
        'An account cannot be exported without its secret key.',
      );
    }

    // The label is "issuer:account" when an issuer is known, with each part
    // encoded separately so a colon inside either part cannot be mistaken for
    // the separator.
    final label = issuer == null || issuer.isEmpty
        ? Uri.encodeComponent(accountName)
        : '${Uri.encodeComponent(issuer)}:${Uri.encodeComponent(accountName)}';

    final query = <String, String>{
      'secret': Base32.encode(secret),
      if (issuer != null && issuer.isNotEmpty) 'issuer': issuer,
      'algorithm': algorithm.uriName,
      'digits': '$digits',
      if (type == OtpType.totp) 'period': '$period',
      if (type == OtpType.hotp) 'counter': '${counter ?? 0}',
    };

    return Uri(
      scheme: 'otpauth',
      host: type.name,
      path: '/$label',
      queryParameters: query,
    ).toString();
  }

  /// A human-readable name for the type, used in error messages.
  static OtpType _parseType(String host) {
    return switch (host.toLowerCase()) {
      'totp' => OtpType.totp,
      'hotp' => OtpType.hotp,
      '' => throw const InvalidOtpAuthUriFailure(
        'That QR code does not say whether it is a time-based or a '
        'counter-based code.',
      ),
      _ => throw InvalidOtpAuthUriFailure(
        'That QR code uses a kind of code this app does not support '
        '("$host").',
      ),
    };
  }

  /// Reads query parameters case-insensitively.
  ///
  /// The specification lower-cases parameter names, but generators in the wild
  /// emit `Secret`, `Digits` and so on.
  static Map<String, String> _lowercasedParameters(Uri uri) {
    final result = <String, String>{};
    for (final entry in uri.queryParameters.entries) {
      result[entry.key.toLowerCase()] = entry.value;
    }
    return result;
  }

  static Uint8List _parseSecret(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      throw const InvalidOtpAuthUriFailure(
        'That QR code is missing its secret key, so it cannot be added.',
      );
    }
    try {
      final decoded = Base32.decode(raw);
      if (decoded.isEmpty) {
        throw const InvalidOtpAuthUriFailure(
          'That QR code contains an empty secret key.',
        );
      }
      return decoded;
    } on Base32FormatException catch (error) {
      // Surface the specific reason — which character, and where — rather than a
      // generic "invalid secret".
      throw InvalidOtpAuthUriFailure(
        'The secret key in that QR code is not valid. ${error.message}',
        cause: error,
      );
    }
  }

  static int _parseDigits(String? raw) {
    if (raw == null || raw.trim().isEmpty) return kDefaultDigits;
    final value = int.tryParse(raw.trim());
    if (value == null || !kSupportedDigits.contains(value)) {
      throw InvalidOtpAuthUriFailure(
        'That QR code asks for $raw digits, but this app supports 6, 7 or 8.',
      );
    }
    return value;
  }

  static int _parsePeriod(String? raw) {
    if (raw == null || raw.trim().isEmpty) return kDefaultPeriod;
    final value = int.tryParse(raw.trim());
    if (value == null || value <= 0) {
      throw InvalidOtpAuthUriFailure(
        'That QR code asks for a code interval of "$raw", which is not a '
        'valid number of seconds.',
      );
    }
    return value;
  }

  static OtpAlgorithm _parseAlgorithm(String? raw) {
    if (raw == null || raw.trim().isEmpty) return OtpAlgorithm.sha1;
    final parsed = OtpAlgorithm.tryParse(raw);
    if (parsed == null) {
      throw InvalidOtpAuthUriFailure(
        'That QR code uses an unsupported algorithm ("$raw"). This app '
        'supports SHA1, SHA256 and SHA512.',
      );
    }
    return parsed;
  }

  static int? _parseCounter(String? raw, OtpType type) {
    if (type != OtpType.hotp) return null;
    if (raw == null || raw.trim().isEmpty) {
      // HOTP without a counter cannot produce a deterministic first code, so
      // defaulting silently would risk generating a code the server rejects.
      throw const InvalidOtpAuthUriFailure(
        'That counter-based code is missing its counter value, so it cannot '
        'be added.',
      );
    }
    final value = int.tryParse(raw.trim());
    if (value == null || value < 0) {
      throw InvalidOtpAuthUriFailure(
        'That QR code has an invalid counter value ("$raw").',
      );
    }
    return value;
  }

  /// Decodes the label portion of the path, stripping the leading slash.
  static String _decodeLabel(String path) {
    final raw = path.startsWith('/') ? path.substring(1) : path;
    if (raw.isEmpty) return '';
    // Percent-decoding throws a FormatException on malformed input; fall back to
    // the raw text rather than rejecting the whole URI over a cosmetic issue.
    try {
      return Uri.decodeComponent(raw);
    } on FormatException {
      return raw;
    }
  }

  /// Splits a decoded label into an optional issuer prefix and the account name.
  ///
  /// The separator is the first colon. Note the trade-off: because the label is
  /// decoded before splitting, an account name that itself contains an encoded
  /// colon is read as an issuer prefix. That is the same behaviour as the other
  /// mainstream authenticators, and it is the reading that makes the far more
  /// common `issuer:account` form work whether the colon arrived literal or
  /// percent-encoded.
  static ({String? issuer, String accountName}) _splitLabel(String label) {
    final separator = label.indexOf(':');
    if (separator < 0) {
      return (issuer: null, accountName: label.trim());
    }
    final issuer = label.substring(0, separator).trim();
    final accountName = label.substring(separator + 1).trim();
    return (issuer: issuer.isEmpty ? null : issuer, accountName: accountName);
  }

  static String? _blankToNull(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
