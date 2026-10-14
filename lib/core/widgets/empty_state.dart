import 'package:flutter/material.dart';

/// A friendly, illustrated placeholder shown when a list has nothing in it.
///
/// Both the empty account list and an empty search result use this, so the two
/// states stay visually consistent.
class EmptyState extends StatelessWidget {
  /// Creates an empty state.
  const new({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    super.key,
  });

  /// Large glyph shown above the title.
  final IconData icon;

  /// Short heading.
  final String title;

  /// One or two sentences explaining what to do next.
  final String body;

  /// Optional call to action.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // At large font scales the text alone can exceed the viewport. Shrinking
    // the decorative badge keeps the message visible instead of pushing it off
    // screen, and the whole thing scrolls as a final fallback.
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final badgeSize = textScale >= 1.5 ? 72.0 : 112.0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // A tonal circle keeps the icon legible in both light and dark
              // schemes without relying on a bitmap asset.
              Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: badgeSize / 2,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...<Widget>[
                const SizedBox(height: 24),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
