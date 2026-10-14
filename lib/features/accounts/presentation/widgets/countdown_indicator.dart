import 'package:flutter/material.dart';
import 'package:utaha_authenticator/core/theme/app_typography.dart';

/// The countdown ring shown beside a time-based code.
///
/// Renders as a ring that fills as the period elapses, with the seconds
/// remaining in the middle. It turns to the theme's error colour in the final
/// few seconds, which is the cue to wait rather than type the code.
class CountdownIndicator extends StatelessWidget {
  /// Creates a countdown indicator.
  const new({
    required this.progress,
    required this.secondsRemaining,
    required this.isExpiringSoon,
    this.size = 40,
    super.key,
  });

  /// Fraction of the period already elapsed, `0.0..1.0`.
  final double progress;

  /// Whole seconds until the code changes.
  final int secondsRemaining;

  /// Whether the code is in its final seconds and should be flagged.
  final bool isExpiringSoon;

  /// Diameter of the ring.
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colour = isExpiringSoon ? scheme.error : scheme.primary;

    return Semantics(
      // The ring is decorative; the number in the middle carries the meaning.
      label: '$secondsRemaining seconds until the code changes',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // The track stays visible so the ring reads as a countdown rather
            // than a spinner.
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: 1,
                strokeWidth: 3,
                color: scheme.surfaceContainerHighest,
              ),
            ),
            SizedBox.expand(
              child: CircularProgressIndicator(
                // `value` is the completed fraction, so passing the elapsed
                // fraction makes the ring fill as time runs out.
                value: progress,
                strokeWidth: 3,
                color: colour,
                // A hard edge at the tip reads more like a gauge than a blob.
                strokeCap: StrokeCap.square,
              ),
            ),
            Text(
              '$secondsRemaining',
              style: AppTypography.countdown(theme)
                  .copyWith(color: colour, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
