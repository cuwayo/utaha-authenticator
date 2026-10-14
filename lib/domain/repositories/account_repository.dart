import 'package:utaha_authenticator/domain/models/account.dart';

/// Reads and writes account metadata.
///
/// Secrets are **not** part of this interface. They are handled separately by
/// `SecretRepository` so that no code path can accidentally persist a secret to
/// the database along with an account.
abstract interface class AccountRepository {
  /// All accounts in display order: pinned first, then the user's ordering.
  Stream<List<Account>> watchAll();

  /// A one-shot read of all accounts, in display order.
  Future<List<Account>> readAll();

  /// Returns the account with [id], or null if there is none.
  Future<Account?> findById(String id);

  /// Inserts or replaces the account's metadata.
  ///
  /// Does not touch the secret; the caller writes that to the keystore. Kept
  /// separate so the two stores can be written in a deliberate order — see
  /// `AccountService` for why the ordering matters.
  Future<void> upsert(Account account);

  /// Removes the account's metadata.
  Future<void> delete(String id);

  /// Persists a new manual ordering.
  ///
  /// Takes the full ordered list rather than individual moves so the stored
  /// ordering can never end up with duplicate or gapped positions.
  Future<void> reorder(List<String> orderedIds);
}
