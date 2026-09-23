import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/config/setting_keys.dart';
import 'package:liza/utils/file_description.dart';
import 'package:liza/utils/url_launcher.dart';
import 'html_message.dart';
import 'linkified_span.dart';

/// HTML-подпись медиа, если у события есть разметка
/// (`format=org.matrix.custom.html` + непустой `formatted_body`), иначе null.
/// Вынесено чистой функцией — чтобы покрыть решение юнитом без рендера
/// (рендер MediaCaption проверяется на устройстве).
String? captionFormattedHtml(Map<String, Object?> content) {
  final formatted = content['formatted_body'];
  if (content['format'] == 'org.matrix.custom.html' &&
      formatted is String &&
      formatted.isNotEmpty &&
      !isForcedListArtifact(content['body'] as String?, formatted)) {
    return formatted;
  }
  return null;
}

/// Подпись под медиа (image/video/file/audio).
///
/// Отправитель (XL и любой Matrix-клиент) может прислать разметку в
/// `formatted_body` (<strong>/<em>/<a>/…). Раньше подпись рисовалась через
/// [Linkify] как ПЛЕЙН-текст — и HTML-теги были видны сырыми (LABA-2207: XL
/// шлёт `<strong>жирный</strong>` в подписи к картинке). Теперь: если у события
/// есть `format=org.matrix.custom.html` — рендерим подпись как HTML через
/// [HtmlMessage] (тот же путь, что у обычного текста в `message_content.dart`).
/// Плейн-подпись без разметки — линкифицируется своим билдером с меню ссылки
/// (LABA-1965: правый клик/долгое нажатие по ссылке → меню ссылки).
class MediaCaption extends StatefulWidget {
  final Event event;
  final Color textColor;
  final Color linkColor;

  /// Время сообщения (Liza-стиль) — встраивается хвостовым inline-span в
  /// конец подписи, чтобы стоять на ТОЙ ЖЕ строке, а не отдельной строкой снизу
  /// (иначе `Align`-футер раздувал пузырь; баг «Перемудрили. Плохо это» —
  /// подпись к m.image).
  final InlineSpan? trailingSpan;

  const MediaCaption({
    super.key,
    required this.event,
    required this.textColor,
    required this.linkColor,
    this.trailingSpan,
  });

  @override
  State<MediaCaption> createState() => _MediaCaptionState();
}

class _MediaCaptionState extends State<MediaCaption> {
  /// Пул распознавателей ссылок плейн-подписи — освобождаем при перестройке и
  /// в dispose (иначе утечка на горячем пути ленты).
  final List<GestureRecognizer> _linkRecognizers = [];

  @override
  void dispose() {
    disposeRecognizers(_linkRecognizers);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Освобождаем распознаватели прошлого кадра В НАЧАЛЕ build (до раннего
    // return HTML-пути): иначе при смене подписи «плейн → HTML» (напр. правка
    // медиа добавила formatted_body) плейн-пул завис бы до dispose(). Известное
    // ограничение: ре-билд во время удержания пальца (до порога long-press)
    // синхронно отклонит активный жест — меню может не открыться с первого раза.
    disposeRecognizers(_linkRecognizers);
    final event = widget.event;
    final textColor = widget.textColor;
    final fontSize =
        AppSettings.fontSizeFactor.value * AppConfig.messageFontSize;
    final linkStyle = TextStyle(
      color: widget.linkColor,
      fontSize: fontSize,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor,
    );

    final formatted = captionFormattedHtml(event.content);
    if (formatted != null) {
      return HtmlMessage(
        html: formatted,
        room: event.room,
        textColor: textColor,
        fontSize: fontSize,
        linkStyle: linkStyle,
        trailingSpan: widget.trailingSpan,
        onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
        eventId: event.eventId,
      );
    }

    // Плейн-подпись без разметки: Text.rich со ссылками (тап открывает, правый
    // клик/долгое нажатие — меню ссылки) + inline-временем.
    final timeSpan = widget.trailingSpan;
    final caption = event.fileEditBody ?? event.fileDescription ?? '';
    // Чистый ambient decoration:none — иначе под пузырём без Material-предка
    // текст наследует жёлтую _errorTextStyle (см. html_message.dart build).
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: Text.rich(
        TextSpan(
          children: [
            ...buildLinkifiedSpans(
              context: context,
              text: caption,
              textStyle: TextStyle(
                color: textColor,
                fontSize: fontSize,
                decoration: TextDecoration.none,
              ),
              linkStyle: linkStyle,
              onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
              recognizerPool: _linkRecognizers,
            ),
            if (timeSpan != null) timeSpan,
          ],
        ),
        textScaler: MediaQuery.textScalerOf(context),
      ),
    );
  }
}
