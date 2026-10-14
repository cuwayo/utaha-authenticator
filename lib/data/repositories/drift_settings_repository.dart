import 'package:utaha_authenticator/data/db/app_database.dart';
import 'package:utaha_authenticator/domain/models/app_settings.dart';
import 'package:utaha_authenticator/domain/repositories/settings_repository.dart';

/// Persists settings in the local drift database.
class DriftSettingsRepository implements SettingsRepository {
  /// Creates a repository backed by the given `database`.
  new(this._database);

  final AppDatabase _database;

  @override
  Future<AppSettings> load() async {
    return AppSettings.fromMap(await _database.readSettings());
  }

  @override
  Future<void> save(AppSettings settings) {
    return _database.writeSettings(settings.toMap());
  }

  @override
  Stream<AppSettings> watch() {
    return _database.watchSettings().map(AppSettings.fromMap);
  }
}
