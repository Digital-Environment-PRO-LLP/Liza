// Остаточные баги форс-списка (комиссия 2026-07-24): гейт рендера пузыря
// (isForcedListArtifact в message_content/media_caption) НЕ покрывал плейн-превью
// пути — список чатов, цитата, пуш, in-app-уведомление, поиск, превью ссылки.
// Там текст берётся через calcLocalizedBody(plaintextBody:true, removeMarkdown:true),
// а SDK конвертирует навязанный <ul><li></li></ul> из «+»/«-» в буллет «•»
// (HtmlToText='•', а removeMarkdown заново гоняет body через markdown()). Фикс —
// геттер Event.isForcedListArtifactBody: на превью-сайтах гасим ОБА флага.
//
// ledger:RL-forced-list-artifact

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/forced_list_artifact.dart';

import '../../utils/test_client.dart';

Event _event(Client client, Map<String, Object?> content) => Event(
      type: 'm.room.message',
      eventId: '\$evt:example.invalid',
      senderId: '@alice:example.invalid',
      originServerTs: DateTime.now(),
      room: Room(id: '!r:example.invalid', client: client),
      content: content,
    );

const _bulletHtml = '<ul>\n<li></li>\n</ul>\n';
const _i18n = MatrixDefaultLocalizations();

void main() {
  late Client client;
  setUpAll(() async {
    client = await prepareTestClient(loggedIn: true);
  });

  group('Event.isForcedListArtifactBody', () {
    test('«+» с навязанным списком → true', () {
      final e = _event(client, {
        'msgtype': 'm.text',
        'body': '+',
        'format': 'org.matrix.custom.html',
        'formatted_body': _bulletHtml,
      });
      expect(e.isForcedListArtifactBody, isTrue);
    });

    test('многострочный список из маркеров «-» → true (LABA-2222)', () {
      final e = _event(client, {
        'msgtype': 'm.text',
        'body': '- один\n- два',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<ul><li>один</li><li>два</li></ul>',
      });
      expect(e.isForcedListArtifactBody, isTrue);
    });

    test('HTML-список без маркеров в body → false (осознанный список)', () {
      final e = _event(client, {
        'msgtype': 'm.text',
        'body': 'один\nдва',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<ul><li>один</li><li>два</li></ul>',
      });
      expect(e.isForcedListArtifactBody, isFalse);
    });

    test('обычный текст без formatted_body → false', () {
      final e = _event(client, {'msgtype': 'm.text', 'body': 'привет'});
      expect(e.isForcedListArtifactBody, isFalse);
    });
  });

  group('превью-путь: подавление «•» через оба флага', () {
    // Регресс, который ловим: с plaintextBody:true / removeMarkdown:true SDK
    // отдаёт «•» для «+». Гейт-логика превью-сайтов (!isForcedListArtifactBody)
    // обязана вернуть «+».
    test('«+» → «+», а НЕ «•» (как на превью-сайтах)', () {
      final e = _event(client, {
        'msgtype': 'm.text',
        'body': '+',
        'format': 'org.matrix.custom.html',
        'formatted_body': _bulletHtml,
      });
      final gate = !e.isForcedListArtifactBody;
      final preview = e.calcLocalizedBodyFallback(
        _i18n,
        hideReply: true,
        hideEdit: true,
        plaintextBody: gate,
        removeMarkdown: gate,
      );
      expect(preview, '+');
      expect(preview, isNot(contains('•')));
    });

    test('СТАРОЕ поведение (оба флага true) действительно давало «•»', () {
      // Документируем корень: без гейта превью показывало буллет.
      final e = _event(client, {
        'msgtype': 'm.text',
        'body': '+',
        'format': 'org.matrix.custom.html',
        'formatted_body': _bulletHtml,
      });
      final buggy = e.calcLocalizedBodyFallback(
        _i18n,
        plaintextBody: true,
        removeMarkdown: true,
      );
      expect(buggy, '•');
    });

    test('многострочный «- один / - два» в превью → литерал, без «•»', () {
      // LABA-2222: список из маркеров тоже литерал.
      final e = _event(client, {
        'msgtype': 'm.text',
        'body': '- один\n- два',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<ul><li>один</li><li>два</li></ul>',
      });
      final gate = !e.isForcedListArtifactBody;
      final preview = e.calcLocalizedBodyFallback(
        _i18n,
        plaintextBody: gate,
        removeMarkdown: gate,
      );
      expect(preview, isNot(contains('•')));
      expect(preview, contains('один'));
    });

    test('HTML-список без маркеров сохраняет буллеты в превью', () {
      final e = _event(client, {
        'msgtype': 'm.text',
        'body': 'один\nдва',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<ul><li>один</li><li>два</li></ul>',
      });
      final gate = !e.isForcedListArtifactBody;
      final preview = e.calcLocalizedBodyFallback(
        _i18n,
        plaintextBody: gate,
        removeMarkdown: gate,
      );
      expect(preview, contains('•'));
      expect(preview, contains('один'));
    });
  });

  group('пузырь: reply/list → литерал (message_content else-ветка)', () {
    // Пузырь при isForcedListArtifact рисует event.calcUnlocalizedBody(
    // hideReply:true) как escaped-плейн (message_content.dart). Проверяем, что
    // для reply/списочных артефактов LABA-2222 это «+»/«-», а не «•».
    test('ответ «+» → пузырь рисует «+», гейт true', () {
      final e = _event(client, {
        'msgtype': 'm.text',
        'body': '> <@o:x> Файл\n\n+',
        'format': 'org.matrix.custom.html',
        'formatted_body':
            '<mx-reply><blockquote>Файл</blockquote></mx-reply><ul><li></li></ul>',
      });
      expect(e.isForcedListArtifactBody, isTrue);
      expect(e.calcUnlocalizedBody(hideReply: true), '+');
    });

    test('список «+ пункт 1 / + пункт 2» → пузырь рисует плейн, гейт true', () {
      final e = _event(client, {
        'msgtype': 'm.text',
        'body': '+ пункт 1\n+ пункт 2',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<ul><li>пункт 1</li><li>пункт 2</li></ul>',
      });
      expect(e.isForcedListArtifactBody, isTrue);
      final bubble = e.calcUnlocalizedBody(hideReply: true);
      expect(bubble, '+ пункт 1\n+ пункт 2');
      expect(bubble, isNot(contains('•')));
    });
  });
}
