import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/domain/migration/google_auth_migration.dart';
import 'package:utaha_authenticator/features/backup/presentation/backup_dialogs.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// Imports accounts from a Google Authenticator export.
///
/// The flow is: scan (or paste) the export QR code, review what was found, then
/// confirm. The review step matters because an export can carry dozens of
/// accounts and the user should see what is about to be added — including
/// anything that had to be skipped.
class MigrationScreen extends ConsumerStatefulWidget {
  /// Creates the migration screen.
  const new({super.key});

  @override
  ConsumerState<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends ConsumerState<MigrationScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  final TextEditingController _pasteController = TextEditingController();

  /// Set while a scan is being handled, so a second one cannot start.
  bool _handling = false;

  /// Whether to show the manual paste field instead of the camera.
  bool _manualEntry = false;

  /// True while accounts are being written.
  bool _importing = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .firstWhere((raw) => raw != null && raw.isNotEmpty, orElse: () => null);
    if (value == null) return;

    _handling = true;
    await _controller.stop();
    if (!mounted) return;
    await _review(value);
  }

  /// Parses [raw], shows the preview, and imports on confirmation.
  Future<void> _review(String raw) async {
    final l10n = AppLocalizations.of(context);

    final MigrationPayload payload;
    try {
      payload = GoogleAuthMigration.parse(raw);
    } on Failure catch (failure) {
      if (!mounted) return;
      await showFailureDialog(context, failure.message);
      _resumeScanning();
      return;
    }

    if (!mounted) {
      payload.dispose();
      return;
    }

    if (payload.accounts.isEmpty) {
      await showFailureDialog(
        context,
        payload.skipped.isEmpty
            ? l10n.migrationNoAccounts
            : l10n.migrationAllSkipped,
      );
      payload.dispose();
      _resumeScanning();
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PreviewSheet(payload: payload),
    );

    if (confirmed != true) {
      payload.dispose();
      _resumeScanning();
      return;
    }

    await _import(payload);
  }

  /// Writes the reviewed accounts into the stores.
  Future<void> _import(MigrationPayload payload) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _importing = true);

    final service = ref.read(accountServiceProvider);
    var added = 0;
    var failed = 0;
    // Captured before dispose() clears the payload.
    final skippedCount = payload.skipped.length;

    try {
      for (final entry in payload.accounts) {
        try {
          await service.add(
            accountName: entry.name,
            issuer: entry.issuer,
            secret: entry.secret,
            type: entry.type,
            algorithm: entry.algorithm,
            digits: entry.digits,
            counter: entry.counter,
          );
          added++;
        } on Object {
          // One bad entry must not lose the rest of the export.
          failed++;
        }
      }
    } finally {
      // The payload holds a secret per account.
      payload.dispose();
      if (mounted) setState(() => _importing = false);
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.migrationImported(added))));

    if (failed > 0 || skippedCount > 0) {
      await showFailureDialog(
        context,
        l10n.migrationSomeSkipped(failed + skippedCount),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  /// Restarts the camera after a cancelled or failed attempt.
  void _resumeScanning() {
    _handling = false;
    if (mounted && !_manualEntry) unawaited(_controller.start());
  }

  /// Handles a pasted URI.
  Future<void> _importFromText() async {
    final text = _pasteController.text.trim();
    if (text.isEmpty) return;
    _pasteController.clear();
    await _review(text);
  }

  /// Imports from a saved image.
  Future<void> _importFromImage() async {
    final l10n = AppLocalizations.of(context);
    // The picker lives on the add-account sheet; here the export is normally a
    // QR code the user is looking at on another screen, so a paste box is the
    // more useful fallback.
    await showFailureDialog(context, l10n.migrationUsePasteInstead);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.migrationTitle),
        actions: <Widget>[
          IconButton(
            onPressed: () {
              setState(() => _manualEntry = !_manualEntry);
              if (_manualEntry) {
                unawaited(_controller.stop());
              } else {
                unawaited(_controller.start());
              }
            },
            icon: Icon(_manualEntry ? Icons.qr_code_scanner : Icons.paste),
            tooltip: _manualEntry
                ? l10n.migrationUseCamera
                : l10n.migrationUsePaste,
          ),
        ],
      ),
      body: _importing
          ? const Center(child: CircularProgressIndicator())
          : _manualEntry
          ? _PastePanel(
              controller: _pasteController,
              onImport: () => unawaited(_importFromText()),
              onPickImage: () => unawaited(_importFromImage()),
            )
          : Stack(
              fit: StackFit.expand,
              children: <Widget>[
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => _CameraFallback(
                    onUsePaste: () => setState(() => _manualEntry = true),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.onSurface,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The review sheet: what was found, and what will happen.
class _PreviewSheet extends StatelessWidget {
  const new({required this.payload});

  final MigrationPayload payload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.migrationPreviewTitle(payload.accounts.length),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.migrationPreviewBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (payload.isMultiPart)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.migrationMultiPart(
                        payload.batchIndex + 1,
                        payload.batchSize,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (payload.skipped.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Card.filled(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.migrationSkippedTitle(payload.skipped.length),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final skip in payload.skipped)
                        Text(
                          '${skip.name}: ${skip.reason}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: payload.accounts.length,
              itemBuilder: (context, index) {
                final account = payload.accounts[index];
                return ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: Text(account.issuer ?? account.name),
                  subtitle: Text(
                    <String>[
                      if (account.issuer != null) account.name,
                      '${account.algorithm.uriName} · ${account.digits} digits',
                      if (account.type.name == 'hotp')
                        'counter ${account.counter}',
                    ].join(' · '),
                  ),
                  // Never show the secret, even in a preview.
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(l10n.actionCancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(l10n.migrationConfirm),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paste-the-URI fallback, for when the camera is not usable.
class _PastePanel extends StatelessWidget {
  const new({
    required this.controller,
    required this.onImport,
    required this.onPickImage,
  });

  final TextEditingController controller;
  final VoidCallback onImport;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text(l10n.migrationPasteTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          l10n.migrationPasteBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          maxLines: 4,
          minLines: 2,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: l10n.migrationPasteLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onImport,
          icon: const Icon(Icons.download_outlined),
          label: Text(l10n.migrationImportAction),
        ),
      ],
    );
  }
}

/// Shown when the camera cannot start.
class _CameraFallback extends StatelessWidget {
  const new({required this.onUsePaste});

  final VoidCallback onUsePaste;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.no_photography_outlined,
                size: 56,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.scanCameraUnavailable,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onUsePaste,
                child: Text(l10n.migrationUsePaste),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
