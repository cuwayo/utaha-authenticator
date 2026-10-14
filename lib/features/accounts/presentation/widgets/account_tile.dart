import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:utaha_authenticator/core/theme/app_typography.dart';
import 'package:utaha_authenticator/domain/models/account.dart';
import 'package:utaha_authenticator/domain/models/display_preferences.dart';
import 'package:utaha_authenticator/domain/services/code_generator.dart';
import 'package:utaha_authenticator/features/accounts/presentation/widgets/countdown_indicator.dart';
import 'package:utaha_authenticator/features/accounts/presentation/widgets/issuer_avatar.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// One account and its current code.
///
/// Tapping the row copies the code; a long press opens the account's menu. Both
/// are exposed as semantics actions so the row is usable with a screen reader.
class AccountTile extends StatelessWidget {
  /// Creates an account tile.
  const new({
    required this.account,
    required this.code,
    required this.grouping,
    required this.tapToReveal,
    required this.compact,
    required this.onCopy,
    this.onLongPress,
    this.onAdvanceCounter,
    super.key,
  });

  /// The account being displayed.
  final Account account;

  /// The account's current code, or null when its secret is missing.
  final AccountCode? code;

  /// How the digits should be grouped for display.
  final CodeGrouping grouping;

  /// Whether the code starts hidden until tapped.
  final bool tapToReveal;

  /// Whether to use the tighter row layout.
  final bool compact;

  /// Called when the user asks to copy the code.
  final VoidCallback onCopy;

  /// Called on long press, to open the account's menu.
  final VoidCallback? onLongPress;

  /// Called when the user asks for the next counter-based code.
  final VoidCallback? onAdvanceCounter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final hasCode = code != null;
    final isExpiring = code?.isExpiringSoon ?? false;

    return Card.filled(
      child: Semantics(
        // One label for the whole row. Without this a screen reader reads the
        // issuer, the account name, the code and the countdown as four separate
        // announcements, which is unusable when moving through a list.
        label: _semanticLabel(l10n),
        button: hasCode,
        onTap: hasCode ? onCopy : null,
        onLongPress: onLongPress,
        excludeSemantics: true,
        child: InkWell(
          onTap: hasCode ? onCopy : null,
          onLongPress: onLongPress,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: compact ? 8 : 12,
            ),
            child: Row(
              children: <Widget>[
                IssuerAvatar(
                  label: account.issuer ?? account.accountName,
                  size: compact ? 32 : 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        account.displayTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (account.displaySubtitle.isNotEmpty)
                        Text(
                          account.displaySubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      if (hasCode)
                        _CodeText(
                          code: code!.code,
                          grouping: grouping,
                          tapToReveal: tapToReveal,
                          compact: compact,
                          isExpiring: isExpiring,
                          onReveal: onCopy,
                          semanticLabel: l10n.copyCodeTooltip,
                        )
                      else
                        Text(
                          l10n.accountMissingSecret,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Trailing(
                  account: account,
                  code: code,
                  onAdvanceCounter: onAdvanceCounter,
                  onCopy: onCopy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the single announcement for this row.
  ///
  /// The code is spelled out digit by digit, which is what makes it
  /// intelligible when spoken — "one two three" rather than "one hundred
  /// twenty-three".
  String _semanticLabel(AppLocalizations l10n) {
    final parts = <String>[account.displayTitle];
    if (account.displaySubtitle.isNotEmpty) {
      parts.add(account.displaySubtitle);
    }
    final current = code;
    if (current == null) {
      parts.add(l10n.accountMissingSecret);
    } else if (tapToReveal) {
      parts
        ..add(l10n.codeHidden)
        ..add(l10n.copyCodeTooltip);
    } else {
      parts.add(current.code.split('').join(' '));
      if (current.secondsRemaining != null) {
        parts.add(l10n.secondsRemaining(current.secondsRemaining!));
      }
    }
    return parts.join(', ');
  }
}

/// The code itself, optionally masked.
class _CodeText extends StatelessWidget {
  const new({
    required this.code,
    required this.grouping,
    required this.tapToReveal,
    required this.compact,
    required this.isExpiring,
    required this.onReveal,
    required this.semanticLabel,
  });

  final String code;
  final CodeGrouping grouping;
  final bool tapToReveal;
  final bool compact;
  final bool isExpiring;
  final VoidCallback onReveal;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final style = AppTypography.otpCode(
      theme,
      compact: compact,
    ).copyWith(color: isExpiring ? scheme.error : scheme.onSurface);

    if (!tapToReveal) {
      return Text(
        grouping.format(code),
        style: style,
        // The label reads the digits one at a time, which is what makes a code
        // intelligible when spoken.
        semanticsLabel: _spokenDigits(code),
      );
    }

    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onReveal,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(grouping.format(code), style: style),
              const SizedBox(width: 8),
              // A blur rather than asterisks: it reads as "hidden" instead of
              // "these are the digits".
              Icon(
                Icons.visibility_off_outlined,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders digits spaced so a screen reader announces them individually.
  static String _spokenDigits(String code) => code.split('').join(' ');
}

/// The countdown ring, or the "next code" control for counter-based accounts.
class _Trailing extends StatelessWidget {
  const new({
    required this.account,
    required this.code,
    required this.onAdvanceCounter,
    required this.onCopy,
  });

  final Account account;
  final AccountCode? code;
  final VoidCallback? onAdvanceCounter;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final current = code;

    if (current?.secondsRemaining != null && current?.progress != null) {
      return CountdownIndicator(
        progress: current!.progress!,
        secondsRemaining: current.secondsRemaining!,
        isExpiringSoon: current.isExpiringSoon,
      );
    }

    if (current == null) {
      return const Icon(Icons.error_outline);
    }

    // Counter-based: offer the explicit "next code" action. Advancing the
    // counter is a deliberate act because it must stay in step with the server.
    return IconButton.filledTonal(
      onPressed: () {
        unawaited(HapticFeedback.selectionClick());
        onAdvanceCounter?.call();
      },
      icon: const Icon(Icons.skip_next),
      tooltip: AppLocalizations.of(context).actionNextCode,
    );
  }
}
