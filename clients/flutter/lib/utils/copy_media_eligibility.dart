import 'package:matrix/matrix.dart';

import 'package:liza/utils/file_description.dart';

/// Чистая логика гейтов «Скопировать изображение» и «Скопировать текст» на медиа
/// — вынесена ради тестируемости без живого Matrix Client (testWidgets с Client
/// виснет). Страж — `RL-copy-media-eligibility`.

/// Растровые типы, которые осмысленно копировать в системный image-буфер как
/// картинку (Liza «Copy Media»). Видео/аудио/файл/текст сюда НЕ входят —
/// они не ложатся в image-буфер и не вставляются картинкой в другое приложение.
const copyableMediaMessageTypes = {MessageTypes.Image, MessageTypes.Sticker};

/// Показывать ли пункт «Скопировать изображение».
///
/// [platformSupportsImageClipboard] — false на web/Linux, где
/// `Pasteboard.writeImage` не поддержан (Linux — тихий no-op; web — квирки
/// Clipboard API с протухающим после await жестом). Тогда пункт скрыт, а не
/// показан-но-неработающий.
bool canCopyMediaDecision({
  required String messageType,
  required bool isSent,
  required bool redacted,
  required bool platformSupportsImageClipboard,
}) =>
    platformSupportsImageClipboard &&
    isSent &&
    !redacted &&
    copyableMediaMessageTypes.contains(messageType);

/// Показывать ли пункт «Скопировать текст».
///
/// На медиа без подписи копировать нечего: `copyEvent` отдал бы generic-заглушку
/// (`calcLocalizedBodyFallback` = «Отправил картинку/файл»), а не осмысленный
/// текст — прячем (само изображение копируется пунктом «Скопировать
/// изображение»). На тексте и на медиа С подписью (`fileDescription`) —
/// показываем.
bool shouldOfferCopyText({required bool isMedia, required bool hasCaption}) =>
    !isMedia || hasCaption;

/// Текст, который «Скопировать текст» кладёт в буфер обмена для события.
///
/// На медиа С ПОДПИСЬЮ — сама подпись (`fileEditBody`: сырой plain `body` со
/// снятым reply-fallback), а НЕ SDK-заглушка `calcLocalizedBodyFallback`
/// («🖼️ Изображение от {автор}»), которая для m.image игнорирует `body`. Это
/// ровно тот текст, что рисует `media_caption.dart` под вложением (WYSIWYG). На
/// тексте и на медиа БЕЗ подписи (`fileEditBody == null`) — прежний
/// `calcLocalizedBodyFallback`.
///
/// [event] ДОЛЖЕН быть display-событием (`getDisplayEvent`), чтобы у
/// отредактированной подписи читалась новая версия (`m.new_content`).
///
/// [withSenderNamePrefix] (режим множественного выбора) добавляет к подписи
/// префикс «{Имя}: » — иначе строки медиа теряли бы автора, тогда как текстовые
/// сохраняют его через SDK. Формат префикса воспроизводит SDK
/// (`event.dart:920` — «Вы» для собственных сообщений). Страж —
/// `RL-copy-caption-text`.
///
/// `hideReply: true` — буфер обязан совпадать с пузырём, а пузырь рисует текст
/// через `calcUnlocalizedBody(hideReply: true)` (`message_content.dart`). Без
/// флага в буфер уезжал служебный matrix reply-fallback («> <@user> …»), которого
/// на экране нет вообще (жалоба 2026-09-08). Медиа-ветка ниже это уже держала
/// (`fileEditBody` со снятым fallback) — здесь достраиваем симметрию.
///
/// `plaintextBody`/`removeMarkdown` сознательно НЕ ставим (в отличие от
/// плейн-превью-сайтов): это флаги ПРЕВЬЮ, а не полной копии — `HtmlToText`
/// заменяет спойлеры на «█», теряет href внешних ссылок и требует парного гейта
/// `isForcedListArtifactBody` (иначе «+» в буфере станет «•», `RL-forced-list-artifact`).
String copyTextForEvent(
  Event event,
  MatrixLocalizations i18n, {
  bool withSenderNamePrefix = false,
}) {
  final caption = event.fileEditBody;
  if (caption == null) {
    return event.calcLocalizedBodyFallback(
      i18n,
      withSenderNamePrefix: withSenderNamePrefix,
      hideReply: true,
    );
  }
  if (!withSenderNamePrefix) return caption;
  final senderNameOrYou = event.senderId == event.room.client.userID
      ? i18n.you
      : event.senderFromMemoryOrFallback.calcDisplayname(i18n: i18n);
  return '$senderNameOrYou: $caption';
}
