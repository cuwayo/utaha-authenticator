import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/core/widgets/empty_state.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/models/app_settings.dart';
import 'package:utaha_authenticator/domain/models/display_preferences.dart';
import 'package:utaha_authenticator/domain/services/code_generator.dart';
import 'package:utaha_authenticator/features/accounts/presentation/widgets/account_tile.dart';
import 'package:utaha_authenticator/features/scan/presentation/add_account_sheet.dart';
import 'package:utaha_authenticator/features/scan/presentation/manual_entry_screen.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// The home screen: a list of accounts and their current codes.
class AccountsScreen extends ConsumerStatefulWidget {
  /// Creates the accounts screen.
  const new({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _startSearch() {
    setState(() => _searching = true);
  }

  void _stopSearch() {
    _searchController.clear();
    ref.read(accountSearchQueryProvider.notifier).clear();
    setState(() => _searching = false);
  }

  /// Copies [account]'s code and tells the user what happened.
  Future<void> _copyCode(Account account, AccountCode code) async {
    final settings =
        ref.read(settingsControllerProvider).value ?? AppSettings.defaults;
    final clipboard = ref.read(clipboardServiceProvider);

    final scheduled = await clipboard.copyWithAutoClear(
      code.code,
      clearAfterSeconds: settings.clipboardClearSeconds,
    );

    // A short, crisp confirmation. Haptics matter here: the user is looking at
    // another app when they paste, so the tap is the only feedback they get.
    await HapticFeedback.lightImpact();

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            scheduled
                ? l10n.copiedToClipboard(settings.clipboardClearSeconds)
                : l10n.codeCopiedNoClear,
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _advanceCounter(Account account) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    await ref.read(accountServiceProvider).advanceHotpCounter(account.id);
    // The code stream is driven by the accounts stream, so the new code appears
    // as soon as the updated counter reaches the database. Read the current
    // value rather than awaiting the provider's `future`, which does not
    // resolve for these provider types.
    final next = ref.read(accountCodesProvider).value?[account.id];
    if (next == null) return;

    await HapticFeedback.selectionClick();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.nextCodeIs(next.code)),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// Hides the account and offers an undo window before deleting it for good.
  void _deleteWithUndo(Account account) {
    final l10n = AppLocalizations.of(context);
    ref.read(pendingDeletionsProvider.notifier).schedule(account.id);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.accountRemoved(account.displayTitle)),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: l10n.actionUndo,
            onPressed: () =>
                ref.read(pendingDeletionsProvider.notifier).undo(account.id),
          ),
        ),
      );
  }

  /// Opens the edit form for [account].
  Future<void> _editAccount(Account account) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ManualEntryScreen(editing: account),
      ),
    );
  }

  Future<void> _togglePinned(Account account) async {
    await ref
        .read(accountServiceProvider)
        .setPinned(account.id, pinned: !account.pinned);
  }

  Future<void> _reorder(
    List<Account> accounts,
    int oldIndex,
    int newIndex,
  ) async {
    // `onReorderItem` (unlike the deprecated `onReorder`) already accounts for
    // the removal of the item at oldIndex, so newIndex needs no adjustment here.
    final ids = accounts.map((a) => a.id).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    await ref.read(accountServiceProvider).reorder(ids);
  }

  /// Opens the per-account menu.
  Future<void> _showAccountMenu(Account account) async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    account.displayTitle,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  if (account.displaySubtitle.isNotEmpty)
                    Text(
                      account.displaySubtitle,
                      style: Theme.of(sheetContext).textTheme.bodyMedium
                          ?.copyWith(
                            color: Theme.of(sheetContext)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(
                account.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              title: Text(account.pinned ? l10n.actionUnpin : l10n.actionPin),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_togglePinned(account));
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.actionEdit),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_editAccount(account));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.actionDelete),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _deleteWithUndo(account);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
    final accounts = ref.watch(visibleAccountsProvider);
    final codes =
        ref.watch(accountCodesProvider).value ?? const <String, AccountCode>{};
    final totalAccounts = ref.watch(accountsProvider).value?.length ?? 0;
    final compact = settings.listDensity == ListDensity.compact;

    return Scaffold(
      appBar: _searching
          ? _searchAppBar(l10n)
          : AppBar(
              title: Text(
                l10n.appTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: <Widget>[
                if (totalAccounts > 0)
                  IconButton(
                    onPressed: _startSearch,
                    icon: const Icon(Icons.search),
                    tooltip: l10n.actionSearch,
                  ),
              ],
            ),
      body: _buildBody(
        accounts: accounts,
        codes: codes,
        settings: settings,
        compact: compact,
        l10n: l10n,
        hasAnyAccount: totalAccounts > 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(showAddAccountSheet(context, ref)),
        icon: const Icon(Icons.add),
        label: Text(l10n.addAccount),
      ),
    );
  }

  PreferredSizeWidget _searchAppBar(AppLocalizations l10n) {
    return AppBar(
      leading: IconButton(
        onPressed: _stopSearch,
        icon: const Icon(Icons.arrow_back),
        tooltip: l10n.actionClose,
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: l10n.searchAccountsHint,
          border: InputBorder.none,
        ),
        onChanged: (value) =>
            ref.read(accountSearchQueryProvider.notifier).query = value,
      ),
      actions: <Widget>[
        IconButton(
          onPressed: () {
            _searchController.clear();
            ref.read(accountSearchQueryProvider.notifier).clear();
          },
          icon: const Icon(Icons.clear),
          tooltip: l10n.actionClear,
        ),
      ],
    );
  }

  Widget _buildBody({
    required List<Account> accounts,
    required Map<String, AccountCode> codes,
    required AppSettings settings,
    required bool compact,
    required AppLocalizations l10n,
    required bool hasAnyAccount,
  }) {
    if (accounts.isEmpty) {
      // Two different empty states: nothing added yet, versus a search that
      // matched nothing. Showing the onboarding copy for an empty search would
      // be misleading.
      if (hasAnyAccount) {
        return EmptyState(
          icon: Icons.search_off,
          title: l10n.emptySearchTitle,
          body: l10n.emptySearchBody,
        );
      }
      return EmptyState(
        icon: Icons.pin_outlined,
        title: l10n.emptyAccountsTitle,
        body: l10n.emptyAccountsBody,
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: accounts.length,
      // Long-press drag: the row's tap and long-press already belong to copy and
      // the menu, so a dedicated handle would be needed for immediate drag.
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) =>
          _reorder(accounts, oldIndex, newIndex),
      proxyDecorator: (child, index, animation) => Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
      itemBuilder: (context, index) {
        final account = accounts[index];
        return Padding(
          key: ValueKey(account.id),
          padding: EdgeInsets.only(bottom: compact ? 6 : 10),
          child: ReorderableDelayedDragStartListener(
            index: index,
            child: AccountTile(
              account: account,
              code: codes[account.id],
              grouping: settings.codeGrouping,
              tapToReveal: settings.tapToReveal,
              compact: compact,
              onCopy: () {
                final code = codes[account.id];
                if (code != null) unawaited(_copyCode(account, code));
              },
              onLongPress: () => _showAccountMenu(account),
              onAdvanceCounter: () => unawaited(_advanceCounter(account)),
            ),
          ),
        );
      },
    );
  }
}
