import 'dart:typed_data';

import 'package:utaha_authenticator/core/utils/zeroing.dart';
import 'package:utaha_authenticator/domain/repositories/secret_repository.dart';

/// An in-memory [SecretRepository] for tests.
///
/// Stores copies of the secret bytes rather than references, so a test that
/// zeroes the buffer it passed in cannot accidentally blank the stored value —
/// which would make the fake behave differently from a real keystore.
class InMemorySecretRepository implements SecretRepository {
  /// Creates a repository, optionally pre-seeded.
  new([Map<String, List<int>>? initial]) {
    if (initial == null) return;
    initial.forEach((key, value) {
      _secrets[key] = Uint8List.fromList(value);
    });
  }

  final Map<String, Uint8List> _secrets = <String, Uint8List>{};

  /// Records the identifiers passed to [write], in order.
  ///
  /// Lets tests assert that a secret was written before its metadata, which is
  /// the ordering the two-store design depends on.
  final List<String> writeLog = <String>[];

  /// Records the identifiers passed to [delete], in order.
  final List<String> deleteLog = <String>[];

  /// When set, [write] throws this instead of succeeding.
  Exception? writeError;

  /// When set, [delete] throws this instead of succeeding.
  Exception? deleteError;

  @override
  Future<void> write(String accountId, Uint8List secret) async {
    if (writeError != null) throw writeError!;
    writeLog.add(accountId);
    _secrets[accountId] = Uint8List.fromList(secret);
  }

  @override
  Future<Uint8List?> read(String accountId) async {
    final stored = _secrets[accountId];
    // Hand back a copy so a caller zeroing its buffer cannot corrupt the store.
    return stored == null ? null : Uint8List.fromList(stored);
  }

  @override
  Future<void> delete(String accountId) async {
    if (deleteError != null) throw deleteError!;
    deleteLog.add(accountId);
    final removed = _secrets.remove(accountId);
    // Zero the removed copy, mirroring a real store.
    zero(removed);
  }

  @override
  Future<void> deleteAll() async {
    _secrets.values.forEach(zero);
    _secrets.clear();
  }

  @override
  Future<Set<String>> accountIds() async => _secrets.keys.toSet();

  /// The raw stored bytes, for assertions. Not zeroed.
  Uint8List? peek(String accountId) => _secrets[accountId];

  /// Seeds a secret directly, bypassing [writeLog].
  void seed(String accountId, List<int> secret) {
    _secrets[accountId] = Uint8List.fromList(secret);
  }
}
