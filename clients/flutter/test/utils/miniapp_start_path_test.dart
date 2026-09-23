// Стражи deep-link mini App: захват app_start_path из URL открытой страницы,
// сборка финального URL без затирания маршрута приложения, граница безопасности.
// ledger:RL-miniapp-start-path
//
// Инварианты:
//  1. extractStartPath срезает Liza-инъекции (initData/return-маркеры) и отдаёт
//     ТОЛЬКО фрагмент/query относительно appUrl; чужой origin → ''.
//  2. composeMiniAppUrl НЕ затирает маршрут приложения: при фрагментном
//     startPath (Tilda #!/...) initData в URL не добавляется (нет двойного #).
//  3. isSafeStartPath режет смену origin/схемы/пути и инъекции (// , :// ,
//     javascript:/data:, управляющие символы, длину) — зеркало серверной
//     _sanitize_start_path в auth-proxy.

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/miniapp_start_path.dart';

void main() {
  const tildaBase = 'https://nrozental.tilda.ws/test_shop';
  const tildaProduct =
      'https://nrozental.tilda.ws/test_shop#!/tproduct/2413257851-1500470245901';

  group('extractStartPath', () {
    test('страница товара Tilda → её фрагмент-маршрут', () {
      expect(
        extractStartPath(appUrl: tildaBase, currentUrl: tildaProduct),
        '#!/tproduct/2413257851-1500470245901',
      );
    });

    test('главная с initData-фрагментом Liza → пусто (маршрута нет)', () {
      const home =
          '$tildaBase#lizaWebAppData=abc%3D&platform=macos&theme_params=%7B%7D';
      expect(extractStartPath(appUrl: tildaBase, currentUrl: home), '');
    });

    test('товар + хвост initData в одном фрагменте → весь фрагмент срезается', () {
      // На практике Tilda заменяет фрагмент целиком, но если бы initData-маркер
      // оказался во фрагменте — это наш служебный фрагмент, режем целиком.
      const mixed = '$tildaBase#!/tproduct/1&lizaWebAppData=x';
      expect(extractStartPath(appUrl: tildaBase, currentUrl: mixed), '');
    });

    test('return-маркеры оплаты в query срезаются', () {
      const paid = '$tildaBase?payment_result=paid&liza_invoice_id=5';
      expect(extractStartPath(appUrl: tildaBase, currentUrl: paid), '');
    });

    test('чужой host (платёжный шлюз) → пусто', () {
      const pay = 'https://payform.online/?order=1#!/tproduct/1';
      expect(extractStartPath(appUrl: tildaBase, currentUrl: pay), '');
    });

    test('смена схемы → пусто', () {
      expect(
        extractStartPath(
          appUrl: tildaBase,
          currentUrl: 'http://nrozental.tilda.ws/test_shop#!/x',
        ),
        '',
      );
    });

    test('пользовательский query без Liza-маркеров сохраняется', () {
      const q = '$tildaBase?ref=abc';
      expect(extractStartPath(appUrl: tildaBase, currentUrl: q), '?ref=abc');
    });
  });

  group('composeMiniAppUrl', () {
    const initData = 'lizaWebAppData=abc&platform=macos&theme_params=%7B%7D';

    test('пустой startPath → прежнее поведение (appUrl#initData)', () {
      expect(
        composeMiniAppUrl(appUrl: tildaBase, initDataFragment: initData),
        '$tildaBase#$initData',
      );
    });

    test('фрагмент-маршрут → initData НЕ добавляется, двойного # нет', () {
      final url = composeMiniAppUrl(
        appUrl: tildaBase,
        startPath: '#!/tproduct/123',
        initDataFragment: initData,
      );
      expect(url, '$tildaBase#!/tproduct/123');
      expect('#'.allMatches(url).length, 1);
      expect(url.contains('lizaWebAppData'), isFalse);
    });

    test('query-startPath без фрагмента → initData в # после query', () {
      final url = composeMiniAppUrl(
        appUrl: tildaBase,
        startPath: '?ref=abc',
        initDataFragment: initData,
      );
      expect(url, '$tildaBase?ref=abc#$initData');
    });

    test('без initData → просто appUrl+startPath', () {
      expect(
        composeMiniAppUrl(appUrl: tildaBase, startPath: '#!/tproduct/1'),
        '$tildaBase#!/tproduct/1',
      );
    });
  });

  group('isSafeStartPath', () {
    test('валидные фрагмент/query', () {
      expect(isSafeStartPath('#!/tproduct/2413257851-1500470245901'), isTrue);
      expect(isSafeStartPath('?ref=abc'), isTrue);
    });

    test('режет смену origin / протокол-релатив / абсолют / path', () {
      expect(isSafeStartPath('https://evil.com'), isFalse);
      expect(isSafeStartPath('//evil.com'), isFalse);
      expect(isSafeStartPath('#x://y'), isFalse);
      expect(isSafeStartPath('/admin'), isFalse); // path не разрешён
    });

    test('режет javascript:/data: и управляющие символы', () {
      expect(isSafeStartPath('javascript:alert(1)'), isFalse);
      expect(isSafeStartPath('data:text/html,x'), isFalse);
      expect(isSafeStartPath('#x${String.fromCharCode(0x0a)}y'), isFalse); // LF
      expect(isSafeStartPath('#x${String.fromCharCode(0x7f)}y'), isFalse); // DEL
      expect(isSafeStartPath('#xy'), isTrue); // обычный фрагмент валиден
    });

    test('режет пустое и слишком длинное', () {
      expect(isSafeStartPath(''), isFalse);
      expect(isSafeStartPath('#${'a' * 520}'), isFalse);
    });
  });
}
