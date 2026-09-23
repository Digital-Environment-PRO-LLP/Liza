import 'package:flutter/material.dart';

import 'package:liza/config/setting_keys.dart';
import 'package:liza/config/themes.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/platform_infos.dart';
import 'package:liza/widgets/layouts/max_width_body.dart';
import 'settings_chat.dart';

class SettingsChatView extends StatelessWidget {
  final SettingsChatController controller;
  const SettingsChatView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).chat),
        automaticallyImplyLeading: !LizaThemes.isColumnMode(context),
        centerTitle: LizaThemes.isColumnMode(context),
      ),
      body: ListTileTheme(
        iconColor: theme.textTheme.bodyLarge!.color,
        child: MaxWidthBody(
          child: Column(
            children: [
              if (PlatformInfos.isDesktop)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(L10n.of(context).downloadFolder),
                  subtitle: Text(
                    AppSettings.downloadDestinationPath.value.isEmpty
                        ? L10n.of(context).downloadFolderDefault
                        : AppSettings.downloadDestinationPath.value,
                  ),
                  onTap: controller.selectDownloadFolder,
                  trailing: AppSettings.downloadDestinationPath.value.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Icon(Icons.chevron_right_outlined),
                        )
                      : IconButton(
                          icon: const Icon(
                            Icons.settings_backup_restore_outlined,
                          ),
                          tooltip: L10n.of(context).downloadFolderDefault,
                          onPressed: controller.resetDownloadFolder,
                        ),
                ),
              // TODO: Hidden until VoIP is stable
              // Divider(color: theme.dividerColor),
              // ListTile(
              //   title: Text(
              //     L10n.of(context).calls,
              //     style: TextStyle(
              //       color: theme.colorScheme.secondary,
              //       fontWeight: FontWeight.bold,
              //     ),
              //   ),
              // ),
              // SettingsSwitchListTile.adaptive(
              //   title: L10n.of(context).experimentalVideoCalls,
              //   onChanged: (b) {
              //     Matrix.of(context).createVoipPlugin();
              //     return;
              //   },
              //   setting: AppSettings.experimentalVoip,
              // ),
            ],
          ),
        ),
      ),
    );
  }
}
