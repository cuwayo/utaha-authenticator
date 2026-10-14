import 'dart:async';

import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/repositories/account_repository.dart';

/// An in-memory [AccountRepository] for tests.
///
/// Mirrors the observable behaviour of the drift implementation — including
/// emitting the current list immediately to new subscribers, and re-emitting
/// after every write — without needing a database. The real repository gets its
/// own tests against a real in-memory SQLite instance.
class InMemoryAccountRepository implements AccountRepository {
  /// Creates a repository seeded with [initial].
  new([List<Account> initial = const <Account>[]])
    : _accounts = List<Account>.of(initial);

  final List<Account> _accounts;
  final StreamController<List<Account>> _controller =
      StreamController<List<Account>>.broadcast();

  @override
  Stream<List<Account>> watchAll() async* {
    yield _sorted();
    yield* _controller.stream;
  }

  @override
  Future<List<Account>> readAll() async => _sorted();

  @override
  Future<Account?> findById(String id) async {
    for (final account in _accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  @override
  Future<void> upsert(Account account) async {
    final index = _accounts.indexWhere((a) => a.id == account.id);
    if (index >= 0) {
      _accounts[index] = account;
    } else {
      _accounts.add(account);
    }
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    _accounts.removeWhere((a) => a.id == id);
    _emit();
  }

  @override
  Future<void> reorder(List<String> orderedIds) async {
    for (var index = 0; index < orderedIds.length; index++) {
      final position = _accounts.indexWhere((a) => a.id == orderedIds[index]);
      if (position >= 0) {
        _accounts[position] = _accounts[position].copyWith(sortOrder: index);
      }
    }
    _emit();
  }

  /// Accounts in display order: pinned first, then the stored ordering.
  List<Account> _sorted() {
    final sorted = List<Account>.of(_accounts)
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) return byOrder;
        final aCreated = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bCreated = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aCreated.compareTo(bCreated);
      });
    return sorted;
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_sorted());
  }

  /// Releases the broadcast stream.
  Future<void> dispose() => _controller.close();
}
