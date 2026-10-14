import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/core/errors/failures.dart';
import 'package:utaha_authenticator/core/theme/app_typography.dart';
import 'package:utaha_authenticator/core/utils/base32.dart';
import 'package:utaha_authenticator/core/utils/zeroing.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/otp/otp.dart';
import 'package:utaha_authenticator/domain/otp/otp_algorithm.dart';
import 'package:utaha_authenticator/domain/otp/otp_type.dart';
import 'package:utaha_authenticator/domain/services/account_importer.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// Types an account in by hand.
///
/// Also used for editing, in which case the secret is left blank and the
/// existing key is kept — the user should not have to re-enter a key to rename
/// an account.
class ManualEntryScreen extends ConsumerStatefulWidget {
  /// Creates the manual entry screen.
  const new({this.editing, super.key});

  /// The account being edited, or null when adding a new one.
  final Account? editing;

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _issuer;
  late final TextEditingController _accountName;
  late final TextEditingController _secret;
  late final TextEditingController _period;
  late final TextEditingController _counter;

  OtpType _type = OtpType.totp;
  OtpAlgorithm _algorithm = OtpAlgorithm.sha1;
  int _digits = kDefaultDigits;

  /// Whether the secret is currently visible.
  bool _revealSecret = false;

  /// True while the account is being saved.
  bool _saving = false;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.editing;
    _issuer = TextEditingController(text: existing?.issuer ?? '');
    _accountName = TextEditingController(text: existing?.accountName ?? '');
    // Deliberately blank even when editing: the stored secret is never loaded
    // into a text field, so it cannot leak into the widget tree or a keyboard
    // buffer. Leaving it blank keeps the existing key.
    _secret = TextEditingController();
    _period = TextEditingController(
      text: (existing?.period ?? kDefaultPeriod).toString(),
    );
    _counter = TextEditingController(text: (existing?.counter ?? 0).toString());
    if (existing != null) {
      _type = existing.type;
      _algorithm = existing.algorithm;
      _digits = existing.digits;
    }
  }

  @override
  void dispose() {
    _issuer.dispose();
    _accountName.dispose();
    _secret.dispose();
    _period.dispose();
    _counter.dispose();
    super.dispose();
  }

  /// Validates the account name field.
  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return AppLocalizations.of(context).validationNameRequired;
    }
    return null;
  }

  /// Validates the secret field.
  ///
  /// When editing, an empty field means "keep the existing key", so it passes.
  String? _validateSecret(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return _isEditing
          ? null
          : AppLocalizations.of(context).validationSecretRequired;
    }
    try {
      Base32.decode(text);
      return null;
    } on Base32FormatException catch (error) {
      // The decoder's message already explains the problem in plain language.
      return error.message;
    }
  }

  String? _validatePeriod(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed <= 0) {
      return AppLocalizations.of(context).validationPeriodInvalid;
    }
    return null;
  }

  String? _validateCounter(String? value) {
    if (_type != OtpType.hotp) return null;
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 0) {
      return AppLocalizations.of(context).validationCounterInvalid;
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    final l10n = AppLocalizations.of(context);
    final importer = ref.read(accountImporterProvider);
    final rawSecret = _secret.text.trim();

    // Decode into bytes, hand them over, and let the importer zero them.
    final Uint8List secret;
    try {
      secret = rawSecret.isEmpty ? Uint8List(0) : Base32.decode(rawSecret);
    } on Base32FormatException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.addFailedTitle),
          content: Text(error.message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.actionClose),
            ),
          ],
        ),
      );
      return;
    }

    final existing = widget.editing;
    if (_isEditing && rawSecret.isEmpty) {
      // Keep the existing key and update only the metadata. Nothing touches the
      // secret store, so the account cannot be left without a usable key.
      final updated = existing!.copyWith(
        accountName: _accountName.text.trim(),
        issuer: _issuer.text.trim().isEmpty ? '' : _issuer.text.trim(),
        type: _type,
        algorithm: _algorithm,
        digits: _digits,
        period: int.tryParse(_period.text.trim()) ?? kDefaultPeriod,
        counter: int.tryParse(_counter.text.trim()) ?? 0,
      );
      final result = await importer.updateMetadata(updated);
      if (!mounted) return;
      setState(() => _saving = false);
      switch (result) {
        case ImportSucceeded():
          Navigator.of(context).pop(true);
        case ImportFailed(:final failure):
          await _showError(failure);
        case ImportDuplicate(:final existing):
          await _showError(
            InvalidSecretFailure(l10n.duplicateBody(existing.displayTitle)),
          );
      }
      return;
    }

    final outcome = await importer.importManual(
      accountName: _accountName.text,
      issuer: _issuer.text,
      secret: secret,
      type: _type,
      algorithm: _algorithm,
      digits: _digits,
      period: int.tryParse(_period.text.trim()) ?? kDefaultPeriod,
      counter: int.tryParse(_counter.text.trim()) ?? 0,
      replaceExistingId: existing?.id,
    );

    if (!mounted) {
      zero(secret);
      return;
    }
    setState(() => _saving = false);

    try {
      switch (outcome) {
        case ImportSucceeded():
          Navigator.of(context).pop(true);
        case ImportFailed(:final failure):
          await _showError(failure);
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
          if (addAnyway != true || !mounted) return;
          // Re-import with the duplicate check disabled, which is what the user
          // just asked for.
          final forced = await importer.importManual(
            accountName: _accountName.text,
            issuer: _issuer.text,
            secret: secret,
            type: _type,
            algorithm: _algorithm,
            digits: _digits,
            period: int.tryParse(_period.text.trim()) ?? kDefaultPeriod,
            counter: int.tryParse(_counter.text.trim()) ?? 0,
            force: true,
          );
          if (!mounted) return;
          if (forced is ImportSucceeded) {
            Navigator.of(context).pop(true);
          } else if (forced is ImportFailed) {
            await _showError(forced.failure);
          }
      }
    } finally {
      // The screen owns the buffer, and it is no longer needed once the flow
      // (including any duplicate retry) has finished.
      zero(secret);
    }
  }

  Future<void> _showError(Failure failure) {
    final l10n = AppLocalizations.of(context);
    return showDialog<void>(
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
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? l10n.editAccount : l10n.addManually),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: <Widget>[
            TextFormField(
              controller: _issuer,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l10n.fieldIssuer,
                helperText: l10n.fieldIssuerHelp,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _accountName,
              validator: _validateName,
              decoration: InputDecoration(
                labelText: l10n.fieldAccountName,
                helperText: l10n.fieldAccountNameHelp,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _secret,
              validator: _validateSecret,
              obscureText: !_revealSecret,
              autocorrect: false,
              enableSuggestions: false,
              // A secret is a credential: never offer to remember or store it.
              autofillHints: const <String>[],
              style: AppTypography.secretInput(theme),
              decoration: InputDecoration(
                labelText: l10n.fieldSecret,
                helperText: _isEditing
                    ? l10n.fieldSecretHelpEditing
                    : l10n.fieldSecretHelp,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _revealSecret = !_revealSecret),
                  icon: Icon(
                    _revealSecret
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  tooltip: _revealSecret ? l10n.actionHide : l10n.actionReveal,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _FieldLabel(text: l10n.fieldType),
            SegmentedButton<OtpType>(
              segments: <ButtonSegment<OtpType>>[
                ButtonSegment<OtpType>(
                  value: OtpType.totp,
                  label: Text(l10n.typeTimeBased),
                ),
                ButtonSegment<OtpType>(
                  value: OtpType.hotp,
                  label: Text(l10n.typeCounterBased),
                ),
              ],
              selected: <OtpType>{_type},
              onSelectionChanged: (selection) =>
                  setState(() => _type = selection.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 24),
            _FieldLabel(text: l10n.fieldAlgorithm),
            SegmentedButton<OtpAlgorithm>(
              segments: const <ButtonSegment<OtpAlgorithm>>[
                ButtonSegment<OtpAlgorithm>(
                  value: OtpAlgorithm.sha1,
                  label: Text('SHA1'),
                ),
                ButtonSegment<OtpAlgorithm>(
                  value: OtpAlgorithm.sha256,
                  label: Text('SHA256'),
                ),
                ButtonSegment<OtpAlgorithm>(
                  value: OtpAlgorithm.sha512,
                  label: Text('SHA512'),
                ),
              ],
              selected: <OtpAlgorithm>{_algorithm},
              onSelectionChanged: (selection) =>
                  setState(() => _algorithm = selection.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 24),
            _FieldLabel(text: l10n.fieldDigits),
            SegmentedButton<int>(
              segments: <ButtonSegment<int>>[
                for (final digits in const <int>[6, 7, 8])
                  ButtonSegment<int>(value: digits, label: Text('$digits')),
              ],
              selected: <int>{_digits},
              onSelectionChanged: (selection) =>
                  setState(() => _digits = selection.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 24),
            if (_type == OtpType.totp)
              TextFormField(
                controller: _period,
                validator: _validatePeriod,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: l10n.fieldPeriod,
                  helperText: l10n.fieldPeriodHelp,
                  border: const OutlineInputBorder(),
                ),
              )
            else
              TextFormField(
                controller: _counter,
                validator: _validateCounter,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: l10n.fieldCounter,
                  helperText: l10n.fieldCounterHelp,
                  border: const OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isEditing ? l10n.actionSave : l10n.addAccount),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: theme.textTheme.bodyLarge),
    );
  }
}
