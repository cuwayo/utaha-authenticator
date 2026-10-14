import 'dart:typed_data';

import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/core/utils/zeroing.dart';
import 'package:utaha_authenticator/domain/backup/backup_codec.dart';
import 'package:utaha_authenticator/domain/backup/backup_format.dart';
import 'package:utaha_authenticator/domain/backup/backup_payload.dart';
import 'package:utaha_authenticator/domain/otpauth/otpauth_uri.dart';
import 'package:utaha_authenticator/domain/repositories/account_repository.dart';
import 'package:utaha_authenticator/domain/repositories/secret_repository.dart';
import 'package:utaha_authenticator/domain/services/account_service.dart';

/// How an import resolved an account that already existed.
enum ImportConflictResolution {
  /// A new account was created alongside the existing one.
  added,

  /// The existing account was overwritten.
  replaced,

  /// The entry was left alone.
  skipped,
}

/// The outcome of restoring a backup.
class RestoreReport {
  /// Creates a restore report.
  const new({
    required this.added,
    required this.replaced,
    required this.skipped,
    required this.failed,
  });

  /// Accounts that were newly created.
  final int added;

  /// Accounts that overwrote an existing entry with the same id.
  final int replaced;

  /// Accounts left untouched because they already existed.
  final int skipped;

  /// Entries that could not be restored.
  final int failed;

  /// The total number of entries considered.
  int get total => added + replaced + skipped + failed;

  /// Never prints secrets.
  @override
  String toString() =>
      'RestoreReport(added: $added, replaced: $replaced, '
      'skipped: $skipped, failed: $failed)';
}

/// Exports accounts to an encrypted backup and restores them again.
///
/// The two operations that move secrets in bulk live here, so the code that
/// handles plaintext secrets in memory is confined to one file.
class BackupService {
  /// Creates a service over the two stores.
  ///
  /// [parameters] defaults to the production Argon2id cost. Tests override it
  /// with something cheap: the defaults are deliberately expensive, and a test
  /// that round-trips a backup a dozen times would otherwise spend most of its
  /// runtime in the KDF and hit the test timeout.
  new({
    required this._accounts,
    required this._secrets,
    Argon2idParameters? parameters,
  }) : _parameters = parameters ?? BackupFormat.argon2id;

  final AccountRepository _accounts;
  final SecretRepository _secrets;
  final Argon2idParameters _parameters;

  /// Builds an encrypted `.utaha` file containing every account.
  ///
  /// [password] is used once and is not retained. The caller owns the returned
  /// buffer, which is ciphertext and needs no zeroing.
  ///
  /// Runs Argon2id, which takes seconds; call it off the UI thread.
  Future<Uint8List> export({
    required String password,
    String? appVersion,
  }) async {
    final accounts = await _accounts.readAll();
    if (accounts.isEmpty) {
      throw const BackupFailure('There are no accounts to back up yet.');
    }

    final entries = <BackupAccount>[];
    try {
      for (final account in accounts) {
        final secret = await _secrets.read(account.id);
        if (secret == null || secret.isEmpty) {
          // An account whose key is missing cannot be restored usefully, so
          // including it would only produce a backup that fails on restore.
          zero(secret);
          continue;
        }
        entries.add(BackupAccount(account: account, secret: secret));
      }

      if (entries.isEmpty) {
        throw const BackupFailure(
          'None of your accounts could be read, so there is nothing to back '
          'up.',
        );
      }

      final plaintext = BackupPayloadCodec.encode(
        entries,
        appVersion: appVersion,
      );
      try {
        return await BackupCodec.encode(
          plaintext: plaintext,
          password: password,
          parameters: _parameters,
        );
      } finally {
        // The plaintext holds every secret in the clear.
        zero(plaintext);
      }
    } finally {
      for (final entry in entries) {
        zero(entry.secret);
      }
    }
  }

  /// Restores the accounts in a `.utaha` file.
  ///
  /// [onConflict] decides what happens when an account with the same id already
  /// exists. The default replaces it, which is what re-importing your own backup
  /// should do.
  ///
  /// Runs Argon2id, which takes seconds; call it off the UI thread.
  Future<RestoreReport> restore({
    required Uint8List file,
    required String password,
    ImportConflictResolution onConflict = ImportConflictResolution.replaced,
  }) async {
    final plaintext = await BackupCodec.decode(file: file, password: password);

    final BackupPayload payload;
    try {
      payload = BackupPayloadCodec.decode(plaintext);
    } finally {
      zero(plaintext);
    }

    var added = 0;
    var replaced = 0;
    var skipped = 0;
    var failed = 0;

    try {
      for (final entry in payload.accounts) {
        try {
          final existing = await _accounts.findById(entry.account.id);

          if (existing != null &&
              onConflict == ImportConflictResolution.skipped) {
            skipped++;
            continue;
          }

          if (existing == null) {
            await _accounts.upsert(entry.account);
            await _secrets.write(entry.account.id, entry.secret);
            added++;
          } else if (onConflict == ImportConflictResolution.replaced) {
            await _accounts.upsert(entry.account);
            await _secrets.write(entry.account.id, entry.secret);
            replaced++;
          } else {
            // `added` on conflict: a fresh id so both accounts survive.
            final newId = generateAccountId();
            await _accounts.upsert(entry.account.copyWith(id: newId));
            await _secrets.write(newId, entry.secret);
            added++;
          }
        } on Object {
          // One bad entry must not abort the whole restore.
          failed++;
        }
      }
    } finally {
      payload.dispose();
    }

    return RestoreReport(
      added: added,
      replaced: replaced,
      skipped: skipped,
      failed: failed,
    );
  }

  /// Builds an unencrypted list of `otpauth://` URIs for every account.
  ///
  /// This output is **not protected in any way**: anyone who obtains it can
  /// generate codes for every account. It exists because some people need to
  /// move accounts to a tool that only reads `otpauth://`, and it is the
  /// caller's job to warn them before writing it anywhere.
  Future<String> exportPlainUris() async {
    final accounts = await _accounts.readAll();
    final lines = <String>[];

    for (final account in accounts) {
      final secret = await _secrets.read(account.id);
      if (secret == null || secret.isEmpty) {
        zero(secret);
        continue;
      }
      try {
        lines.add(
          OtpAuthUri.build(
            secret: secret,
            accountName: account.accountName,
            issuer: account.issuer,
            type: account.type,
            algorithm: account.algorithm,
            digits: account.digits,
            period: account.period,
            counter: account.counter,
          ),
        );
      } finally {
        zero(secret);
      }
    }

    if (lines.isEmpty) {
      throw const BackupFailure('There are no accounts to export yet.');
    }
    return lines.join('\n');
  }

  /// The Argon2id parameters this instance uses.
  Argon2idParameters get parameters => _parameters;
}
