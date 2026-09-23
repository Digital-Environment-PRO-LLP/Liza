import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_linkify/flutter_linkify.dart' show LinkCallback;
import 'package:linkify/linkify.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/platform_infos.dart';
import 'package:liza/utils/url_launcher.dart';
import 'package:liza/widgets/adaptive_dialogs/show_modal_action_popup.dart';

/// Контекстное меню ССЫЛКИ (паритет с Liza, LABA-1965): правый клик
/// (desktop/web) или долгое нажатие (mobile) по ссылке показывают это меню
/// вместо контекстного меню всего сообщения. Действия — «Открыть» и
/// «Копировать ссылку». Вид адаптивный: шторка снизу на Android/Windows/Linux,
/// CupertinoActionSheet на iOS/macOS (через [showModalActionPopup]).
Future<void> showLinkContextMenu(BuildContext context, String url) async {
  final l10n = L10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final action = await showModalActionPopup<_LinkMenuAction>(
    context: context,
    title: url,
    cancelLabel: l10n.cancel,
    actions: [
      AdaptiveModalAction(
        value: _LinkMenuAction.open,
        label: l10n.open,
        icon: const Icon(Icons.open_in_new_outlined),
      ),
      AdaptiveModalAction(
        value: _LinkMenuAction.copy,
        label: l10n.copyLink,
        icon: const Icon(Icons.copy_outlined),
      ),
    ],
  );
  switch (action) {
    case _LinkMenuAction.open:
      if (context.mounted) UrlLauncher(context, url).launchUrl();
    case _LinkMenuAction.copy:
      await Clipboard.setData(ClipboardData(text: url));
      messenger.showSnackBar(SnackBar(content: Text(l10n.linkCopied)));
    case null:
      break;
  }
}

enum _LinkMenuAction { open, copy }

/// Строит инлайн-спаны текста с автоопределением ссылок (замена [LinkifySpan]),
/// где каждая ссылка по тапу открывается ([onOpen]), а по правому клику
/// (desktop) / долгому нажатию (mobile) показывает [showLinkContextMenu].
///
/// Распознаватели складываются в [recognizerPool] — вызывающая сторона обязана
/// звать [disposeRecognizers] при перестройке и в `dispose()` (иначе утечка:
/// спаны пересоздаются на каждый build ленты). Живя в самом спане, распознаватель
/// работает на любой глубине вложенных `Text.rich` — координатный hit-test не
/// нужен, Flutter сам маршрутизирует указатель по глифам.
List<InlineSpan> buildLinkifiedSpans({
  required BuildContext context,
  required String text,
  required TextStyle? textStyle,
  required TextStyle linkStyle,
  required LinkCallback onOpen,
  required List<GestureRecognizer> recognizerPool,
  LinkifyOptions options = const LinkifyOptions(humanize: false),
  // Тест-шов: выбор жеста меню. По умолчанию — по платформе (touch → long-press,
  // pointer → правый клик). В тестах на хосте `PlatformInfos.isMobile` всегда
  // false, поэтому мобильную ветку форсируем явно.
  bool? touchLongPress,
}) {
  final isTouch = touchLongPress ?? PlatformInfos.isMobile;
  final elements = linkify(text, options: options, linkifiers: defaultLinkifiers);
  return [
    for (final element in elements)
      if (element is LinkableElement)
        TextSpan(
          text: element.text,
          style: linkStyle,
          mouseCursor: SystemMouseCursors.click,
          recognizer: _buildLinkRecognizer(
            context: context,
            url: element.url,
            onOpen: () => onOpen(element),
            pool: recognizerPool,
            isTouch: isTouch,
          ),
        )
      else
        TextSpan(text: element.text, style: textStyle),
  ];
}

/// Освобождает и очищает пул распознавателей ссылок.
void disposeRecognizers(List<GestureRecognizer> pool) {
  for (final recognizer in pool) {
    recognizer.dispose();
  }
  pool.clear();
}

GestureRecognizer _buildLinkRecognizer({
  required BuildContext context,
  required String url,
  required VoidCallback onOpen,
  required List<GestureRecognizer> pool,
  required bool isTouch,
}) {
  void openMenu() {
    if (context.mounted) showLinkContextMenu(context, url);
  }

  final GestureRecognizer recognizer;
  if (isTouch) {
    // Мобайл: жеста secondary нет — нужен ОДИН распознаватель, различающий тап
    // (открыть) и удержание (меню). TapGestureRecognizer long-press не умеет,
    // поэтому — комбинированный [_TapOrLongPressGestureRecognizer].
    recognizer = _TapOrLongPressGestureRecognizer()
      ..onTapCallback = onOpen
      ..onLongPressStart = (_) => openMenu();
  } else {
    // Desktop/web: тап открывает, правый клик (secondaryTapDown) — меню.
    recognizer = TapGestureRecognizer()
      ..onTap = onOpen
      ..onSecondaryTapDown = (_) => openMenu();
  }
  pool.add(recognizer);
  return recognizer;
}

/// Комбинированный распознаватель для ссылки в тексте на mobile: короткий тап
/// (отпуск до порога long-press) открывает ссылку, удержание — меню. Один слот
/// `TextSpan.recognizer` не вмещает два штатных распознавателя, поэтому tap
/// детектируем поверх [LongPressGestureRecognizer]. Протяжка (скролл) сбрасывает
/// распознаватель по slop до PointerUp — long-press и тап не срабатывают.
class _TapOrLongPressGestureRecognizer extends LongPressGestureRecognizer {
  VoidCallback? onTapCallback;
  bool _longPressFired = false;

  @override
  void didExceedDeadline() {
    _longPressFired = true;
    super.didExceedDeadline();
  }

  @override
  void handlePrimaryPointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      _longPressFired = false;
    } else if (event is PointerUpEvent && !_longPressFired) {
      // Отпуск до порога long-press и в пределах slop — это тап: открыть ссылку.
      onTapCallback?.call();
    }
    super.handlePrimaryPointer(event);
  }
}
