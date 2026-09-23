import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:image/image.dart';
import 'package:matrix/matrix.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:qr_image/qr_image.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/liza_share.dart';
import 'package:liza/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:liza/widgets/future_loading_dialog.dart';
import '../config/themes.dart';

/// Ссылка, которую кодирует QR и копирует/шарит/сохраняет диалог.
///
/// Единственное место сборки URL — используется и для QR-кода, и для
/// подписи под ним (`qrDisplayText`), чтобы не завести две независимые
/// копии одного и того же выражения.
String qrLink({required String content, String? inviteLink}) =>
    inviteLink ?? 'https://matrix.to/#/$content';

/// Что показать подписью под QR-кодом.
///
/// Показываем ровно то, что копируется и зашито в QR-код: раньше подпись
/// давала сырой `#alias:server`, а кнопка копировала matrix.to-ссылку.
/// Подпись всегда равна [qrLink], чтобы показанное и скопированное не
/// расходились.
String qrDisplayText({required String content, String? inviteLink}) =>
    qrLink(content: content, inviteLink: inviteLink);

Future<void> showQrCodeViewer(
  BuildContext context,
  String content, {
  String? inviteLink,
}) =>
    showDialog(
      context: context,
      builder: (context) =>
          QrCodeViewer(content: content, inviteLink: inviteLink),
    );

class QrCodeViewer extends StatelessWidget {
  final String content;
  final String? inviteLink;

  const QrCodeViewer({required this.content, this.inviteLink, super.key});

  String get _link => qrLink(content: content, inviteLink: inviteLink);

  void _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.of(context).copiedToClipboard)),
    );
  }

  void _save(BuildContext context) async {
    final link = _link;
    final imageResult = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final image = QRImage(link, size: 256, radius: 1).generate();
        return compute(encodePng, image);
      },
    );
    final bytes = imageResult.result;
    if (bytes == null) return;
    if (!context.mounted) return;

    MatrixImageFile(
      bytes: bytes,
      name: 'QR_Code_$content.png',
      mimeType: 'image/png',
    ).save(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _link;
    return Scaffold(
      backgroundColor: Colors.black.withAlpha(128),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withAlpha(128),
          ),
          icon: const Icon(Icons.close),
          onPressed: Navigator.of(context).pop,
          color: Colors.white,
          tooltip: L10n.of(context).close,
        ),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withAlpha(128),
            ),
            icon: Icon(Icons.adaptive.share_outlined),
            onPressed: () => LizaShare.share(link, context),
            color: Colors.white,
            tooltip: L10n.of(context).share,
          ),
          const SizedBox(width: 8),
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withAlpha(128),
            ),
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _save(context),
            color: Colors.white,
            tooltip: L10n.of(context).downloadFile,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(32.0),
          padding: const EdgeInsets.all(32.0),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          ),
          child: Column(
            mainAxisSize: .min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: LizaThemes.columnWidth,
                ),
                child: PrettyQrView.data(
                  data: link,
                  decoration: PrettyQrDecoration(
                    shape: PrettyQrSmoothSymbol(
                      roundFactor: 1,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8.0),
              SelectableText(
                qrDisplayText(content: content, inviteLink: inviteLink),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12.0),
              OutlinedButton.icon(
                onPressed: () => _copyLink(context),
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: Text(L10n.of(context).copyLink),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  side: BorderSide(
                    color: theme.colorScheme.onPrimaryContainer.withAlpha(128),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
