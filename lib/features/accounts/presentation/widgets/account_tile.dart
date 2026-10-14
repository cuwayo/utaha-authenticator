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
class AccountTile extends StatefulWidget {
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
  State<AccountTile> createState() => _AccountTileState();
}

class _AccountTileState extends State<AccountTile> {
  /// Whether the code has been revealed by a tap.
  ///
  /// Only meaningful when [AccountTile.tapToReveal] is on. Kept per tile, so
  /// revealing one account does not reveal the others.
  bool _revealed = false;

  /// Whether the code should currently be shown in the clear.
  bool get _showCode => !widget.tapToReveal || _revealed;

  @override
  void didUpdateWidget(AccountTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Hide the code again when it changes.
    //
    // The reveal is scoped to a single code: once the code rolls over there is
    // a new secret on screen, and leaving it uncovered would silently undo the
    // setting the user turned on. Comparing the code string rather than a timer
    // means this works for HOTP too, where there is no period.
    if (oldWidget.code?.code != widget.code?.code) {
      _revealed = false;
    }
  }

  /// Handles a tap on the row.
  ///
  /// With tap-to-reveal on, the first tap uncovers the code and only a second
  /// tap copies it — otherwise the setting would be defeated by the very
  /// gesture it asks for.
  void _handleTap() {
    if (widget.code == null) return;
    if (widget.tapToReveal && !_revealed) {
      setState(() => _revealed = true);
      return;
    }
    widget.onCopy();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    final code = widget.code;
    final hasCode = code != null;
    final isExpiring = code?.isExpiringSoon ?? false;

    return Card.filled(
      child: Semantics(
        // One label for the whole row. Without this a screen reader reads the
        // issuer, the account name, the code and the countdown as four separate
        // announcements, which is unusable when moving through a list.
        label: _semanticLabel(l10n),
        button: hasCode,
        onTap: hasCode ? _handleTap : null,
        onLongPress: widget.onLongPress,
        excludeSemantics: true,
        child: InkWell(
          onTap: hasCode ? _handleTap : null,
          onLongPress: widget.onLongPress,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: widget.compact ? 8 : 12,
            ),
            child: Row(
              children: <Widget>[
                IssuerAvatar(
                  label: widget.account.issuer ?? widget.account.accountName,
                  size: widget.compact ? 32 : 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        widget.account.displayTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.account.displaySubtitle.isNotEmpty)
                        Text(
                          widget.account.displaySubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      if (hasCode)
                        _CodeText(
                          code: code.code,
                          grouping: widget.grouping,
                          // The digits are passed only when they are meant to be
                          // visible. Masking has to happen here rather than in
                          // the widget's styling: a blurred or obscured Text
                          // still holds the real string, and a screen reader
                          // would happily read it out.
                          visible: _showCode,
                          compact: widget.compact,
                          isExpiring: isExpiring,
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
                  account: widget.account,
                  code: code,
                  onAdvanceCounter: widget.onAdvanceCounter,
                  onCopy: widget.onCopy,
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
    final parts = <String>[widget.account.displayTitle];
    if (widget.account.displaySubtitle.isNotEmpty) {
      parts.add(widget.account.displaySubtitle);
    }
    final current = widget.code;
    if (current == null) {
      parts.add(l10n.accountMissingSecret);
    } else if (!_showCode) {
      // The first tap reveals rather than copies, so the hint must say so —
      // announcing "copy code" would be a lie about what the gesture does.
      parts
        ..add(l10n.codeHidden)
        ..add(l10n.revealCodeHint);
    } else {
      parts.add(current.code.split('').join(' '));
      if (current.secondsRemaining != null) {
        parts.add(l10n.secondsRemaining(current.secondsRemaining!));
      }
    }
    return parts.join(', ');
  }
}

/// The code itself, masked until revealed when tap-to-reveal is on.
class _CodeText extends StatelessWidget {
  const new({
    required this.code,
    required this.grouping,
    required this.visible,
    required this.compact,
    required this.isExpiring,
  });

  /// The code digits. Only rendered when [visible] is true.
  final String code;

  /// How the digits should be grouped for display.
  final CodeGrouping grouping;

  /// Whether the digits may be shown.
  final bool visible;

  /// Whether to use the smaller type size.
  final bool compact;

  /// Whether the code is in its final seconds.
  final bool isExpiring;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final style = AppTypography.otpCode(
      theme,
      compact: compact,
    ).copyWith(color: isExpiring ? scheme.error : scheme.onSurface);

    if (!visible) {
      // One placeholder character per digit, so the row is the same width
      // hidden and revealed and the layout does not jump on the first tap.
      // The code's length is not a secret — it is visible in the account's own
      // settings — so mirroring it leaks nothing.
      //
      // The real digits are not rendered at all: not blurred, not coloured to
      // match the background, not clipped. Anything that still holds the string
      // can be read by a screen reader or recovered from a screenshot, which
      // would defeat the setting entirely.
      return Semantics(
        label: AppLocalizations.of(context).codeHidden,
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('•' * code.length, style: style),
            const SizedBox(width: 8),
            Icon(
              Icons.visibility_outlined,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      );
    }

    return Text(
      grouping.format(code),
      style: style,
      // The label reads the digits one at a time, which is what makes a code
      // intelligible when spoken.
      semanticsLabel: _spokenDigits(code),
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
