import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:utaha_authenticator/app/providers.dart';
import 'package:utaha_authenticator/core/constants/app_constants.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// The first-run introduction: three short screens, then straight into the app.
///
/// Kept deliberately brief. Someone opening an authenticator usually wants a
/// code they already have, or to add one; a long tour before either is
/// frustrating. Skippable at every step.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// Creates the onboarding flow.
  const new({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();

  /// The page currently on screen.
  int _page = 0;

  /// The number of pages, kept in one place so the indicator cannot disagree.
  static const int _pageCount = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref
        .read(settingsControllerProvider.notifier)
        .mutate((current) => current.copyWith(onboardingCompleted: true));
  }

  void _next() {
    if (_page >= _pageCount - 1) {
      unawaited(_finish());
      return;
    }
    // `nextPage` is annotated `@awaitNotRequired`, so no `unawaited` wrapper.
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final pages = <_OnboardingPage>[
      _OnboardingPage(
        icon: Icons.lock_outline,
        title: l10n.onboardingOneTitle,
        body: l10n.onboardingOneBody,
      ),
      _OnboardingPage(
        icon: Icons.qr_code_scanner,
        title: l10n.onboardingTwoTitle,
        body: l10n.onboardingTwoBody,
      ),
      _OnboardingPage(
        icon: Icons.backup_outlined,
        title: l10n.onboardingThreeTitle,
        body: l10n.onboardingThreeBody,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: () => unawaited(_finish()),
                  child: Text(l10n.actionSkip),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) => pages[index],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (var i = 0; i < _pageCount; i++) _Dot(active: i == _page),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(
                    _page >= _pageCount - 1
                        ? l10n.onboardingGetStarted
                        : l10n.actionNext,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      // The dots are decorative; the button carries the meaning. Announced so a
      // screen-reader user knows where they are in the flow.
      bottomNavigationBar: Semantics(
        label: l10n.onboardingProgress(_page + 1, _pageCount),
        excludeSemantics: true,
        child: const SizedBox.shrink(),
      ),
    );
  }
}

/// One page of the introduction.
class _OnboardingPage extends StatelessWidget {
  const new({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 60, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 32),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A page indicator dot.
class _Dot extends StatelessWidget {
  const new({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? scheme.primary : scheme.outlineVariant,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// Decides whether to show the introduction or the app.
class OnboardingGate extends ConsumerWidget {
  /// Creates the gate around [child].
  const new({required this.child, super.key});

  /// The app content, shown once onboarding is done.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider).value;

    // Until settings load, show nothing rather than flashing the introduction
    // at someone who has already dismissed it.
    if (settings == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    if (settings.onboardingCompleted) return child;
    return const OnboardingScreen();
  }
}

/// The app name and tagline, used where a splash-like header is wanted.
class AppWordmark extends StatelessWidget {
  /// Creates the wordmark.
  const new({this.compact = false, super.key});

  /// Whether to use a smaller presentation.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          kAppDisplayName,
          style:
              (compact
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
