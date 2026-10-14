import 'dart:convert';
import 'dart:typed_data';

import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/core/utils/zeroing.dart';
import 'package:utaha_authenticator/domain/otp/otp.dart';
import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';
import 'package:utaha_authenticator/domain/otp/otp_type.dart';

/// One account recovered from a Google Authenticator export.
class MigratedAccount {
  /// Creates a migrated account.
  new({
    required this.secret,
    required this.name,
    this.issuer,
    this.algorithm = OtpAlgorithm.sha1,
    this.digits = kDefaultDigits,
    this.type = OtpType.totp,
    this.counter = 0,
  });

  /// Raw secret key bytes. The caller owns this buffer and must zero it.
  final Uint8List secret;

  /// The account name as exported.
  final String name;

  /// The service name, when the export carried one separately.
  final String? issuer;

  /// HMAC hash function.
  final OtpAlgorithm algorithm;

  /// Number of digits.
  final int digits;

  /// Time-based or counter-based.
  final OtpType type;

  /// HOTP counter.
  final int counter;

  /// Never prints the secret.
  @override
  String toString() =>
      'MigratedAccount(issuer: $issuer, name: $name, '
      'algorithm: ${algorithm.name}, digits: $digits, type: ${type.name})';
}

/// The result of parsing an export payload.
class MigrationPayload {
  /// Creates a parsed payload.
  new({
    required this.accounts,
    required this.skipped,
    this.batchSize = 1,
    this.batchIndex = 0,
    this.version = 1,
  });

  /// The accounts that could be read.
  final List<MigratedAccount> accounts;

  /// Entries that were present but unusable, with the reason.
  ///
  /// Reported rather than silently dropped: a user migrating away from Google
  /// Authenticator needs to know if any account did not come across, because
  /// the loss is otherwise invisible until that account is next needed.
  final List<MigrationSkip> skipped;

  /// How many QR codes the export was split across.
  final int batchSize;

  /// Which of those QR codes this payload is.
  final int batchIndex;

  /// Payload format version reported by the exporter.
  final int version;

  /// True when this payload is one of several, so the UI can ask for the rest.
  bool get isMultiPart => batchSize > 1;

  /// Zeroes every secret held by this payload.
  void dispose() {
    for (final account in accounts) {
      zero(account.secret);
    }
  }

  /// Never prints secrets.
  @override
  String toString() =>
      'MigrationPayload(accounts: ${accounts.length}, '
      'skipped: ${skipped.length}, batch: ${batchIndex + 1}/$batchSize)';
}

/// An entry that could not be imported, and why.
class MigrationSkip {
  /// Creates a skip record.
  const new({required this.name, required this.reason});

  /// The name of the entry, when one could be read.
  final String name;

  /// A plain-language reason, safe to show the user.
  final String reason;
}

/// Reads Google Authenticator's bulk-export payloads.
///
/// The payload is a protobuf `MigrationPayload` carried in the `data` query
/// parameter of an `otpauth-migration://offline` URI:
///
/// ```text
/// otpauth-migration://offline?data=<base64 protobuf>
/// ```
///
/// The protobuf is decoded by hand rather than with generated code. The schema
/// is five fields and two levels deep, and `protoc`'s Dart plugin is not
/// available in this project's toolchain; a small, well-tested reader is a
/// better trade than adding a code-generation step and a dependency for it.
/// The reader is tested against real `protoc`-generated wire bytes in
/// `test/fixtures/migration_vectors.yaml`.
abstract final class GoogleAuthMigration {
  /// The URI scheme and host Google Authenticator uses.
  static const String scheme = 'otpauth-migration';

  /// Field numbers from the reconstructed schema.
  static const int _fieldOtpParameters = 1;
  static const int _fieldVersion = 2;
  static const int _fieldBatchSize = 3;
  static const int _fieldBatchIndex = 4;

  /// Field numbers inside `OtpParameters`.
  static const int _fieldSecret = 1;
  static const int _fieldName = 2;
  static const int _fieldIssuer = 3;
  static const int _fieldAlgorithm = 4;
  static const int _fieldDigits = 5;
  static const int _fieldType = 6;
  static const int _fieldCounter = 7;

  /// Enum values, verified against three independent reconstructions.
  static const int _algorithmSha1 = 1;
  static const int _algorithmSha256 = 2;
  static const int _algorithmSha512 = 3;
  static const int _algorithmMd5 = 4;

  static const int _digitsSix = 1;
  static const int _digitsEight = 2;

  static const int _typeHotp = 1;
  static const int _typeTotp = 2;

  /// Parses [uri], which may be the full `otpauth-migration://` URI or just the
  /// bare base64 `data` value.
  ///
  /// Throws [MigrationParseFailure] with a user-facing message when the payload
  /// cannot be read at all. Individual unusable entries do not throw; they are
  /// reported through `MigrationPayload.skipped`.
  static MigrationPayload parse(String uri) {
    final data = _extractData(uri);

    final Uint8List bytes;
    try {
      bytes = Uint8List.fromList(base64.decode(_normaliseBase64(data)));
    } on FormatException catch (error) {
      throw MigrationParseFailure(
        'That export code could not be read. It may be incomplete or damaged.',
        cause: error,
      );
    }

    if (bytes.isEmpty) {
      throw const MigrationParseFailure(
        'That export code is empty. Try generating a new one from Google '
        'Authenticator.',
      );
    }

    try {
      return _decodePayload(bytes);
    } on MigrationParseFailure {
      rethrow;
    } on Object catch (error) {
      // A malformed protobuf can fail in many ways; the user gets one clear
      // message either way.
      throw MigrationParseFailure(
        'That export code could not be read. It may be incomplete or damaged.',
        cause: error,
      );
    } finally {
      // The raw payload contains every secret in the export.
      zero(bytes);
    }
  }

  /// Pulls the base64 payload out of a URI, or returns the input unchanged.
  static String _extractData(String input) {
    final trimmed = input.trim();
    if (!trimmed.contains('://')) {
      // Already a bare data value.
      return trimmed;
    }

    final Uri parsed;
    try {
      parsed = Uri.parse(trimmed);
    } on FormatException catch (error) {
      throw MigrationParseFailure(
        'That export code could not be read. It may be incomplete or damaged.',
        cause: error,
      );
    }

    if (parsed.scheme.toLowerCase() != scheme) {
      throw const MigrationParseFailure(
        'That is not a Google Authenticator export code. In Google '
        'Authenticator, choose Transfer accounts, then Export accounts.',
      );
    }

    final data = parsed.queryParameters['data'];
    if (data == null || data.trim().isEmpty) {
      throw const MigrationParseFailure(
        'That export code is missing its contents. Try generating a new one.',
      );
    }
    return data;
  }

  /// Makes base64 usable by `base64.decode`.
  ///
  /// Google Authenticator percent-encodes the value in the URI, and `Uri`
  /// decodes it for us, but a pasted value can still arrive with spaces or with
  /// `-`/`_` instead of `+`/`/`, and without padding.
  static String _normaliseBase64(String value) {
    final cleaned = value.replaceAll(RegExp(r'\s'), '');
    final standard = cleaned.replaceAll('-', '+').replaceAll('_', '/');
    final remainder = standard.length % 4;
    if (remainder == 0) return standard;
    // A remainder of 1 is not a valid base64 length; let the decoder report it.
    return standard + '=' * (4 - remainder);
  }

  static MigrationPayload _decodePayload(Uint8List bytes) {
    final accounts = <MigratedAccount>[];
    final skipped = <MigrationSkip>[];

    var version = 1;
    var batchSize = 1;
    var batchIndex = 0;

    final reader = _ProtoReader(bytes);
    while (reader.hasMore) {
      final tag = reader.readTag();
      switch (tag.fieldNumber) {
        case _fieldOtpParameters:
          if (tag.wireType != _wireLengthDelimited) {
            throw const MigrationParseFailure(
              'That export code could not be read. It may be incomplete or '
              'damaged.',
            );
          }
          final entry = reader.readLengthDelimitedView();
          _readOtpParameters(entry, accounts, skipped);

        case _fieldVersion:
          version = reader.readVarint();

        case _fieldBatchSize:
          batchSize = reader.readVarint();

        case _fieldBatchIndex:
          batchIndex = reader.readVarint();

        default:
          // Unknown fields are skipped rather than rejected, so a future
          // exporter adding a field does not break the import.
          reader.skipField(tag.wireType);
      }
    }

    return MigrationPayload(
      accounts: accounts,
      skipped: skipped,
      version: version,
      batchSize: batchSize < 1 ? 1 : batchSize,
      batchIndex: batchIndex < 0 ? 0 : batchIndex,
    );
  }

  static void _readOtpParameters(
    Uint8List bytes,
    List<MigratedAccount> accounts,
    List<MigrationSkip> skipped,
  ) {
    var secret = Uint8List(0);
    var name = '';
    var issuer = '';
    var algorithm = 0;
    var digits = 0;
    var type = 0;
    var counter = 0;

    final reader = _ProtoReader(bytes);
    while (reader.hasMore) {
      final tag = reader.readTag();
      switch (tag.fieldNumber) {
        case _fieldSecret:
          secret = reader.readLengthDelimited();
        case _fieldName:
          name = reader.readString();
        case _fieldIssuer:
          issuer = reader.readString();
        case _fieldAlgorithm:
          algorithm = reader.readVarint();
        case _fieldDigits:
          digits = reader.readVarint();
        case _fieldType:
          type = reader.readVarint();
        case _fieldCounter:
          counter = reader.readVarint();
        default:
          reader.skipField(tag.wireType);
      }
    }

    // The name is the only thing worth reporting for a skipped entry, so fall
    // back to whatever identifying text exists.
    final label = name.isNotEmpty ? name : (issuer.isNotEmpty ? issuer : '?');

    if (secret.isEmpty) {
      // Importing this would create an account that can never produce a code.
      skipped.add(
        MigrationSkip(
          name: label,
          reason: 'It has no secret key, so it cannot generate codes.',
        ),
      );
      return;
    }

    final resolvedType = switch (type) {
      _typeTotp => OtpType.totp,
      _typeHotp => OtpType.hotp,
      _ => null,
    };
    if (resolvedType == null) {
      zero(secret);
      skipped.add(
        MigrationSkip(
          name: label,
          reason: 'It does not say whether it is time-based or counter-based.',
        ),
      );
      return;
    }

    final resolvedAlgorithm = switch (algorithm) {
      _algorithmSha1 => OtpAlgorithm.sha1,
      _algorithmSha256 => OtpAlgorithm.sha256,
      _algorithmSha512 => OtpAlgorithm.sha512,
      _algorithmMd5 => null,
      // An exporter that omits the field means SHA1, which is the default the
      // whole ecosystem assumes.
      0 => OtpAlgorithm.sha1,
      _ => null,
    };
    if (resolvedAlgorithm == null) {
      zero(secret);
      skipped.add(
        MigrationSkip(
          name: label,
          reason: algorithm == _algorithmMd5
              ? 'It uses MD5, which this app does not support.'
              : 'It uses an algorithm this app does not support.',
        ),
      );
      return;
    }

    final resolvedDigits = switch (digits) {
      _digitsSix => 6,
      _digitsEight => 8,
      // Absent means the usual six digits.
      0 => 6,
      _ => null,
    };
    if (resolvedDigits == null) {
      zero(secret);
      skipped.add(
        MigrationSkip(
          name: label,
          reason: 'It asks for a number of digits this app does not support.',
        ),
      );
      return;
    }

    // Google Authenticator packs the issuer into the name as "Issuer:Account"
    // when it does not emit a separate issuer field.
    final splitName = _splitName(name, issuer);

    accounts.add(
      MigratedAccount(
        secret: secret,
        name: splitName.accountName,
        issuer: splitName.issuer,
        algorithm: resolvedAlgorithm,
        digits: resolvedDigits,
        type: resolvedType,
        counter: counter,
      ),
    );
  }

  /// Works out the issuer and account name from the two places they can appear.
  static ({String? issuer, String accountName}) _splitName(
    String name,
    String issuer,
  ) {
    final cleanIssuer = issuer.trim();
    if (cleanIssuer.isNotEmpty) {
      // The separate field wins. Strip a matching prefix from the name so the
      // account is not displayed as "GitHub" / "GitHub:ada@example.com".
      final prefix = '$cleanIssuer:';
      final accountName = name.startsWith(prefix)
          ? name.substring(prefix.length).trim()
          : name.trim();
      return (issuer: cleanIssuer, accountName: accountName);
    }

    final separator = name.indexOf(':');
    if (separator > 0) {
      final prefix = name.substring(0, separator).trim();
      final rest = name.substring(separator + 1).trim();
      if (prefix.isNotEmpty && rest.isNotEmpty) {
        return (issuer: prefix, accountName: rest);
      }
    }

    return (issuer: null, accountName: name.trim());
  }
}

/// Wire types used by the protobuf encoding.
const int _wireVarint = 0;
const int _wireLengthDelimited = 2;

/// A tag: the field number plus its wire type.
class _Tag {
  const new(this.fieldNumber, this.wireType);

  final int fieldNumber;
  final int wireType;
}

/// A minimal protobuf reader.
///
/// Supports only what the migration payload uses: varints and
/// length-delimited fields. Unknown fields are skipped by wire type, so a
/// payload from a newer exporter still parses.
class _ProtoReader {
  new(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  /// Whether there is unread data left.
  bool get hasMore => _offset < _bytes.length;

  /// Reads a field tag.
  _Tag readTag() {
    final value = readVarint();
    final fieldNumber = value >> 3;
    final wireType = value & 0x07;
    if (fieldNumber == 0) {
      throw const FormatException('invalid field number 0');
    }
    return _Tag(fieldNumber, wireType);
  }

  /// Reads a base-128 varint.
  int readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_offset >= _bytes.length) {
        throw const FormatException('truncated varint');
      }
      final byte = _bytes[_offset++];
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) break;
      shift += 7;
      // Ten bytes is the maximum for a 64-bit value; more means corrupt data.
      if (shift > 63) {
        throw const FormatException('varint too long');
      }
    }
    return result;
  }

  /// Reads a length-delimited field as raw bytes.
  ///
  /// Returns a **copy**, not a view. The caller keeps secrets read from here
  /// while the payload buffer is zeroed once parsing finishes; a view would be
  /// wiped along with it, silently turning every secret into zeros.
  Uint8List readLengthDelimited() {
    final length = readVarint();
    if (length < 0 || _offset + length > _bytes.length) {
      throw const FormatException('length-delimited field runs past the end');
    }
    final value = Uint8List.fromList(
      Uint8List.sublistView(_bytes, _offset, _offset + length),
    );
    _offset += length;
    return value;
  }

  /// Reads a length-delimited field as bytes without copying.
  ///
  /// Only for nested messages, which are consumed before the payload buffer is
  /// wiped and are never retained.
  Uint8List readLengthDelimitedView() {
    final length = readVarint();
    if (length < 0 || _offset + length > _bytes.length) {
      throw const FormatException('length-delimited field runs past the end');
    }
    final value = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return value;
  }

  /// Reads a length-delimited field as a UTF-8 string.
  ///
  /// Invalid UTF-8 is replaced rather than rejected: a mangled display name
  /// should not cost the user their account.
  String readString() {
    final bytes = readLengthDelimited();
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Skips a field of the given wire type.
  void skipField(int wireType) {
    switch (wireType) {
      case _wireVarint:
        readVarint();
      case 1: // 64-bit
        _offset += 8;
      case _wireLengthDelimited:
        readLengthDelimited();
      case 5: // 32-bit
        _offset += 4;
      default:
        throw FormatException('unsupported wire type $wireType');
    }
    if (_offset > _bytes.length) {
      throw const FormatException('field runs past the end');
    }
  }
}
