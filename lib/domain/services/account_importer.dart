import 'dart:typed_data';

import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/core/utils/zeroing.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/otp/otp.dart';
import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';
import 'package:utaha_authenticator/domain/otp/otp_type.dart';
import 'package:utaha_authenticator/domain/otpauth/otpauth_uri.dart';
import 'package:utaha_authenticator/domain/services/account_service.dart';

/// The outcome of an attempted import.
sealed class ImportOutcome {
  const new();
}

/// The account was added.
final class ImportSucceeded extends ImportOutcome {
  /// Creates a success outcome.
  const new(this.account);

  /// The account that was created.
  final Account account;
}

/// An account with the same service and name already exists.
///
/// Not an error: adding a duplicate is sometimes deliberate (two accounts for
/// the same service, or re-adding after a reset), so the caller decides whether
/// to proceed rather than being blocked.
final class ImportDuplicate extends ImportOutcome {
  /// Creates a duplicate outcome.
  const new(this.existing);

  /// The account that is already present.
  final Account existing;
}

/// The input could not be turned into an account.
final class ImportFailed extends ImportOutcome {
  /// Creates a failure outcome.
  const new(this.failure);

  /// What went wrong, with a message safe to show.
  final Failure failure;
}

/// Turns scanned or typed input into accounts.
///
/// Keeps the "is this a duplicate?" question in one place, so the scan, image
/// and manual paths all behave the same way.
class AccountImporter {
  /// Creates an importer over the given `accounts` service.
  new(this._accounts);

  final AccountService _accounts;

  /// Parses [uri] and adds the account it describes.
  ///
  /// When [replaceExistingId] is given, an account with that id is updated in
  /// place instead of a new one being created — used by the edit flow.
  ///
  /// The secret inside the parsed URI is zeroed before returning, whatever the
  /// outcome.
  Future<ImportOutcome> importUri(
    String uri, {
    String? replaceExistingId,
    bool force = false,
  }) async {
    final ParsedOtpAuth parsed;
    try {
      parsed = OtpAuthUri.parse(uri);
    } on Failure catch (failure) {
      return ImportFailed(failure);
    }

    try {
      return await _add(
        secret: parsed.secret,
        accountName: parsed.accountName,
        issuer: parsed.issuer,
        type: parsed.type,
        algorithm: parsed.algorithm,
        digits: parsed.digits,
        period: parsed.period,
        counter: parsed.counter ?? 0,
        replaceExistingId: replaceExistingId,
        force: force,
      );
    } finally {
      // The parsed URI owns this buffer; nothing outside may keep it.
      zero(parsed.secret);
    }
  }

  /// Adds an account from values typed into the manual-entry form.
  ///
  /// **The caller owns [secret] and must zero it.** It is deliberately not
  /// wiped here because the duplicate-retry flow may need it again; wiping it
  /// inside would make a second attempt use an empty key.
  Future<ImportOutcome> importManual({
    required String accountName,
    required Uint8List secret,
    String? issuer,
    OtpType type = OtpType.totp,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
    int digits = kDefaultDigits,
    int period = kDefaultPeriod,
    int counter = 0,
    String? replaceExistingId,
    bool force = false,
  }) async {
    try {
      return await _add(
        secret: secret,
        accountName: accountName,
        issuer: issuer,
        type: type,
        algorithm: algorithm,
        digits: digits,
        period: period,
        counter: counter,
        replaceExistingId: replaceExistingId,
        force: force,
      );
    } on Failure catch (failure) {
      return ImportFailed(failure);
    }
  }

  /// Updates an account's metadata without touching its stored secret.
  ///
  /// Used by the edit flow when the user leaves the key field blank, which is
  /// the normal case: renaming an account should not require re-entering its
  /// secret.
  Future<ImportOutcome> updateMetadata(Account account) async {
    try {
      await _accounts.update(account);
      return ImportSucceeded(account);
    } on Failure catch (failure) {
      return ImportFailed(failure);
    }
  }

  /// Returns the accounts that would collide with the given service and name.
  ///
  /// Matching is case-insensitive and trims whitespace, because the same
  /// account scanned twice rarely differs by anything more than spacing.
  Future<List<Account>> findDuplicates({
    required String accountName,
    String? issuer,
  }) async {
    final targetIssuer = (issuer ?? '').trim().toLowerCase();
    final targetName = accountName.trim().toLowerCase();

    final all = await _accounts.readAll();
    return all
        .where(
          (a) =>
              (a.issuer ?? '').trim().toLowerCase() == targetIssuer &&
              a.accountName.trim().toLowerCase() == targetName,
        )
        .toList(growable: false);
  }

  Future<ImportOutcome> _add({
    required Uint8List secret,
    required String accountName,
    required OtpType type,
    required OtpAlgorithm algorithm,
    required int digits,
    required int period,
    required int counter,
    String? issuer,
    String? replaceExistingId,
    bool force = false,
  }) async {
    // `force` is how the user overrides the duplicate prompt: without it this
    // would re-detect the same duplicate and ask again, forever.
    final existing = force
        ? const <Account>[]
        : await findDuplicates(issuer: issuer, accountName: accountName);

    // When replacing, the account being edited is not a duplicate of itself.
    final others = existing
        .where((a) => a.id != replaceExistingId)
        .toList(growable: false);
    if (others.isNotEmpty) {
      return ImportDuplicate(others.first);
    }

    try {
      if (replaceExistingId != null) {
        final current = await _accounts.findById(replaceExistingId);
        if (current == null) {
          return const ImportFailed(
            InvalidSecretFailure(
              'That account no longer exists, so it could not be updated.',
            ),
          );
        }
        final updated = current.copyWith(
          accountName: accountName,
          issuer: issuer,
          type: type,
          algorithm: algorithm,
          digits: digits,
          period: period,
          counter: counter,
        );
        await _accounts.update(updated, newSecret: secret);
        return ImportSucceeded(updated);
      }

      final account = await _accounts.add(
        accountName: accountName,
        issuer: issuer,
        secret: secret,
        type: type,
        algorithm: algorithm,
        digits: digits,
        period: period,
        counter: counter,
      );
      return ImportSucceeded(account);
    } on Failure catch (failure) {
      return ImportFailed(failure);
    }
  }
}
