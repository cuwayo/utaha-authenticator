import 'dart:convert';
import 'dart:typed_data';

import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/core/utils/base32.dart';
import 'package:utaha_authenticator/core/utils/zeroing.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/otp/otp.dart';
import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';
import 'package:utaha_authenticator/domain/otp/otp_type.dart';

/// An account together with its secret, as carried inside a backup.
///
/// This is the only place a secret is paired with its metadata in memory, and
/// it exists only for the duration of an export or an import.
class BackupAccount {
  /// Creates a backup entry.
  new({required this.account, required this.secret});

  /// The account's metadata.
  final Account account;

  /// The raw secret key bytes. The caller owns this buffer.
  final Uint8List secret;

  /// Never prints the secret.
  @override
  String toString() =>
      'BackupAccount(issuer: ${account.issuer}, name: ${account.accountName})';
}

/// The decoded contents of a backup file.
class BackupPayload {
  /// Creates a payload.
  new({required this.accounts, this.createdAt, this.appVersion});

  /// The accounts in the backup.
  final List<BackupAccount> accounts;

  /// When the backup was written, when recorded.
  final DateTime? createdAt;

  /// The app version that wrote it, when recorded.
  final String? appVersion;

  /// Zeroes every secret held by this payload.
  void dispose() {
    for (final entry in accounts) {
      zero(entry.secret);
    }
  }

  /// Never prints secrets.
  @override
  String toString() => 'BackupPayload(accounts: ${accounts.length})';
}

/// The JSON body of a backup, before encryption.
///
/// JSON rather than a binary encoding because the payload is small (a few tens
/// of accounts), it is easy to evolve, and — importantly — it can be inspected
/// during development with the password known, without a bespoke decoder.
abstract final class BackupPayloadCodec {
  /// The schema version of the JSON body, independent of the file format.
  static const int schemaVersion = 1;

  /// Serialises [accounts] to UTF-8 JSON.
  ///
  /// The caller owns the returned buffer and must zero it: it contains every
  /// secret in plaintext.
  static Uint8List encode(
    List<BackupAccount> accounts, {
    DateTime? createdAt,
    String? appVersion,
  }) {
    final json = <String, Object?>{
      'schema': schemaVersion,
      'createdAt': (createdAt ?? DateTime.now().toUtc()).toIso8601String(),
      'appVersion': ?appVersion,
      'accounts': <Map<String, Object?>>[
        for (final entry in accounts)
          <String, Object?>{
            'id': entry.account.id,
            'accountName': entry.account.accountName,
            'issuer': entry.account.issuer,
            'type': entry.account.type.id,
            'algorithm': entry.account.algorithm.id,
            'digits': entry.account.digits,
            'period': entry.account.period,
            'counter': entry.account.counter,
            if (entry.account.tags.isNotEmpty) 'tags': entry.account.tags,
            'pinned': entry.account.pinned,
            'sortOrder': entry.account.sortOrder,
            if (entry.account.createdAt != null)
              'createdAt': entry.account.createdAt!.toUtc().toIso8601String(),
            // The secret travels as Base32 text because JSON has no byte type.
            // This is an encoding, not a protection: the whole payload is
            // encrypted before it reaches a file.
            'secret': Base32.encode(entry.secret),
          },
      ],
    };

    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }

  /// Parses a decrypted backup body.
  ///
  /// Throws [BackupFailure] when the body is not a backup this build can read.
  static BackupPayload decode(Uint8List bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on FormatException catch (error) {
      throw BackupFailure(
        'The contents of that backup could not be read. The password may be '
        'wrong, or the file may be damaged.',
        cause: error,
      );
    }

    if (decoded is! Map<String, Object?>) {
      throw const BackupFailure('That backup does not contain any accounts.');
    }

    final schema = decoded['schema'];
    if (schema is int && schema > schemaVersion) {
      throw const UnsupportedBackupVersionFailure(
        'That backup was made by a newer version of the app. Update the app, '
        'then try again.',
      );
    }

    final rawAccounts = decoded['accounts'];
    if (rawAccounts is! List) {
      throw const BackupFailure('That backup does not contain any accounts.');
    }

    final accounts = <BackupAccount>[];
    for (final raw in rawAccounts) {
      if (raw is! Map) continue;
      final entry = _decodeAccount(raw.cast<String, Object?>());
      if (entry != null) accounts.add(entry);
    }

    return BackupPayload(
      accounts: accounts,
      createdAt: _parseDate(decoded['createdAt']),
      appVersion: decoded['appVersion'] as String?,
    );
  }

  static BackupAccount? _decodeAccount(Map<String, Object?> json) {
    final secretText = json['secret'];
    final id = json['id'];
    if (secretText is! String || id is! String || secretText.isEmpty) {
      // An entry without a key or an id cannot be used; skipping it is better
      // than failing the whole restore, and the caller reports the count.
      return null;
    }

    final Uint8List secret;
    try {
      secret = Base32.decode(secretText);
    } on Object {
      return null;
    }
    if (secret.isEmpty) return null;

    final account = Account(
      id: id,
      accountName: (json['accountName'] as String?) ?? '',
      issuer: json['issuer'] as String?,
      type: OtpType.fromId(json['type'] as String?),
      algorithm: OtpAlgorithm.fromId(json['algorithm'] as String?),
      digits: _intOrDefault(json['digits'], kDefaultDigits),
      period: _intOrDefault(json['period'], kDefaultPeriod),
      counter: _intOrDefault(json['counter'], 0),
      tags: switch (json['tags']) {
        final List<Object?> tags => tags.whereType<String>().toList(),
        _ => const <String>[],
      },
      pinned: json['pinned'] == true,
      sortOrder: _intOrDefault(json['sortOrder'], 0),
      createdAt: _parseDate(json['createdAt']),
    );

    return BackupAccount(account: account, secret: secret);
  }

  static int _intOrDefault(Object? value, int fallback) =>
      value is int ? value : fallback;

  static DateTime? _parseDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }
}
