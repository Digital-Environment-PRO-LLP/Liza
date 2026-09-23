import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/miniapp_start_path.dart';
import 'package:liza/widgets/mxc_image.dart';
import 'package:liza/pages/chat/mini_app_web_view.dart';

/// Карточка запуска Mini App в чате.
///
/// Рендерит сообщение с `msgtype: "com.liza.miniapp.launch"` как карточку
/// с иконкой приложения, названием, опциональным превью и кнопкой запуска.
class MiniAppLaunchContent extends StatefulWidget {
  final Event event;
  final Color textColor;

  const MiniAppLaunchContent({
    required this.event,
    required this.textColor,
    super.key,
  });

  /// msgtype для launch-карточки Mini App.
  static const String msgType = 'com.liza.miniapp.launch';

  @override
  State<MiniAppLaunchContent> createState() => _MiniAppLaunchContentState();
}

class _MiniAppLaunchContentState extends State<MiniAppLaunchContent> {
  bool _loading = false;

  String get _appName {
    final name = widget.event.content.tryGet<String>('app_name');
    if (name != null && name.length <= 64) return name;
    return name?.substring(0, 64) ?? L10n.of(context).miniAppFallbackName;
  }

  String get _buttonText {
    final text = widget.event.content.tryGet<String>('button_text');
    if (text != null && text.length <= 32) return text;
    return text?.substring(0, 32) ?? L10n.of(context).chatInputOpen;
  }

  String? get _appUrl => widget.event.content.tryGet<String>('app_url');

  String? get _appId => widget.event.content.tryGet<String>('app_id');

  /// Deep-link на страницу mini App из launch-карточки (валидируем как границу).
  String get _appStartPath {
    final raw = widget.event.content.tryGet<String>('app_start_path');
    return (raw != null && isSafeStartPath(raw)) ? raw : '';
  }

  /// 'first_party' (наш доверенный app) или 'third_party' (сторонний — грузится
  /// изолированно через shell + sandboxed iframe). По умолчанию first_party.
  String get _appType =>
      widget.event.content.tryGet<String>('app_type') == 'third_party'
          ? 'third_party'
          : 'first_party';

  Uri? get _appIconMxc {
    final icon = widget.event.content.tryGet<String>('app_icon');
    return icon != null ? Uri.tryParse(icon) : null;
  }

  Uri? get _previewMxc {
    final preview = widget.event.content.tryGet<String>('app_preview');
    return preview != null ? Uri.tryParse(preview) : null;
  }

  bool get _isValidUrl {
    final url = _appUrl;
    if (url == null) return false;
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https';
  }

  Future<void> _openMiniApp() async {
    if (!_isValidUrl || _loading) return;

    setState(() => _loading = true);

    try {
      if (!mounted) return;
      await MiniAppWebView.open(
        context: context,
        appUrl: _appUrl!,
        appId: _appId ?? 'unknown',
        appName: _appName,
        room: widget.event.room,
        appType: _appType,
        appStartPath: _appStartPath,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      label: L10n.of(context).miniAppLaunchSemantics(_appName, _buttonText),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
            // Превью изображение (опционально)
            if (_previewMxc != null)
              ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppConfig.borderRadius),
                  topRight: Radius.circular(AppConfig.borderRadius),
                ),
                child: AspectRatio(
                  aspectRatio: 2,
                  child: MxcImage(
                    uri: _previewMxc,
                    event: widget.event,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            // Иконка + название
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  if (_appIconMxc != null) ...[
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: MxcImage(
                          uri: _appIconMxc,
                          event: widget.event,
                          fit: BoxFit.cover,
                          width: 40,
                          height: 40,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _appName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: widget.textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.event.body.isNotEmpty &&
                            widget.event.body != _appName)
                          Text(
                            widget.event.body,
                            style: TextStyle(
                              fontSize: 13,
                              color: widget.textColor.withAlpha(178),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Кнопка "Открыть"
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: FilledButton(
                onPressed: _isValidUrl ? _openMiniApp : null,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConfig.borderRadius / 2),
                  ),
                  minimumSize: const Size.fromHeight(44),
                ),
                child: _loading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        _buttonText,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
