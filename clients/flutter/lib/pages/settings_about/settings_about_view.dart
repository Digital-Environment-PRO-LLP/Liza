import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/config/themes.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/widgets/layouts/max_width_body.dart';
import 'settings_about.dart';

class SettingsAboutView extends StatelessWidget {
  final SettingsAboutController controller;

  const SettingsAboutView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.about),
        automaticallyImplyLeading: !LizaThemes.isColumnMode(context),
        centerTitle: LizaThemes.isColumnMode(context),
      ),
      body: ListTileTheme(
        iconColor: theme.colorScheme.onSurface,
        child: MaxWidthBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(
                  controller.version.isEmpty
                      ? l10n.about
                      : controller.buildNumber.isEmpty
                      ? l10n.versionWithNumber(controller.version)
                      : l10n.versionWithBuildNumber(
                          controller.version,
                          controller.buildNumber,
                        ),
                ),
              ),
              Divider(color: theme.dividerColor),

              // Юридические документы: те же адреса, что и в сноске первого
              // экрана, — единый источник `AppConfig`.
              _ExternalTile(
                icon: Icons.privacy_tip_outlined,
                label: l10n.privacyPolicy,
                url: AppConfig.privacyUrl,
              ),
              _ExternalTile(
                icon: Icons.description_outlined,
                label: l10n.termsOfUse,
                url: AppConfig.termsUrl,
              ),
              Divider(color: theme.dividerColor),

              // Corresponding Source по AGPL-3.0: один публичный монорепозиторий.
              _ExternalTile(
                icon: Icons.code_outlined,
                label: l10n.aboutSourceCodeLiza,
                url: AppConfig.lizaSourceUrl,
              ),
              ListTile(
                leading: const Icon(Icons.balance_outlined),
                title: Text(l10n.license),
                subtitle: Text(l10n.aboutLicenseNotice),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Пункт, уводящий во внешний браузер: иконка `open_in_new` предупреждает об
/// этом (та же конвенция, что у юр-ссылки в «Настройках»).
class _ExternalTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Uri url;

  const _ExternalTile({
    required this.icon,
    required this.label,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.open_in_new_outlined),
      onTap: () => launchUrl(url),
    );
  }
}
