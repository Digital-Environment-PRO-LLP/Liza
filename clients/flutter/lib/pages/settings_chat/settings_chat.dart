import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';

import 'package:liza/config/setting_keys.dart';
import 'package:liza/l10n/l10n.dart';
import 'settings_chat_view.dart';

class SettingsChat extends StatefulWidget {
  const SettingsChat({super.key});

  @override
  SettingsChatController createState() => SettingsChatController();
}

class SettingsChatController extends State<SettingsChat> {
  Future<void> selectDownloadFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: L10n.of(context).downloadFolder,
    );
    if (path == null || !mounted) return;
    await AppSettings.downloadDestinationPath.setItem(path);
    if (mounted) setState(() {});
  }

  Future<void> resetDownloadFolder() async {
    await AppSettings.downloadDestinationPath.setItem('');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsChatView(this);
}
