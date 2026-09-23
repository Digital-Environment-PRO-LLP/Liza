import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/file_description.dart';
import 'test_client.dart';

// Страж реестра регрессии: ledger:RL-media-caption-reply-fallback (см.
// tests/registry/). LABA-2238.
//
// Инвариант: reply-фолбэк, который SDK дописывает в `body`/`formatted_body` при
// ответе (`room.sendEvent(inReplyTo:)`), НЕ считается подписью медиа. У медиа
// `body` == имя файла; при ответе SDK портит `body` цитатой → `body != filename`,
// и без снятия фолбэка имя файла `recording…ogg` ложно показывалось подписью под
// осциллограммой. `fileDescription`/`fileEditBody` — единственный гейт рендера
// подписи (audio_player, message.dart, download, context_menu).
//
// Критерии приёмки (LABA-2238): «имя файла НЕ показывать никогда» — ∀ по типам
// (voice/image), reply и не-reply, с реальной подписью и без.

late Client _client;
late Room _room;

Event _media({
  required String msgtype,
  required String body,
  String? filename,
  String? formattedBody,
  bool voice = false,
}) =>
    Event(
      eventId: '\$e-${body.hashCode}-${filename.hashCode}',
      senderId: '@u:example.invalid',
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
        if (voice) 'org.matrix.msc3245.voice': <String, Object?>{},
      },
      room: _room,
    );

// Reply-фолбэк ровно как строит SDK (matrix room.dart:1151-1178): body получает
// ведущую цитату «> …» + пустую строку, formatted_body оборачивается в mx-reply.
const _quoteBody = '> <@peer:example.invalid> привет\n\n';
// `body` события-ответа: ведущая цитата + хвост (имя файла или подпись).
String _replyBody(String tail) => '$_quoteBody$tail';
String _mxReplyWrap(String inner) =>
    '<mx-reply><blockquote>…</blockquote></mx-reply>$inner';

void main() {
  setUpAll(() async {
    _client = await prepareTestClient(loggedIn: true);
    _room = Room(id: '!r:example.invalid', client: _client);
  });

  group('fileDescription / fileEditBody — reply-fallback ≠ подпись'
      ' [ledger:RL-media-caption-reply-fallback]', () {
    // AC-1: reply-голосовое (главный кейс LABA-2238) — подписи НЕТ.
    test('AC:RL-media-caption-reply-fallback/1 — reply-voice → нет подписи', () {
      final e = _media(
        msgtype: MessageTypes.Audio,
        voice: true,
        filename: 'recording1785329047882163.ogg',
        body: _replyBody('recording1785329047882163.ogg'),
        formattedBody: _mxReplyWrap('recording1785329047882163.ogg'),
      );
      expect(e.fileDescription, isNull);
      expect(e.fileEditBody, isNull);
    });

    // AC-2: не-reply голосовое (контроль) — подписи нет и не было.
    test('AC:RL-media-caption-reply-fallback/2 — non-reply voice → нет подписи',
        () {
      final e = _media(
        msgtype: MessageTypes.Audio,
        voice: true,
        filename: 'recording1785329047882163.ogg',
        body: 'recording1785329047882163.ogg',
      );
      expect(e.fileDescription, isNull);
      expect(e.fileEditBody, isNull);
    });

    // AC-3: reply-картинка С реальной подписью — подпись сохранена (без цитаты).
    test('AC:RL-media-caption-reply-fallback/3 — reply-image с подписью → подпись',
        () {
      final e = _media(
        msgtype: MessageTypes.Image,
        filename: 'photo.jpg',
        body: _replyBody('смотри сюда'),
        formattedBody: _mxReplyWrap('смотри сюда'),
      );
      // fileEditBody (плейн) — очищенная от цитаты подпись, НЕ имя файла.
      expect(e.fileEditBody, 'смотри сюда');
      expect(e.fileEditBody, isNot(contains('photo.jpg')));
      expect(e.fileEditBody, isNot(startsWith('>')));
      // fileDescription отдаёт formatted_body (разметку) — mx-reply снимет
      // HtmlMessage при рендере; главное — оно НЕ null (гейт открыт) и содержит
      // подпись, а не только имя файла.
      expect(e.fileDescription, isNotNull);
      expect(e.fileDescription, contains('смотри сюда'));
    });

    // AC-4: reply-картинка БЕЗ подписи (только fallback) — подписи нет.
    test('AC:RL-media-caption-reply-fallback/4 — reply-image без подписи → нет',
        () {
      final e = _media(
        msgtype: MessageTypes.Image,
        filename: 'photo.jpg',
        body: _replyBody('photo.jpg'),
        formattedBody: _mxReplyWrap('photo.jpg'),
      );
      expect(e.fileDescription, isNull);
      expect(e.fileEditBody, isNull);
    });

    // AC-5: не-reply картинка с подписью (контроль) — подпись есть.
    test('AC:RL-media-caption-reply-fallback/5 — non-reply image с подписью → есть',
        () {
      final e = _media(
        msgtype: MessageTypes.Image,
        filename: 'photo.jpg',
        body: 'красивый вид',
      );
      expect(e.fileEditBody, 'красивый вид');
      expect(e.fileDescription, 'красивый вид');
    });

    // Край: медиа без поля `filename` (внешний/старый клиент) с подписью —
    // подпись сохраняем (не регрессируем LABA-2207).
    test('медиа без filename с подписью → подпись сохранена', () {
      final e = _media(
        msgtype: MessageTypes.Image,
        body: 'подпись без filename',
      );
      expect(e.fileDescription, 'подпись без filename');
      expect(e.fileEditBody, 'подпись без filename');
    });
  });
}
