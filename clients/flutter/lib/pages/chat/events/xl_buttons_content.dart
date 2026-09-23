import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/config/setting_keys.dart';
import 'package:liza/pages/chat/external_link_web_view.dart';
import 'package:liza/utils/url_launcher.dart';
import 'package:liza/widgets/matrix.dart';
import 'html_message.dart';

class _XlButton {
  final String index;
  final String title;
  final String? url;
  const _XlButton({required this.index, required this.title, this.url});
}

/// Открывает url-кнопку бота ВНУТРИ мессенджера (встроенный `ExternalLinkWebView`)
/// для `https`, иначе — внешним лаунчером (fallback).
///
/// Вынесено top-level, чтобы страж проверял РЕАЛЬНУЮ навигацию (а не реплику
/// логики): `ledger:RL-xl-button-url-inapp-webview`.
/// non-https (`matrix.to`/deep-link/`geo:`/`tel:`/`mailto:`/кастом-схемы)
/// обслуживает `UrlLauncher` — `ExternalLinkWebView` пускает только `https` и на
/// прочих схемах молча ничего не делает, иначе кнопка стала бы мёртвой.
Future<void> openXlButtonUrl(BuildContext context, String url) async {
  if (isSafeHttpsUrl(url)) {
    // closeOnPaymentReturn: url-кнопка бота (в т.ч. «Оплатить» с формой Prodamus)
    // после оплаты редиректит на наш urlSuccess/urlReturn. Закрываем webview на
    // этом редиректе, чтобы вернуть пользователя в чат бота, а не показать SPA
    // магазина («Liza Wall»). Для НЕ-платёжных ссылок безвредно (на /payment/*
    // они не ходят).
    await ExternalLinkWebView.open(
      context: context,
      url: url,
      closeOnPaymentReturn: true,
    );
  } else {
    UrlLauncher(context, url).launchUrl();
  }
}

/// Кнопки XL под текстовым сообщением бота (нативный рендер Liza reply_markup).
///
/// Сообщение `m.text` от бота с полем `com.liza.xl_buttons` (список
/// `{index, title, url}`) и чистым текстом в `com.liza.xl_text_html`.
/// Кнопка-ссылка (есть `url`) открывает URL; кнопка-действие отправляет свой
/// номер как обычный текст — эмулятор `liza-bot-api` матчит его на `callback_query`
/// и двигает сценарий XL (callback-суррогат).
///
/// Интерактивна (рисует кнопки) ТОЛЬКО когда отправитель — бот (роль `ai`):
/// доверяем управляющие кнопки лишь доверенному отправителю. Иначе — обычный
/// текст (старые клиенты и так рендерят нумерованный список из `formatted_body`).
class XlButtonsContent extends StatefulWidget {
  final Event event;
  final Color textColor;
  final Color linkColor;

  const XlButtonsContent({
    required this.event,
    required this.textColor,
    required this.linkColor,
    super.key,
  });

  /// Поле контента со структурированными кнопками (клиентский рендер).
  static const String contentKey = 'com.liza.xl_buttons';

  /// Поле с чистым HTML текста (без нумерованного списка-фолбэка).
  static const String textHtmlKey = 'com.liza.xl_text_html';

  @override
  State<XlButtonsContent> createState() => _XlButtonsContentState();
}

class _XlButtonsContentState extends State<XlButtonsContent> {
  /// Debounce: пока обрабатываем тап (открываем webview / шлём callback), второй
  /// тап игнорируем — иначе двойной тап по url-кнопке кладёт ДВА webview в стек
  /// навигации (внешний браузер так не стекался). Аналог `_pending` в
  /// `MiniAppChoiceContent`.
  bool _busy = false;

  List<_XlButton> _parseButtons() {
    final raw = widget.event.content[XlButtonsContent.contentKey];
    final out = <_XlButton>[];
    if (raw is List) {
      for (final b in raw) {
        if (b is! Map) continue;
        final title = b['title']?.toString() ?? '';
        if (title.isEmpty) continue;
        final url = b['url']?.toString();
        out.add(
          _XlButton(
            index: b['index']?.toString() ?? '',
            title: title,
            url: (url != null && url.isNotEmpty) ? url : null,
          ),
        );
      }
    }
    return out;
  }

  Future<void> _onTap(_XlButton b) async {
    if (_busy) return;
    _busy = true;
    try {
      if (b.url != null) {
        // Кнопка-ссылка бота (в т.ч. «Оплатить» с готовым payment_url формы
        // Prodamus) открывается ВНУТРИ мессенджера — встроенный webview вместо
        // системного браузера (Liza-паритет для inline url-кнопок; кнопки
        // видны только у доверенных ботов роли `ai`).
        await openXlButtonUrl(context, b.url!);
        return;
      }
      // Кнопка-действие: отправляем её номер → callback-суррогат эмулятора.
      try {
        await widget.event.room.sendTextEvent(b.index, parseCommands: false);
      } catch (e) {
        Logs().e('[XlButtons] callback send failed: $e');
      }
    } finally {
      _busy = false;
    }
  }

  String _textHtml() {
    final html = widget.event.content[XlButtonsContent.textHtmlKey]?.toString();
    if (html != null && html.isNotEmpty) return html;
    // Фолбэк: экранированное тело (HtmlMessage парсит HTML).
    return widget.event.body
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', '<br>');
  }

  @override
  Widget build(BuildContext context) {
    final fontSize =
        AppSettings.fontSizeFactor.value * AppConfig.messageFontSize;

    final textWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: HtmlMessage(
        html: _textHtml(),
        room: widget.event.room,
        textColor: widget.textColor,
        fontSize: fontSize,
        linkStyle: TextStyle(
          color: widget.linkColor,
          fontSize: fontSize,
          decoration: TextDecoration.underline,
          decorationColor: widget.linkColor,
        ),
        onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
        eventId: widget.event.eventId,
      ),
    );

    final buttons = _parseButtons();
    final senderIsBot = Matrix.of(context).isAiUser(widget.event.senderId);
    if (!senderIsBot || buttons.isEmpty) {
      return textWidget;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        textWidget,
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in buttons)
                OutlinedButton(
                  onPressed: () => _onTap(b),
                  child: Text(b.title),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
