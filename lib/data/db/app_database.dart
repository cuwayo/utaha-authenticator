import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Key/value table holding non-secret user preferences.
///
/// Preferences are not secrets, so they do not belong in the keystore — but
/// keeping them here rather than in `SharedPreferences` means one storage
/// mechanism and one place to look when auditing what is persisted.
class SettingsEntries extends Table {
  /// Setting name, e.g. `theme_mode`.
  TextColumn get key => text()();

  /// Setting value, encoded as a string.
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

/// Account metadata.
///
/// **This table never holds a secret.** The OTP secret key lives only in the
/// platform keystore, addressed by [id]. Keeping the secret out of SQLite means
/// a database file recovered from a device, a backup or a debugging dump
/// contains nothing that can generate a code on its own.
///
/// The generated row class is named `AccountRow` via `@DataClassName` so it
/// cannot collide with the domain model `Account`, which is a different thing:
/// the domain model is what the UI and OTP code work with, this is its
/// persistence shape.
@DataClassName('AccountRow')
class Accounts extends Table {
  /// Stable local identifier, and the key the secret is stored under.
  TextColumn get id => text()();

  /// The user's name for this account, e.g. `ada@example.com`.
  TextColumn get accountName => text()();

  /// The service the account belongs to, e.g. `GitHub`. Null when the issuer
  /// did not supply one.
  TextColumn get issuer => text().nullable()();

  /// `totp` or `hotp`.
  TextColumn get type => text().withDefault(const Constant('totp'))();

  /// `sha1`, `sha256` or `sha512`.
  TextColumn get algorithm => text().withDefault(const Constant('sha1'))();

  /// Number of digits in a generated code.
  IntColumn get digits => integer().withDefault(const Constant(6))();

  /// TOTP time step in seconds.
  IntColumn get period => integer().withDefault(const Constant(30))();

  /// HOTP counter.
  IntColumn get counter => integer().withDefault(const Constant(0))();

  /// Comma-separated labels used for grouping. Stored as one column rather than
  /// a join table because tags are short, few, and always read together with
  /// their account.
  TextColumn get tags => text().withDefault(const Constant(''))();

  /// Whether the account is pinned to the top of the list.
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  /// Position in the user's manual ordering.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// When the account was added, in milliseconds since the epoch.
  ///
  /// Stored as an integer rather than drift's `dateTime()` so the value is
  /// unambiguously UTC and does not depend on the local time zone at write time.
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// The application's local database.
///
/// Only non-secret metadata is stored here. OTP secrets live exclusively in the
/// platform keystore via `SecretRepository`.
@DriftDatabase(tables: <Type>[SettingsEntries, Accounts])
class AppDatabase extends _$AppDatabase {
  /// Opens the app database in the application documents directory.
  new() : super(driftDatabase(name: 'utaha_authenticator'));

  /// Opens the database on an arbitrary [executor], for tests.
  new forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (migrator, from, to) async {
      // Version 1 shipped only the settings table; version 2 adds accounts.
      // Written as a step-wise ladder so future versions extend it rather than
      // replacing it.
      if (from < 2) {
        await migrator.createTable(accounts);
      }
    },
    beforeOpen: (details) async {
      // Foreign keys are not used yet, but enabling them now means a future
      // relation cannot silently go unenforced.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Reads every stored setting.
  Future<Map<String, String>> readSettings() async {
    final rows = await select(settingsEntries).get();
    return <String, String>{for (final row in rows) row.key: row.value};
  }

  /// Writes [values], replacing any existing entries with the same keys.
  ///
  /// Runs as a single transaction so a settings change can never be observed
  /// half-applied by the UI.
  Future<void> writeSettings(Map<String, String> values) {
    return transaction(() async {
      for (final entry in values.entries) {
        await into(settingsEntries).insertOnConflictUpdate(
          SettingsEntriesCompanion.insert(key: entry.key, value: entry.value),
        );
      }
    });
  }

  /// Emits the full settings map now and after every write.
  Stream<Map<String, String>> watchSettings() {
    return select(settingsEntries).watch().map(
      (rows) => <String, String>{for (final row in rows) row.key: row.value},
    );
  }

  /// All accounts, in display order: pinned first, then the user's ordering.
  ///
  /// Ordering is done in SQL so the list does not have to sort on every rebuild.
  Stream<List<AccountRow>> watchAccounts() {
    return (select(accounts)..orderBy(<OrderClauseGenerator<$AccountsTable>>[
          (t) => OrderingTerm.desc(t.pinned),
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.createdAt),
        ]))
        .watch();
  }

  /// All accounts, ordered the same way as [watchAccounts].
  Future<List<AccountRow>> readAccounts() {
    return (select(accounts)..orderBy(<OrderClauseGenerator<$AccountsTable>>[
          (t) => OrderingTerm.desc(t.pinned),
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.createdAt),
        ]))
        .get();
  }

  /// The highest `sort_order` currently in use, or null when there are no rows.
  ///
  /// Used to append a new account to the end of the user's ordering. Computed in
  /// Dart rather than with `MAX()` in SQL because the row count is small (a
  /// person has tens of accounts, not thousands) and this avoids an aggregate
  /// query whose result type would need unwrapping.
  Future<int?> highestSortOrder() async {
    final rows =
        await (select(accounts)
              ..orderBy(<OrderClauseGenerator<$AccountsTable>>[
                (t) => OrderingTerm.desc(t.sortOrder),
              ])
              ..limit(1))
            .getSingleOrNull();
    return rows?.sortOrder;
  }
}
