import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:utaha_authenticator/core/constants/app_constants.dart';
import 'package:utaha_authenticator/l10n/app_localizations.dart';

/// Shows the app name, version, licence and links to the repository.
class AboutScreen extends StatelessWidget {
  /// Creates the about screen.
  const new({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.errorGenericBody)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: <Widget>[
          Center(
            child: Column(
              children: <Widget>[
                // The launcher icon doubles as the About logo.
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 96,
                    height: 96,
                    // A missing asset must not break the About page, so the
                    // name below still identifies the app.
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        Icons.pin,
                        size: 48,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  kAppDisplayName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.appTagline,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                // Resolved asynchronously; the version is informational, so a
                // brief placeholder is better than blocking the page.
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final version = snapshot.data?.version;
                    return Text(
                      version == null ? '' : l10n.aboutVersion(version),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Icon(Icons.wifi_off, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.aboutOffline,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(l10n.aboutSourceCode),
            subtitle: const Text(kAppRepositoryUrl),
            onTap: () => _open(context, kAppRepositoryUrl),
          ),
          ListTile(
            leading: const Icon(Icons.public),
            title: Text(l10n.aboutWebsite),
            subtitle: const Text(kAppWebsite),
            onTap: () => _open(context, kAppWebsite),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.aboutViewLicenses),
            onTap: () => showLicensePage(
              context: context,
              applicationName: kAppDisplayName,
              applicationLegalese: 'Released under the MIT License.',
            ),
          ),
        ],
      ),
    );
  }
}
