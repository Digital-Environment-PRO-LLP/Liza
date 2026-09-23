import 'package:flutter/material.dart';

import 'package:liza/utils/platform_infos.dart';
import 'settings_about_view.dart';

/// Экран «О приложении»: юридическая информация и атрибуция форкнутых компонентов.
///
/// Заменяет системный `showAboutDialog`: Flutter принудительно добавляет в него
/// кнопку «Посмотреть лицензии» (`MaterialLocalizations.viewLicensesButtonLabel`),
/// убрать её из `showAboutDialog` нельзя, а по требованию она показываться не
/// должна. `PlatformInfos.showDialog` при этом жив — у него остались вызовы с
/// экрана входа.
class SettingsAbout extends StatefulWidget {
  const SettingsAbout({super.key});

  @override
  SettingsAboutController createState() => SettingsAboutController();
}

class SettingsAboutController extends State<SettingsAbout> {
  /// Версия приложения; до загрузки `PackageInfo` строка пуста.
  String version = '';

  /// Номер сборки (`+NNNN`); пуст, если платформа его не отдала.
  String buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final version = await PlatformInfos.getVersion();
    final buildNumber = await PlatformInfos.getBuildNumber();
    if (!mounted) return;
    setState(() {
      this.version = version;
      this.buildNumber = buildNumber;
    });
  }

  @override
  Widget build(BuildContext context) => SettingsAboutView(this);
}
