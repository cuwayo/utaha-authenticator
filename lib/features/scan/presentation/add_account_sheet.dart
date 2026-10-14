import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:utaha_authenticator/features/scan/presentation/manual_entry_screen.dart';
import 'package:utaha_authenticator/features/scan/presentation/scan_screen.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// The three ways to add an account, presented as a bottom sheet.
///
/// Returns true when an account was added, so the caller can refresh if needed.
Future<bool> showAddAccountSheet(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);

  final choice = await showModalBottomSheet<_AddMethod>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.addAccount,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: Text(l10n.addByScanning),
            subtitle: Text(l10n.addByScanningHelp),
            onTap: () => Navigator.of(sheetContext).pop(_AddMethod.scan),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: Text(l10n.addFromImage),
            subtitle: Text(l10n.addFromImageHelp),
            onTap: () => Navigator.of(sheetContext).pop(_AddMethod.image),
          ),
          ListTile(
            leading: const Icon(Icons.keyboard),
            title: Text(l10n.addManually),
            subtitle: Text(l10n.addManuallyHelp),
            onTap: () => Navigator.of(sheetContext).pop(_AddMethod.manual),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (choice == null || !context.mounted) return false;

  switch (choice) {
    case _AddMethod.scan:
      final added = await Navigator.of(
        context,
      ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const ScanScreen()));
      return added ?? false;

    case _AddMethod.manual:
      final added = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const ManualEntryScreen()),
      );
      return added ?? false;

    case _AddMethod.image:
      return await _importFromImage(context, ref);
  }
}

enum _AddMethod { scan, image, manual }

/// Lets the user pick an image containing a QR code and imports it.
///
/// Uses the system photo picker rather than a custom gallery browser, so the app
/// only ever receives the single image the user chose.
Future<bool> _importFromImage(BuildContext context, WidgetRef ref) {
  return _pickAndAnalyse(context, ref, AppLocalizations.of(context));
}

/// Picks an image and analyses it.
///
/// Split from [_importFromImage] so the caller can return this future directly
/// instead of awaiting it.
Future<bool> _pickAndAnalyse(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
) async {
  final picker = ImagePicker();
  final XFile? picked;
  try {
    picked = await picker.pickImage(source: ImageSource.gallery);
  } on Object {
    if (context.mounted) _showMessage(context, l10n.imagePickFailed);
    return false;
  }
  if (picked == null) return false;
  if (!context.mounted) return false;

  // Analysing is done by the scanner plugin, which needs a controller of its
  // own; it is disposed as soon as the analysis finishes.
  final controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );

  try {
    final capture = await controller.analyzeImage(picked.path);
    final value = capture?.barcodes
        .map((barcode) => barcode.rawValue)
        .firstWhere((raw) => raw != null && raw.isNotEmpty, orElse: () => null);

    if (!context.mounted) return false;
    if (value == null) {
      _showMessage(context, l10n.imageNoCodeFound);
      return false;
    }

    return await showAddAccountResult(context: context, ref: ref, uri: value);
  } on Object {
    if (context.mounted) _showMessage(context, l10n.imageNoCodeFound);
    return false;
  } finally {
    unawaited(controller.dispose());
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
