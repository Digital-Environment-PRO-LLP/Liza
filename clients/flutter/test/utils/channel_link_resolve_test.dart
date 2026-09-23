// ledger:RL-channel-link-open-internal
// AC:RL-channel-link-open-internal/1
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/invite_link_parser.dart';

void main() {
  group('resolveInternalRoute — ссылка Liza → внутренний путь роутера', () {
    test('ссылка на канал me.liza.ru/c/<handle> → /c/<handle>', () {
      expect(
        resolveInternalRoute(Uri.parse('https://me.liza.ru/c/rozental')),
        '/c/rozental',
      );
    });

    test('custom-scheme liza://channel/<handle> → /c/<handle>', () {
      expect(
        resolveInternalRoute(Uri.parse('liza://channel/rozental')),
        '/c/rozental',
      );
    });

    test('сторис me.liza.ru/s/<code> → /s/<code>', () {
      expect(
        resolveInternalRoute(Uri.parse('https://me.liza.ru/s/abc123')),
        '/s/abc123',
      );
    });

    test('инвайт me.liza.ru/i/<code> → /i/<code>', () {
      expect(
        resolveInternalRoute(Uri.parse('https://me.liza.ru/i/p_DKvhaNQUUi')),
        '/i/p_DKvhaNQUUi',
      );
    });

    test(
      'чужой https-хост → null (не перехватываем, откроется в браузере)',
      () {
        expect(
          resolveInternalRoute(Uri.parse('https://example.com/c/rozental')),
          isNull,
        );
      },
    );

    test('обычная https-ссылка → null', () {
      expect(resolveInternalRoute(Uri.parse('https://google.com')), isNull);
    });

    test('невалидный ник канала (/c/мусор) → null', () {
      expect(
        resolveInternalRoute(Uri.parse('https://me.liza.ru/c/@x')),
        isNull,
      );
    });
  });
}
