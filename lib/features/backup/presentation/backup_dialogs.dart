import 'dart:async';

import 'package:flutter/material.dart';
import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// Asks for a password, twice, and returns it.
///
/// Used for both export and import so the two flows present the same thing.
/// Returns null if the user cancels.
Future<String?> promptForPassword({
  required BuildContext context,
  required bool confirm,
  required String title,
  required String body,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    // The password must not be dismissed by a stray tap outside the dialog.
    barrierDismissible: false,
    builder: (_) => _PasswordDialog(
      confirm: confirm,
      title: title,
      body: body,
      confirmLabel: confirmLabel,
    ),
  );
}

class _PasswordDialog extends StatefulWidget {
  const new({
    required this.confirm,
    required this.title,
    required this.body,
    required this.confirmLabel,
  });

  final bool confirm;
  final String title;
  final String body;
  final String confirmLabel;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _reveal = false;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.body),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              autofocus: true,
              obscureText: !_reveal,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const <String>[],
              decoration: InputDecoration(
                labelText: l10n.backupPassword,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _reveal = !_reveal),
                  icon: Icon(
                    _reveal
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  tooltip: _reveal ? l10n.actionHide : l10n.actionReveal,
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l10n.backupPasswordRequired;
                }
                return null;
              },
            ),
            if (widget.confirm) ...<Widget>[
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmation,
                obscureText: !_reveal,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const <String>[],
                decoration: InputDecoration(
                  labelText: l10n.backupPasswordConfirm,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value != _password.text) {
                    return l10n.backupPasswordMismatch;
                  }
                  return null;
                },
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(_password.text);
            }
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Shows a modal progress dialog while a slow cryptographic operation runs.
///
/// Argon2id takes seconds, so the user needs to see that something is happening
/// rather than a frozen screen.
class BackupProgressDialog extends StatelessWidget {
  /// Creates a progress dialog.
  const new({required this.message, super.key});

  /// What is happening, in plain language.
  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Dismissing mid-derivation would leave the operation running with no way
      // to report its result.
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: <Widget>[
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

/// Runs [operation] behind a progress dialog, then reports the outcome.
///
/// Centralises the "slow crypto + progress + error reporting" shape that export,
/// restore and migration import all share.
Future<T?> runWithProgress<T>({
  required BuildContext context,
  required String message,
  required Future<T> Function() operation,
  required String Function(T result) successMessage,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);

  // Show the dialog without awaiting it: awaiting would block until it closes.
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BackupProgressDialog(message: message),
    ),
  );

  try {
    final result = await operation();
    if (context.mounted) Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(successMessage(result))));
    return result;
  } on Failure catch (failure) {
    // Domain failures already carry a message written for a person.
    if (context.mounted) Navigator.of(context).pop();
    if (context.mounted) await showFailureDialog(context, failure.message);
    return null;
  } on Object {
    if (context.mounted) Navigator.of(context).pop();
    if (context.mounted) {
      await showFailureDialog(context, l10n.errorGenericBody);
    }
    return null;
  }
}

/// Shows a failure message in a dialog.
Future<void> showFailureDialog(BuildContext context, String message) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.errorGenericTitle),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.actionClose),
        ),
      ],
    ),
  );
}
