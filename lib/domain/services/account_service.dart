import 'dart:math';
import 'dart:typed_data';

import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/core/utils/zeroing.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/otp/otp.dart';
import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';
import 'package:utaha_authenticator/domain/otp/otp_type.dart';
import 'package:utaha_authenticator/domain/repositories/account_repository.dart';
import 'package:utaha_authenticator/domain/repositories/secret_repository.dart';

/// Generates local account identifiers.
///
/// Uses a cryptographically secure source. The identifier is not itself a
/// secret, but it is the key the secret is stored under, so guessing one would
/// let an attacker enumerate which accounts exist.
String generateAccountId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = Uint8List(16);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = source.nextInt(256);
  }
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Coordinates account metadata with the secret store.
///
/// The two live in different places — metadata in SQLite, secrets in the
/// platform keystore — so every operation here has to consider what happens if
/// one write succeeds and the other fails. The rules are:
///
/// * **Adding**: write the secret first, then the metadata. The account list is
///   driven by metadata, so until that lands the account does not exist as far
///   as the UI is concerned — no half-built row is ever shown. If the metadata
///   write fails, the secret is deleted again so nothing is left orphaned.
/// * **Deleting**: remove the metadata first, then the secret. The account
///   disappears from the UI immediately and cannot be resurrected by a failure
///   part-way through.
/// * **Orphans** are pruned on demand by [pruneOrphanedSecrets], which covers
///   the case where a compensating delete itself failed, and the case where the
///   platform keystore was reset underneath us.
class AccountService {
  /// Creates a service over the two stores.
  new({required this._accounts, required this._secrets});

  final AccountRepository _accounts;
  final SecretRepository _secrets;

  /// All accounts in display order.
  Stream<List<Account>> watchAll() => _accounts.watchAll();

  /// A one-shot read of all accounts, in display order.
  Future<List<Account>> readAll() => _accounts.readAll();

  /// Returns the account with [id], or null if there is none.
  Future<Account?> findById(String id) => _accounts.findById(id);

  /// Adds an account and stores its secret.
  ///
  /// [secret] is copied into the keystore and is **not** retained; the caller
  /// still owns the buffer and should zero it.
  ///
  /// Throws [InvalidSecretFailure] when the parameters cannot produce a valid
  /// code, so the problem is reported before anything is written.
  Future<Account> add({
    required String accountName,
    required Uint8List secret,
    String? issuer,
    OtpType type = OtpType.totp,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
    int digits = kDefaultDigits,
    int period = kDefaultPeriod,
    int counter = 0,
    List<String> tags = const <String>[],
    String? id,
  }) async {
    _validate(
      accountName: accountName,
      secret: secret,
      digits: digits,
      period: period,
      type: type,
      counter: counter,
    );

    final accountId = id ?? generateAccountId();
    final nextOrder = await _nextSortOrder();

    final account = Account(
      id: accountId,
      accountName: accountName.trim(),
      issuer: _clean(issuer),
      type: type,
      algorithm: algorithm,
      digits: digits,
      period: period,
      counter: counter,
      tags: tags,
      sortOrder: nextOrder,
      createdAt: DateTime.now(),
    );

    // Secret first: see the class comment for why.
    await _secrets.write(accountId, secret);
    try {
      await _accounts.upsert(account);
    } on Object {
      // Roll back so a failed add cannot leave a secret with no account
      // pointing at it.
      await _tryDeleteSecret(accountId);
      rethrow;
    }

    return account;
  }

  /// Replaces an account's metadata, and its secret when [newSecret] is given.
  ///
  /// Passing [newSecret] rewrites the key; omitting it leaves the existing key
  /// untouched, which is what an edit that only changes the label should do.
  Future<void> update(Account account, {Uint8List? newSecret}) async {
    _validate(
      accountName: account.accountName,
      secret: newSecret,
      digits: account.digits,
      period: account.period,
      type: account.type,
      counter: account.counter,
      secretRequired: false,
    );

    if (newSecret != null) {
      // Write the new secret before the metadata, so the account never claims a
      // key that is not there yet.
      await _secrets.write(account.id, newSecret);
    }
    await _accounts.upsert(account);
  }

  /// Removes an account and its secret.
  Future<void> delete(String id) async {
    // Metadata first: the account vanishes from the UI even if the keystore
    // delete fails, and [pruneOrphanedSecrets] can clean up afterwards.
    await _accounts.delete(id);
    await _tryDeleteSecret(id);
  }

  /// Advances an HOTP account's counter and returns the updated account.
  ///
  /// The counter is persisted immediately. HOTP counters are shared with the
  /// server, so a code that was shown but never acknowledged must not silently
  /// advance again — the user taps "next code" only after using the current one,
  /// and each tap is durable.
  Future<Account> advanceHotpCounter(String id) async {
    final account = await _accounts.findById(id);
    if (account == null) {
      throw const SecureStorageFailure(
        'That account could not be found, so its code cannot be advanced.',
      );
    }
    if (account.type != OtpType.hotp) {
      throw const InvalidSecretFailure(
        'Only counter-based accounts have a next code.',
      );
    }

    final updated = account.copyWith(counter: account.counter + 1);
    await _accounts.upsert(updated);
    return updated;
  }

  /// Persists a new manual ordering.
  Future<void> reorder(List<String> orderedIds) =>
      _accounts.reorder(orderedIds);

  /// Toggles whether an account is pinned.
  Future<void> setPinned(String id, {required bool pinned}) async {
    final account = await _accounts.findById(id);
    if (account == null) return;
    await _accounts.upsert(account.copyWith(pinned: pinned));
  }

  /// Removes secrets that no account refers to.
  ///
  /// Covers two situations: a compensating delete that itself failed, and a
  /// device whose metadata was restored from a backup while the keystore was
  /// not. Returns the identifiers that were removed.
  Future<List<String>> pruneOrphanedSecrets() async {
    final storedIds = await _secrets.accountIds();
    if (storedIds.isEmpty) return const <String>[];

    final knownIds = (await _accounts.readAll()).map((a) => a.id).toSet();
    final orphans = storedIds.difference(knownIds).toList(growable: false);

    for (final id in orphans) {
      await _tryDeleteSecret(id);
    }
    return orphans;
  }

  /// Returns the accounts whose secret is missing from the keystore.
  ///
  /// These cannot generate codes. They are reported rather than deleted, because
  /// a keystore reset is often recoverable from a backup and silently discarding
  /// the account would lose the user's only record of it.
  Future<List<String>> findAccountsMissingSecrets() async {
    final storedIds = await _secrets.accountIds();
    final accounts = await _accounts.readAll();
    return accounts
        .where((a) => !storedIds.contains(a.id))
        .map((a) => a.id)
        .toList(growable: false);
  }

  /// Deletes a secret, swallowing failures.
  ///
  /// Used for compensating actions, where the original error is the one worth
  /// reporting and a failure to clean up should not mask it.
  Future<void> _tryDeleteSecret(String id) async {
    try {
      await _secrets.delete(id);
    } on Object {
      // Deliberately ignored: the caller is already handling a failure, and
      // pruneOrphanedSecrets will retry this later.
    }
  }

  Future<int> _nextSortOrder() async {
    final highest = await _accounts.readAll();
    if (highest.isEmpty) return 0;
    return highest.map((a) => a.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Validates the parameters that would otherwise produce a wrong or
  /// ungeneratable code.
  static void _validate({
    required String accountName,
    required Uint8List? secret,
    required int digits,
    required int period,
    required OtpType type,
    required int counter,
    bool secretRequired = true,
  }) {
    if (accountName.trim().isEmpty) {
      throw const InvalidSecretFailure(
        'Please enter a name for this account so you can recognise it later.',
      );
    }
    if (secretRequired && (secret == null || secret.isEmpty)) {
      throw const InvalidSecretFailure(
        'This account needs a secret key. Check the code you scanned or typed.',
      );
    }
    if (secret != null && secret.isEmpty) {
      throw const InvalidSecretFailure(
        'That secret key is empty. Check the code you scanned or typed.',
      );
    }
    if (!kSupportedDigits.contains(digits)) {
      throw InvalidSecretFailure(
        'A code can have 6, 7 or 8 digits, but $digits was requested.',
      );
    }
    if (period <= 0) {
      throw const InvalidSecretFailure(
        'The code interval must be a positive number of seconds.',
      );
    }
    if (type == OtpType.hotp && counter < 0) {
      throw const InvalidSecretFailure(
        'The counter for a counter-based account cannot be negative.',
      );
    }
  }
}

/// Convenience for wiping a secret buffer after it has been stored.
void wipeSecret(Uint8List? secret) => zero(secret);
