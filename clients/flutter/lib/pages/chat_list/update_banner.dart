import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/version_gate_service.dart';
import 'package:liza/widgets/matrix.dart';

class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  static const _allowedSchemes = {'https', 'http', 'itms-beta'};

  Future<void> _open(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !_allowedSchemes.contains(uri.scheme)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<VersionGateResult>(
      valueListenable: Matrix.of(context).versionGateResult,
      builder: (context, result, _) {
        if (!result.needsUpdate) return const SizedBox.shrink();
        return Material(
          color: AppConfig.primaryColor,
          child: InkWell(
            onTap: () => _open(result.updateUrl),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.system_update,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        L10n.of(context).newVersionAvailable,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
