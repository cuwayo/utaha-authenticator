import 'dart:typed_data';

/// Thrown when a Base32 string cannot be decoded.
///
/// The [message] is written to be shown directly to a user: it explains what is
/// wrong with the secret without using jargon like "base32" or "padding".
class Base32FormatException implements Exception {
  /// Creates an exception describing [message], optionally at [index].
  const new(this.message, {this.index});

  /// A calm, plain-language explanation suitable for display in the UI.
  final String message;

  /// Zero-based offset of the offending character, when known.
  final int? index;

  @override
  String toString() => index == null
      ? 'Base32FormatException: $message'
      : 'Base32FormatException: $message (at $index)';
}

/// RFC 4648 Base32 codec, as used by `otpauth://` secrets.
///
/// Decoding is deliberately forgiving about *presentation* and strict about
/// *content*:
///
/// * Case is ignored, and spaces, hyphens and `=` padding are stripped. Real
///   services print secrets in groups (`JBSW Y3DP EHPK 3PXP`), and users paste
///   them verbatim, so rejecting that formatting would be unhelpful.
/// * Any character outside the Base32 alphabet is rejected with a message
///   naming the character and its position, because silently dropping it would
///   produce a valid-looking but wrong secret — the worst possible failure mode
///   for a 2FA app.
abstract final class Base32 {
  /// The RFC 4648 alphabet, in value order.
  static const String alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static const int _bitsPerChar = 5;
  static const int _bitsPerByte = 8;

  static final Map<int, int> _decodeTable = <int, int>{
    for (var i = 0; i < alphabet.length; i++) alphabet.codeUnitAt(i): i,
  };

  /// Characters ignored wherever they appear in a secret.
  static bool _isSeparator(int codeUnit) =>
      codeUnit == 0x20 || // space
      codeUnit == 0x09 || // tab
      codeUnit == 0x0A || // newline
      codeUnit == 0x0D || // carriage return
      codeUnit == 0x2D || // hyphen
      codeUnit == 0x5F || // underscore
      codeUnit == 0x3D; // padding '='

  /// Returns the canonical form of [input]: uppercase, separators removed.
  ///
  /// This does not validate; use [decode] for that.
  static String normalize(String input) {
    final buffer = StringBuffer();
    for (final unit in input.codeUnits) {
      if (_isSeparator(unit)) continue;
      // Lowercase ASCII a-z -> uppercase. Uppercase already passes through.
      buffer.writeCharCode(unit >= 0x61 && unit <= 0x7A ? unit - 0x20 : unit);
    }
    return buffer.toString();
  }

  /// True when [input] decodes successfully.
  static bool isValid(String input) {
    try {
      final bytes = decode(input);
      bytes.fillRange(0, bytes.length, 0);
      return bytes.isNotEmpty;
    } on Base32FormatException {
      return false;
    }
  }

  /// Decodes [input] into raw bytes.
  ///
  /// Throws [Base32FormatException] with a user-facing message when the input
  /// contains a character outside the alphabet, or carries no data at all.
  static Uint8List decode(String input) {
    final cleaned = normalize(input);
    if (cleaned.isEmpty) {
      throw const Base32FormatException(
        'That secret is empty. Check the code and try again.',
      );
    }

    final output = Uint8List((cleaned.length * _bitsPerChar) ~/ _bitsPerByte);
    var outIndex = 0;
    var accumulator = 0;
    var bitsInAccumulator = 0;

    for (var i = 0; i < cleaned.length; i++) {
      final codeUnit = cleaned.codeUnitAt(i);
      final value = _decodeTable[codeUnit];
      if (value == null) {
        throw Base32FormatException(
          '“${String.fromCharCode(codeUnit)}” is not a valid character in a '
          'secret key. Secrets use the letters A–Z and the digits 2–7.',
          index: i,
        );
      }

      accumulator = (accumulator << _bitsPerChar) | value;
      bitsInAccumulator += _bitsPerChar;

      if (bitsInAccumulator >= _bitsPerByte) {
        bitsInAccumulator -= _bitsPerByte;
        output[outIndex++] = (accumulator >> bitsInAccumulator) & 0xFF;
      }
    }

    // Leftover bits that do not complete a byte are dropped. This matches the
    // lenient behaviour of Google Authenticator, which emits secrets whose bit
    // length is not always a multiple of 8.
    if (outIndex == 0) {
      throw const Base32FormatException(
        'That secret is too short to contain a key. Check the code and try '
        'again.',
      );
    }

    return Uint8List.sublistView(output, 0, outIndex);
  }

  /// Encodes [bytes] as Base32 without padding.
  ///
  /// Padding is omitted because `otpauth://` secrets conventionally omit it.
  static String encode(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final buffer = StringBuffer();
    var accumulator = 0;
    var bitsInAccumulator = 0;

    for (final byte in bytes) {
      accumulator = (accumulator << _bitsPerByte) | (byte & 0xFF);
      bitsInAccumulator += _bitsPerByte;
      while (bitsInAccumulator >= _bitsPerChar) {
        bitsInAccumulator -= _bitsPerChar;
        buffer.write(alphabet[(accumulator >> bitsInAccumulator) & 0x1F]);
      }
    }

    if (bitsInAccumulator > 0) {
      buffer.write(
        alphabet[(accumulator << (_bitsPerChar - bitsInAccumulator)) & 0x1F],
      );
    }

    return buffer.toString();
  }
}
