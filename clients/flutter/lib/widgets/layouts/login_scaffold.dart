import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/config/themes.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/platform_infos.dart';

class LoginScaffold extends StatelessWidget {
  final Widget body;
  final AppBar? appBar;
  final bool enforceMobileMode;

  const LoginScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.enforceMobileMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isMobileMode =
        enforceMobileMode || !LizaThemes.isColumnMode(context);
    if (isMobileMode) {
      return Scaffold(
        key: const Key('LoginScaffold'),
        appBar: appBar,
        body: SafeArea(child: body),
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.surfaceContainerLow,
            theme.colorScheme.surfaceContainer,
            theme.colorScheme.surfaceContainerHighest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Material(
                  borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                  clipBehavior: Clip.hardEdge,
                  elevation: theme.appBarTheme.scrolledUnderElevation ?? 4,
                  shadowColor: theme.appBarTheme.shadowColor,
                  child: ConstrainedBox(
                    // Потолок 800 — «просторный» размер карточки, но на
                    // невысоком мониторе окно короче, и жёсткие 800 давали
                    // карточку выше вьюпорта: низ (кнопка и юр-сноска)
                    // оказывался за краем. Берём минимум из 800 и реально
                    // доступной высоты — содержимое внутри ужимается само
                    // (см. density в HomeserverPickerView).
                    constraints: isMobileMode
                        ? const BoxConstraints()
                        : BoxConstraints(
                            maxWidth: 480,
                            maxHeight: math.min(
                              800,
                              MediaQuery.sizeOf(context).height - 32,
                            ),
                          ),
                    child: Scaffold(
                      key: const Key('LoginScaffold'),
                      appBar: appBar,
                      body: SafeArea(child: body),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // _PrivacyButtons hidden intentionally
          // const _PrivacyButtons(mainAxisAlignment: .center),
        ],
      ),
    );
  }
}

// ignore: unused_element — временно отключён (см. закомментированный вызов выше)
class _PrivacyButtons extends StatelessWidget {
  final MainAxisAlignment mainAxisAlignment;
  const _PrivacyButtons({required this.mainAxisAlignment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shadowTextStyle = TextStyle(color: theme.colorScheme.secondary);
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: mainAxisAlignment,
          children: [
            TextButton(
              onPressed: () => launchUrlString(AppConfig.website),
              child: Text(L10n.of(context).website, style: shadowTextStyle),
            ),
            TextButton(
              onPressed: () => launchUrlString(AppConfig.supportUrl),
              child: Text(L10n.of(context).help, style: shadowTextStyle),
            ),
            TextButton(
              onPressed: () => launchUrl(AppConfig.privacyUrl),
              child: Text(L10n.of(context).privacy, style: shadowTextStyle),
            ),
            TextButton(
              onPressed: () => PlatformInfos.showDialog(context),
              child: Text(L10n.of(context).about, style: shadowTextStyle),
            ),
          ],
        ),
      ),
    );
  }
}
