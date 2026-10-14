import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/domain/services/account_importer.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// Scans a QR code with the camera and adds the account it describes.
///
/// The camera is stopped as soon as a code is recognised, so a second scan
/// cannot fire while the confirmation sheet is open — and so the camera is not
/// left running behind the sheet.
class ScanScreen extends ConsumerStatefulWidget {
  /// Creates the scan screen.
  const new({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    // Only QR codes are needed, and narrowing the formats makes detection both
    // faster and less prone to false positives.
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// Guards against a second detection arriving before the first is handled.
  bool _handling = false;

  /// Whether the camera failed to start, so we can show guidance instead of a
  /// black rectangle.
  bool _cameraUnavailable = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
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
    final added = await showAddAccountResult(
      context: context,
      ref: ref,
      uri: value,
    );

    if (!mounted) return;
    if (added) {
      // The account is in the list; there is nothing left to scan.
      Navigator.of(context).pop(true);
      return;
    }

    // Not added (cancelled, or the code was not usable) — let the user try again.
    _handling = false;
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanTitle)),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (_cameraUnavailable)
            _CameraUnavailable(message: l10n.scanCameraUnavailable)
          else
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) {
                // The builder runs during build, so defer the state change.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_cameraUnavailable) {
                    setState(() => _cameraUnavailable = true);
                  }
                });
                return _CameraUnavailable(message: l10n.scanCameraUnavailable);
              },
            ),
          // A viewfinder frame, so it is obvious where to aim the code.
          const _ScanOverlay(),
        ],
      ),
    );
  }
}

/// A translucent frame with a clear window in the middle.
class _ScanOverlay extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            border: Border.all(color: scheme.onSurface, width: 3),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}

/// Shown when the camera cannot be used.
class _CameraUnavailable extends StatelessWidget {
  const new({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
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
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Result of an add attempt, reported to the user.
enum AddAccountResult {
  /// The account was added.
  added,

  /// The user cancelled.
  cancelled,

  /// The account already exists and the user chose not to add it again.
  duplicateDeclined,
}

/// Handles the outcome of an import and tells the user what happened.
///
/// Shared by the scan, image and manual paths so all three behave identically.
///
/// Returns true when an account was added, so the caller can decide whether to
/// close itself.
Future<bool> showAddAccountResult({
  required BuildContext context,
  required WidgetRef ref,
  required String uri,
  String? replaceExistingId,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final importer = ref.read(accountImporterProvider);
  final outcome = await importer.importUri(
    uri,
    replaceExistingId: replaceExistingId,
  );

  if (!context.mounted) return false;

  switch (outcome) {
    case ImportSucceeded(:final account):
      unawaited(_notify(messenger, l10n.accountAdded(account.displayTitle)));
      return true;

    case ImportFailed(:final failure):
      // The failure's message is already written for a person to read.
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.addFailedTitle),
          content: Text(failure.message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.actionClose),
            ),
          ],
        ),
      );
      return false;

    case ImportDuplicate(:final existing):
      final addAnyway = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.duplicateTitle),
          content: Text(l10n.duplicateBody(existing.displayTitle)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.duplicateAddAnyway),
            ),
          ],
        ),
      );
      if (addAnyway != true) return false;
      // Re-import with the duplicate check disabled, which is what the user
      // just asked for.
      final forced = await importer.importUri(uri, force: true);
      if (forced is ImportSucceeded) {
        unawaited(
          _notify(messenger, l10n.accountAdded(forced.account.displayTitle)),
        );
        return true;
      }
      return false;
  }
}

/// Shows a short confirmation without letting a previous snackbar linger.
Future<void> _notify(ScaffoldMessengerState messenger, String text) async {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
