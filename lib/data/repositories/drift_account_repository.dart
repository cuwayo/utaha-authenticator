import 'package:drift/drift.dart';
import 'package:utaha_authenticator/data/db/app_database.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';
import 'package:utaha_authenticator/domain/otp/otp_type.dart';
import 'package:utaha_authenticator/domain/repositories/account_repository.dart';

/// Persists account metadata in the local drift database.
///
/// Secrets never pass through here; see `AccountRepository` for why the two
/// stores are kept apart.
class DriftAccountRepository implements AccountRepository {
  /// Creates a repository backed by the given `database`.
  new(this._database);

  final AppDatabase _database;

  /// Separator used to pack tags into a single column.
  ///
  /// A newline is chosen because it cannot appear in a tag typed into a text
  /// field, so packing is lossless without needing escaping.
  static const String _tagSeparator = '\n';

  @override
  Stream<List<Account>> watchAll() {
    return _database.watchAccounts().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  @override
  Future<List<Account>> readAll() async {
    final rows = await _database.readAccounts();
    return rows.map(_toDomain).toList(growable: false);
  }

  @override
  Future<Account?> findById(String id) async {
    final row = await (_database.select(
      _database.accounts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<void> upsert(Account account) {
    return _database
        .into(_database.accounts)
        .insertOnConflictUpdate(
          AccountsCompanion(
            id: Value(account.id),
            accountName: Value(account.accountName),
            issuer: Value(account.issuer),
            type: Value(account.type.id),
            algorithm: Value(account.algorithm.id),
            digits: Value(account.digits),
            period: Value(account.period),
            counter: Value(account.counter),
            tags: Value(account.tags.join(_tagSeparator)),
            pinned: Value(account.pinned),
            sortOrder: Value(account.sortOrder),
            createdAt: Value(
              (account.createdAt ?? DateTime.now().toUtc())
                  .millisecondsSinceEpoch,
            ),
          ),
        );
  }

  @override
  Future<void> delete(String id) {
    return (_database.delete(
      _database.accounts,
    )..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> reorder(List<String> orderedIds) {
    return _database.transaction(() async {
      // Renumber from zero across the whole list in one transaction, so a
      // concurrent read can never observe duplicate or gapped positions.
      for (var index = 0; index < orderedIds.length; index++) {
        await (_database.update(_database.accounts)
              ..where((t) => t.id.equals(orderedIds[index])))
            .write(AccountsCompanion(sortOrder: Value(index)));
      }
    });
  }

  /// Converts a stored row into the domain model.
  static Account _toDomain(AccountRow row) {
    return Account(
      id: row.id,
      accountName: row.accountName,
      issuer: row.issuer,
      type: OtpType.fromId(row.type),
      algorithm: OtpAlgorithm.fromId(row.algorithm),
      digits: row.digits,
      period: row.period,
      counter: row.counter,
      tags: row.tags.isEmpty
          ? const <String>[]
          : row.tags.split(_tagSeparator).where((t) => t.isNotEmpty).toList(),
      pinned: row.pinned,
      sortOrder: row.sortOrder,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.createdAt,
        isUtc: true,
      ).toLocal(),
    );
  }
}
