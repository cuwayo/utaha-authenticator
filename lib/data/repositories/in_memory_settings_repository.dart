import 'dart:async';

import 'package:utaha_authenticator/domain/models/app_settings.dart';
import 'package:utaha_authenticator/domain/repositories/settings_repository.dart';

/// In-memory [SettingsRepository] used in tests and before the database opens.
///
/// This is deliberately not used in production: settings written here are lost
/// when the process exits.
class InMemorySettingsRepository implements SettingsRepository {
  /// Creates a repository seeded with [initial].
  new([AppSettings initial = AppSettings.defaults]) : _current = initial;

  AppSettings _current;
  final StreamController<AppSettings> _controller =
      StreamController<AppSettings>.broadcast();

  @override
  Future<AppSettings> load() async => _current;

  @override
  Future<void> save(AppSettings settings) async {
    _current = settings;
    if (!_controller.isClosed) _controller.add(settings);
  }

  @override
  Stream<AppSettings> watch() async* {
    yield _current;
    yield* _controller.stream;
  }

  /// Releases the broadcast stream.
  Future<void> dispose() => _controller.close();
}
