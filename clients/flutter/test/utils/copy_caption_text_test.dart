import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/copy_media_eligibility.dart';
import 'package:liza/utils/file_description.dart';
import 'test_client.dart';

// Страж реестра регрессии: ledger:RL-copy-caption-text (см. tests/registry/).
//
// Инвариант: «Скопировать текст» на медиа С ПОДПИСЬЮ кладёт в буфер ИМЕННО текст
// подписи (`fileEditBody`), а НЕ SDK-заглушку `calcLocalizedBodyFallback`
// («🖼️ Изображение от {автор}»). Проверяем КОНТЕНТ копии на реальном `Event`
// через `copyTextForEvent` — единый источник для одиночного `copyEvent` и
// множественного `_getSelectedEventString` в `chat.dart`.

late Client _client;
late Room _room;

Event _media({
  required String msgtype,
  required String body,
  String? filename,
  String? formattedBody,
  String? senderId,
}) => Event(
  eventId: '\$e-${body.hashCode}-${filename.hashCode}',
  senderId: senderId ?? '@peer:example.invalid',
  originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
  type: EventTypes.Message,
  content: {
    'msgtype': msgtype,
    'body': body,
    if (filename != null) 'filename': filename,
    if (formattedBody != null) ...{
      'format': 'org.matrix.custom.html',
      'formatted_body': formattedBody,
    },
  },
  room: _room,
);

// Reply-фолбэк ровно как строит SDK: ведущая цитата «> …» + пустая строка.
String _replyBody(String tail) => '> <@peer:example.invalid> привет\n\n$tail';
String _mxReplyWrap(String inner) =>
    '<mx-reply><blockquote>…</blockquote></mx-reply>$inner';

const _caption =
    'С телефона в час по чайной ложке пытается воспроизвести и не смогает. '
    'Скачать не дает. С пк ни воспроизвести, ни скачать, при этом текст '
    'совсем не читается на экране';

void main() {
  late MatrixLocalizations i18n;

  setUpAll(() async {
    _client = await prepareTestClient(loggedIn: true);
    _room = Room(id: '!r:example.invalid', client: _client);
    i18n = MatrixDefaultLocalizations();
  });

  group('copyTextForEvent — контент «Скопировать текст»'
      ' [ledger:RL-copy-caption-text]', () {
    // AC-1: одиночная картинка с подписью → буфер == подпись, не заглушка.
    test('AC:RL-copy-caption-text/1 — image с подписью → подпись', () {
      final e = _media(
        msgtype: MessageTypes.Image,
        filename: 'photo.jpg',
        body: _caption,
      );
      expect(copyTextForEvent(e, i18n), _caption);
      expect(copyTextForEvent(e, i18n), isNot(contains('🖼')));
      expect(copyTextForEvent(e, i18n), isNot(contains('Изображение от')));
    });

    // AC-2: множественный выбор — подпись медиа НЕ теряет префикс отправителя
    // (как текстовые строки), обычный текст сохраняет прежний префикс.
    test('AC:RL-copy-caption-text/2 — multi: подпись с префиксом автора', () {
      final img = _media(
        msgtype: MessageTypes.Image,
        filename: 'photo.jpg',
        body: _caption,
        senderId: '@peer:example.invalid',
      );
      final text = _media(msgtype: MessageTypes.Text, body: 'просто текст');
      final imgLine = copyTextForEvent(img, i18n, withSenderNamePrefix: true);
      final textLine = copyTextForEvent(text, i18n, withSenderNamePrefix: true);
      // Медиа-подпись несёт автора и саму подпись (а не заглушку).
      expect(imgLine, endsWith(': $_caption'));
      expect(imgLine, isNot(contains('Изображение от')));
      // Текстовая строка тоже с префиксом «Имя: текст» — атрибуция согласована.
      expect(textLine, endsWith(': просто текст'));
      expect(imgLine.split(':').first, isNotEmpty);
    });

    // AC-3: медиа БЕЗ подписи → fileEditBody == null → прежняя заглушка
    // (пункт в меню и так скрыт гейтом shouldOfferCopyText). Не подпись.
    test('AC:RL-copy-caption-text/3 — image без подписи → заглушка, не пусто', () {
      final e = _media(
        msgtype: MessageTypes.Image,
        filename: 'photo.jpg',
        body: 'photo.jpg', // body == filename → подписи нет
      );
      expect(e.fileEditBody, isNull);
      // Гейт скрыл бы пункт; но если позвать напрямую — прежнее поведение.
      expect(copyTextForEvent(e, i18n), isNot(_caption));
      expect(
        shouldOfferCopyText(isMedia: true, hasCaption: e.fileEditBody != null),
        isFalse,
      );
    });

    // AC-4: обычный текст → поведение прежнее (регресс-якорь).
    test('AC:RL-copy-caption-text/4 — обычный текст не изменился', () {
      final e = _media(msgtype: MessageTypes.Text, body: 'привет мир');
      expect(copyTextForEvent(e, i18n), 'привет мир');
      expect(
        copyTextForEvent(e, i18n),
        e.calcLocalizedBodyFallback(i18n),
      );
    });

    // AC-5 (мультикейс ∀): video/audio/file с подписью → буфер == подпись.
    test('AC:RL-copy-caption-text/5 — video/audio/file с подписью → подпись', () {
      for (final type in [
        MessageTypes.Video,
        MessageTypes.Audio,
        MessageTypes.File,
      ]) {
        final e = _media(
          msgtype: type,
          filename: 'attachment.bin',
          body: 'подпись к $type',
        );
        expect(copyTextForEvent(e, i18n), 'подпись к $type', reason: type);
        expect(copyTextForEvent(e, i18n), isNot(contains('от ')), reason: type);
      }
    });

    // AC-6: reply-медиа с подписью → чистая подпись БЕЗ ведущей цитаты reply.
    test('AC:RL-copy-caption-text/6 — reply-image → подпись без цитаты', () {
      final e = _media(
        msgtype: MessageTypes.Image,
        filename: 'photo.jpg',
        body: _replyBody('смотри сюда'),
        formattedBody: _mxReplyWrap('смотри сюда'),
      );
      expect(copyTextForEvent(e, i18n), 'смотри сюда');
      expect(copyTextForEvent(e, i18n), isNot(startsWith('>')));
      expect(copyTextForEvent(e, i18n), isNot(contains('привет')));
    });

    // AC-8: подпись С форматированием (formatted_body) → в буфер уходит СЫРОЙ
    // plain body, а НЕ HTML. Это единственное место, где fileEditBody (plain) и
    // fileDescription (может вернуть formatted_body) расходятся — буфер обмена
    // HTML не принимает, копируем текст. (flutter-quality/Прокурор M-1.)
    test('AC:RL-copy-caption-text/8 — formatted подпись → plain, не HTML', () {
      final e = _media(
        msgtype: MessageTypes.Image,
        filename: 'photo.jpg',
        body: 'жирный текст',
        formattedBody: '<strong>жирный текст</strong>',
      );
      expect(copyTextForEvent(e, i18n), 'жирный текст');
      expect(copyTextForEvent(e, i18n), isNot(contains('<strong>')));
      expect(copyTextForEvent(e, i18n), isNot(contains('</strong>')));
    });

    // AC-9: множественный выбор СОБСТВЕННОГО медиа-с-подписью → префикс «Вы: »
    // (i18n.you), как SDK делает для собственных текстовых сообщений.
    test('AC:RL-copy-caption-text/9 — свой медиа в мультивыборе → префикс «Вы»',
        () {
      final e = _media(
        msgtype: MessageTypes.Image,
        filename: 'photo.jpg',
        body: 'моя подпись',
        senderId: _client.userID,
      );
      final line = copyTextForEvent(e, i18n, withSenderNamePrefix: true);
      expect(line, '${i18n.you}: моя подпись');
      expect(line, isNot(contains('Изображение от')));
    });
  });
}
