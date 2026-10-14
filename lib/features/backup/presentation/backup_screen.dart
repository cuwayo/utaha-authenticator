import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/core/constants/app_constants.dart';
import 'package:utaha_authenticator/domain/backup/backup_service.dart';
import 'package:utaha_authenticator/features/backup/presentation/backup_dialogs.dart';
import 'package:utaha_authenticator/features/backup/presentation/migration_screen.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// Backup and restore.
class BackupScreen extends ConsumerWidget {
  /// Creates the backup screen.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Text(
              l10n.backupIntro,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          _SectionCard(
            icon: Icons.lock_outline,
            title: l10n.backupExportTitle,
            body: l10n.backupExportBody,
            actionLabel: l10n.backupExportAction,
            onAction: () => unawaited(_export(context, ref)),
          ),

          const SizedBox(height: 12),

          _SectionCard(
            icon: Icons.lock_open_outlined,
            title: l10n.backupRestoreTitle,
            body: l10n.backupRestoreBody,
            actionLabel: l10n.backupRestoreAction,
            onAction: () => unawaited(_restore(context, ref)),
          ),

          const SizedBox(height: 12),

          _SectionCard(
            icon: Icons.swap_horiz,
            title: l10n.backupMigrateTitle,
            body: l10n.backupMigrateBody,
            actionLabel: l10n.backupMigrateAction,
            onAction: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const MigrationScreen()),
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),

          _SectionCard(
            icon: Icons.warning_amber_outlined,
            title: l10n.backupPlainTitle,
            body: l10n.backupPlainBody,
            actionLabel: l10n.backupPlainAction,
            destructive: true,
            onAction: () => unawaited(_exportPlain(context, ref)),
          ),
        ],
      ),
    );
  }

  /// Exports an encrypted backup and offers it to the share sheet.
  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);

    final password = await promptForPassword(
      context: context,
      confirm: true,
      title: l10n.backupExportTitle,
      body: l10n.backupPasswordBody,
      confirmLabel: l10n.backupExportAction,
    );
    if (password == null || !context.mounted) return;

    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    final service = ref.read(backupServiceProvider);

    final bytes = await runWithProgress<Uint8List>(
      context: context,
      message: l10n.backupEncrypting,
      operation: () => service.export(
        password: password,
        appVersion: '${info.version}+${info.buildNumber}',
      ),
      successMessage: (_) => l10n.backupExportDone,
    );
    if (bytes == null || !context.mounted) return;

    await _shareBackup(context, bytes, l10n);
  }

  /// Writes the backup to a temporary file and hands it to the share sheet.
  ///
  /// A file rather than raw bytes because that is what the share sheet needs to
  /// offer "save to Files", "send by email" and so on.
  Future<void> _shareBackup(
    BuildContext context,
    Uint8List bytes,
    AppLocalizations l10n,
  ) async {
    // Captured before any await so the context is not used across an async gap.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final directory = await getTemporaryDirectory();
      final stamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .substring(0, 19)
          .replaceAll(':', '-');
      final file = File(
        '${directory.path}/utaha-backup-$stamp.$kBackupFileExtension',
      );
      await file.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: kBackupMimeType)],
          subject: l10n.backupShareSubject,
        ),
      );
    } on Object {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.backupShareFailed)));
    }
  }

  /// Picks a backup file and restores it.
  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);

    final PlatformFile? picked;
    try {
      // file_picker 13 returns a single file directly rather than a result
      // object, and bytes are read from it rather than passed alongside.
      picked = await FilePicker.pickFile();
    } on Object {
      if (context.mounted) {
        await showFailureDialog(context, l10n.backupPickFailed);
      }
      return;
    }
    if (picked == null || !context.mounted) return;

    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } on Object {
      if (context.mounted) {
        await showFailureDialog(context, l10n.backupPickFailed);
      }
      return;
    }
    if (!context.mounted) return;

    final password = await promptForPassword(
      context: context,
      confirm: false,
      title: l10n.backupRestoreTitle,
      body: l10n.backupRestorePasswordBody,
      confirmLabel: l10n.backupRestoreAction,
    );
    if (password == null || !context.mounted) return;

    final service = ref.read(backupServiceProvider);

    final report = await runWithProgress<RestoreReport>(
      context: context,
      message: l10n.backupDecrypting,
      operation: () => service.restore(file: bytes, password: password),
      successMessage: (result) => _describeRestore(l10n, result),
    );
    if (report == null || !context.mounted) return;

    // Anything the backup could not carry across is worth saying out loud: a
    // silent partial restore is how people lose an account without noticing.
    if (report.failed > 0) {
      await showFailureDialog(
        context,
        l10n.backupRestorePartial(report.failed),
      );
    }
  }

  static String _describeRestore(AppLocalizations l10n, RestoreReport report) {
    if (report.replaced > 0 && report.added == 0) {
      return l10n.backupRestoreReplaced(report.replaced);
    }
    if (report.skipped > 0 && report.added == 0 && report.replaced == 0) {
      return l10n.backupRestoreSkipped(report.skipped);
    }
    return l10n.backupRestoreDone(report.added + report.replaced);
  }

  /// Exports an unencrypted `otpauth://` list, after an explicit warning.
  Future<void> _exportPlain(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);

    // Two-step confirmation: this output is not protected at all, so the user
    // must acknowledge that before it is produced.
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_outlined),
        title: Text(l10n.backupPlainWarningTitle),
        content: Text(l10n.backupPlainWarningBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.backupPlainConfirm),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;

    final text = await runWithProgress<String>(
      context: context,
      message: l10n.backupExporting,
      operation: () => ref.read(backupServiceProvider).exportPlainUris(),
      successMessage: (_) => l10n.backupPlainDone,
    );
    if (text == null || !context.mounted) return;

    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/utaha-plain-uris.txt');
      await file.writeAsString(text, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'text/plain')],
          subject: l10n.backupPlainShareSubject,
        ),
      );
    } on Object {
      if (context.mounted) {
        await showFailureDialog(context, l10n.backupShareFailed);
      }
    }
  }
}

/// One labelled action on the backup screen.
class _SectionCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: destructive ? scheme.error : scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: destructive
                  ? OutlinedButton(
                      onPressed: onAction,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error,
                      ),
                      child: Text(actionLabel),
                    )
                  : FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ),
          ],
        ),
      ),
    );
  }
}
