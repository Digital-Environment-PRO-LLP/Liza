// Жалоба Романа: «отправляю в чат "+", а он меняет на булет списка». Markdown
// (в SDK/внешних клиентах/XL) заворачивает строку-маркер (`-`/`+`/`*`) в
// <ul><li>, и bab53b5c (рендер formatted_body) стал показывать буллет.
// LABA-2222 расширила: то же в ОТВЕТЕ (<mx-reply>…</mx-reply><ul><li></li></ul>)
// и в МНОГОСТРОЧНОМ списке «плюсов/минусов». isForcedListArtifact подавляет
// навязанный список из маркеров «+»/«-»/«*», не трогая обычную разметку,
// нумерованные многострочные списки и HTML-списки без маркеров в body.

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat/events/html_message.dart';

const _bulletHtml = '<ul>\n<li></li>\n</ul>\n';

// Reply-фолбэк ровно как строит SDK room.sendEvent(inReplyTo) при
// parseMarkdown:true (старые сборки / внешние клиенты): mx-reply + список.
String _reply(String repliedHtml) =>
    '<mx-reply><blockquote><a href="https://matrix.to/#/!r/\$o">In reply to</a> '
    '<a href="https://matrix.to/#/@o:x">@o:x</a><br>Файл</blockquote></mx-reply>'
    '$repliedHtml';
String _replyBody(String tail) => '> <@o:x> Файл\n\n$tail';

// ledger:RL-forced-list-artifact
void main() {
  group('isForcedListArtifact — подавляем (литерал)', () {
    test('одиночный «+»', () {
      expect(isForcedListArtifact('+', _bulletHtml), isTrue);
    });

    test('одиночный «-» (дефис)', () {
      expect(isForcedListArtifact('-', _bulletHtml), isTrue);
    });

    test('одиночная «*»', () {
      expect(isForcedListArtifact('*', _bulletHtml), isTrue);
    });

    test('маркер с текстом на одной строке «+ да»', () {
      expect(isForcedListArtifact('+ да', '<ul>\n<li>да</li>\n</ul>\n'), isTrue);
    });

    test('нумерованный одиночный «1. раз»', () {
      expect(
        isForcedListArtifact('1. раз', '<ol>\n<li>раз</li>\n</ol>\n'),
        isTrue,
      );
    });

    test('пробелы вокруг маркера не мешают', () {
      expect(isForcedListArtifact('  -  ', _bulletHtml), isTrue);
    });

    // Ветка (B): вырожденный список без видимого текста («•»).
    test('пустой буллет — body пустой', () {
      expect(isForcedListArtifact('', _bulletHtml), isTrue);
    });

    test('пустой буллет — body null', () {
      expect(isForcedListArtifact(null, _bulletHtml), isTrue);
    });

    test('вырожденный нумерованный (пустой li)', () {
      expect(isForcedListArtifact('', '<ol>\n<li></li>\n</ol>\n'), isTrue);
    });

    // LABA-2222 (C): МНОГОСТРОЧНЫЙ список из «+»/«-»/«*» — тоже литерал.
    test('многострочный «+ пункт 1 / + пункт 2»', () {
      expect(
        isForcedListArtifact(
          '+ пункт 1\n+ пункт 2',
          '<ul><li>пункт 1</li><li>пункт 2</li></ul>',
        ),
        isTrue,
      );
    });

    test('многострочный «- пункт / - пункт2»', () {
      expect(
        isForcedListArtifact(
          '- пункт\n- пункт2',
          '<ul>\n<li>пункт</li>\n<li>пункт2</li>\n</ul>\n',
        ),
        isTrue,
      );
    });

    test('многострочный из голых маркеров «+ / -»', () {
      expect(
        isForcedListArtifact('+\n-', '<ul><li></li></ul><ul><li></li></ul>'),
        isTrue,
      );
    });

    // LABA-2222 (жалоба Нади): СМЕШАННОЕ сообщение — список + пояснительная строка
    // в одном событии. Раньше падало (не все строки маркеры).
    test('смешанный «+ п1 / + п2 / Это два плюса»', () {
      expect(
        isForcedListArtifact(
          '+ пункт 1\n+ пункт 2\nЭто два плюса',
          '<ul><li>пункт 1</li><li>пункт 2</li></ul>\n<p>Это два плюса</p>',
        ),
        isTrue,
      );
    });

    test('смешанный «- п1 / текст / - п2»', () {
      expect(
        isForcedListArtifact(
          '- п1\nпросто текст\n- п2',
          '<ul><li>п1</li></ul><p>просто текст</p><ul><li>п2</li></ul>',
        ),
        isTrue,
      );
    });

    // LABA-2222 (A/B): ОТВЕТ одиночным «+»/«-» → mx-reply + список.
    test('ответ одиночным «+» (вырожденный список после цитаты)', () {
      expect(
        isForcedListArtifact(_replyBody('+'), _reply('<ul><li></li></ul>')),
        isTrue,
      );
    });

    test('ответ «- да» (маркер с текстом после цитаты)', () {
      expect(
        isForcedListArtifact(
          _replyBody('- да'),
          _reply('<ul><li>да</li></ul>'),
        ),
        isTrue,
      );
    });

    test('ответ многострочным списком «+ a / + b»', () {
      expect(
        isForcedListArtifact(
          _replyBody('+ a\n+ b'),
          _reply('<ul><li>a</li><li>b</li></ul>'),
        ),
        isTrue,
      );
    });
  });

  group('isForcedListArtifact — НЕ трогаем', () {
    test('одно-пунктовый HTML-список без маркера в body', () {
      // Осознанный список внешнего клиента: текст есть, маркера в body нет.
      expect(
        isForcedListArtifact(
          'купить молоко',
          '<ul>\n<li>купить молоко</li>\n</ul>\n',
        ),
        isFalse,
      );
    });

    test('МНОГОСТРОЧНЫЙ HTML-список без маркеров в body', () {
      expect(
        isForcedListArtifact(
          'один\nдва',
          '<ul><li>один</li><li>два</li></ul>',
        ),
        isFalse,
      );
    });

    test('нумерованный МНОГОСТРОЧНЫЙ список сохраняем', () {
      expect(
        isForcedListArtifact(
          '1. раз\n2. два',
          '<ol><li>раз</li><li>два</li></ol>',
        ),
        isFalse,
      );
    });

    test('ответ обычным текстом на СПИСОК (список только в цитате)', () {
      // Оригинал был списком → он внутри mx-reply; наш ответ — плейн «ок».
      expect(
        isForcedListArtifact(
          _replyBody('ок'),
          '<mx-reply><blockquote>цитата<ul><li>x</li></ul></blockquote>'
          '</mx-reply>ок',
        ),
        isFalse,
      );
    });

    test('маркер в середине текста «a + b»', () {
      expect(isForcedListArtifact('a + b', '<p>a + b</p>'), isFalse);
    });

    test('жирный текст (не список)', () {
      expect(isForcedListArtifact('**жир**', '<strong>жир</strong>'), isFalse);
    });

    test('маркер, но formatted_body без списка — оставляем как есть', () {
      expect(isForcedListArtifact('+', '<strong>+</strong>'), isFalse);
    });

    test('formatted_body null безопасен', () {
      expect(isForcedListArtifact('+', null), isFalse);
    });
  });
}
