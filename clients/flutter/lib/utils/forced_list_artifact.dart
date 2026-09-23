import 'package:matrix/matrix.dart';

/// Markdown-парсер (в SDK и внешних Matrix-клиентах, и у XL) заворачивает
/// строку-маркер списка (`-`/`+`/`*`/`1.`) в `<ul>`/`<ol>` — и обычный «+»
/// приходит в `formatted_body` буллетом (жалоба Романа: «отправляю в чат "+", а
/// он меняет на булет списка»; LABA-2222: то же в ОТВЕТЕ и в многострочном списке
/// «плюсов/минусов»). Сама Лиза шлёт `parseMarkdown:false`, поэтому НЕ порождает
/// списков осознанно — любой навязанный `<ul>/<ol>` из маркеров трактуем как
/// литерал (паритет с Liza: «+» — это «+», а не буллет; список из «+»/«-» —
/// это строки с «+»/«-»). Настоящую разметку (жирный/курсив/ссылки) и списки БЕЗ
/// маркеров в плейн-`body` (осознанный HTML-список внешнего клиента) не трогаем.
final _singleListMarkerLine = RegExp(r'^([-+*]|\d+[.)])(\s|$)');
// Строка неупорядоченного списка «+ …»/«- …»/«* …» (или голый маркер).
final _unorderedMarkerLine = RegExp(r'^\s*[-+*](\s|$)');
final _htmlTag = RegExp(r'<[^>]+>');
final _listTag = RegExp(r'<(ul|ol|li)\b', caseSensitive: false);
final _mxReply =
    RegExp(r'<mx-reply>.*?</mx-reply>', caseSensitive: false, dotAll: true);
// Reply-фолбэк в плейн-`body`: ведущие строки-цитаты «> …» + пустая строка
// (так строит SDK `room.sendEvent` при `inReplyTo`).
final _replyFallback = RegExp(r'^(?:>[^\n]*\r?\n)+\r?\n?');

bool isForcedListArtifact(String? plainBody, String? formattedBody) {
  if (formattedBody == null) return false;
  // Подавляем ТОЛЬКО списочное форматирование — жирный/курсив/ссылки не трогаем.
  if (!_listTag.hasMatch(formattedBody)) return false;
  // Reply-случай (LABA-2222): наш «+»/«-» в ответе уходит как
  // `<mx-reply>…</mx-reply><ul><li></li></ul>`. Срезаем цитату, чтобы трактовать
  // тело как обычное сообщение. Если после среза списка не осталось — список был
  // ВНУТРИ цитируемого оригинала (чужой), это не наш артефакт.
  final fmt = formattedBody.replaceAll(_mxReply, '');
  if (!_listTag.hasMatch(fmt)) return false;
  // (B) вырожденный список без видимого текста («•» из markdown голого «+»/«-»,
  // где `li` пустой) — артефакт при любом body (в т.ч. если body обрезан в пусто).
  if (fmt.replaceAll(_htmlTag, '').trim().isEmpty) return true;
  // Плейн-body без reply-фолбэка.
  final body = (plainBody ?? '').replaceFirst(_replyFallback, '').trim();
  if (body.isEmpty) return false;
  final lines = body.split(RegExp(r'\r?\n'));
  // (A) одиночная строка-маркер («+», «+ да», «1. раз»).
  if (lines.length == 1) return _singleListMarkerLine.hasMatch(body);
  // (C) МНОГОСТРОЧНОЕ сообщение, где ХОТЯ БЫ ОДНА строка — неупорядоченный маркер
  // «+»/«-»/«*» (LABA-2222, жалоба Нади). Liza шлёт parseMarkdown:false и списков
  // осознанно не порождает — значит любой «+»/«-» в начале строки пользователь
  // набрал буквально (паритет с Liza). Ловим и СМЕШАННЫЕ сообщения
  // («+ п1\n+ п2\nЭто два плюса»), где раньше пояснительная строка ломала (C).
  // Нумерованные (`1.`) и HTML-списки БЕЗ маркеров в body (`<li>текст` при body
  // без «+»/«-») — не подпадают, сохраняются как список.
  return lines.any(_unorderedMarkerLine.hasMatch);
}

/// Снимает reply-фолбэк из плейн-`body` (ведущие строки-цитаты «> …» + пустая
/// строка-разделитель), который SDK дописывает при `inReplyTo`
/// (`room.sendEvent`). Возвращает строку без изменений, если фолбэка нет; `null`
/// → `null`. Нужно, чтобы у медиа не считать испорченный reply-fallback'ом `body`
/// подписью (LABA-2238).
///
/// ⚠️ Этот паттерн НАМЕРЕННО мягче SDK-варианта (`hideReply: true` →
/// `event.dart` `^>( \*)? <[^>]+>[^\n\r]+\r?\n(> [^\n]*\r?\n)*\r?\n`): не требует
/// ни `<@mxid>` в первой строке, ни пустой строки-разделителя — под LABA-2238, где
/// подпись приходила без разделителя. Обратная сторона: он съест и БУКВАЛЬНЫЙ
/// блок-квот пользователя («> он сказал…»). Поэтому для копирования ТЕКСТА
/// сообщения его применять НЕЛЬЗЯ — там строгий SDK-флаг `hideReply: true`
/// (`copy_media_eligibility.dart`), который такой блок-квот сохраняет.
String? stripReplyFallbackBody(String? body) =>
    body?.replaceFirst(_replyFallback, '');

/// HTML-двойник [stripReplyFallbackBody]: снимает `<mx-reply>…</mx-reply>`,
/// который SDK дописывает в `formatted_body` при `inReplyTo` (`room.sendEvent`).
///
/// Паттерн `_mxReply` — общий с [isForcedListArtifact]: пятая копия этой regex в
/// репозитории запрещена (SDK держит свои две, здесь — одна на оба направления).
String? stripReplyFallbackFormatted(String? formattedBody) =>
    formattedBody?.replaceAll(_mxReply, '');

/// Событие — форс-списочный артефакт («+»/«-» в навязанном `<ul>/<ol>`)?
///
/// Нужно для превью/уведомлений: `plaintextBody:true` и `removeMarkdown:true` в
/// SDK конвертируют такой formatted_body в буллет «•»
/// (`HtmlToText.convert('<ul><li></li></ul>') == '•'`, а `removeMarkdown` заново
/// гоняет body через `markdown()` — «+» → «•»). Гейт рендера пузыря
/// (`message_content`/`media_caption`) эти пути НЕ покрывает. Поэтому на КАЖДОМ
/// плейн-превью-сайте (список чатов, цитата, пуш, in-app-уведомление, поиск,
/// превью ссылки) при `true` этого геттера гасим ОБА флага — тогда берётся сырой
/// `body` («+»), а sender-префикс/hideReply/withSenderNamePrefix сохраняются.
/// Для настоящих (без маркеров) списков геттер = false → прежнее поведение.
extension ForcedListPreviewBody on Event {
  bool get isForcedListArtifactBody =>
      isForcedListArtifact(body, formattedText);
}
