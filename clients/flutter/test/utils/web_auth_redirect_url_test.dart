import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/web_auth_redirect_url.dart';

/// Регресс 2026-08-04: redirect_url для OIDC собирался относительным
/// разрешением от текущего URL — `Uri.parse(href).resolveUri(pathSegments:
/// ['auth.html'])`. С вложенной страницы это давало `/i/auth.html`, а не
/// `/auth.html`: файла нет, nginx отдавал SPA-fallback (index.html, 200),
/// результат авторизации не доезжал до вкладки, и пользователя возвращало
/// на пустой экран входа. Ломался ЛЮБОЙ вход не с корня.
void main() {
  group('webAuthRedirectUrl [ledger:RL-web-auth-html-absolute]', () {
    test('корень -> /auth.html [AC:RL-web-auth-html-absolute/1]', () {
      expect(
        webAuthRedirectUrl('https://web.liza.ru/'),
        'https://web.liza.ru/auth.html',
      );
    });

    test(
      'страница инвайта /i/<code> -> /auth.html (не /i/auth.html) '
      '[AC:RL-web-auth-html-absolute/1]',
      () {
        expect(
          webAuthRedirectUrl('https://web.liza.ru/i/p_mJuNUdhx4M'),
          'https://web.liza.ru/auth.html',
        );
      },
    );

    test('вложенный путь /rooms/<id> -> /auth.html '
        '[AC:RL-web-auth-html-absolute/1]', () {
      expect(
        webAuthRedirectUrl('https://web.liza.ru/rooms/abc'),
        'https://web.liza.ru/auth.html',
      );
    });

    test('путь со слешом на конце -> /auth.html '
        '[AC:RL-web-auth-html-absolute/1]', () {
      expect(
        webAuthRedirectUrl('https://web.liza.ru/i/p_X9/'),
        'https://web.liza.ru/auth.html',
      );
    });

    test('dev-контур сохраняет свой хост [AC:RL-web-auth-html-absolute/2]', () {
      expect(
        webAuthRedirectUrl('https://dev.web.liza.ru/i/d_rHAM5BjzHP'),
        'https://dev.web.liza.ru/auth.html',
      );
    });

    test('localhost сохраняет порт [AC:RL-web-auth-html-absolute/2]', () {
      expect(
        webAuthRedirectUrl('http://localhost:8080/i/d_abc123DEFG'),
        'http://localhost:8080/auth.html',
      );
    });

    test(
      'query и fragment текущей страницы отбрасываются '
      '[AC:RL-web-auth-html-absolute/3]',
      () {
        // `#/home` от go_router в redirect_uri ломал бы сверку на стороне
        // OIDC-провайдера (redirect_uri должен совпадать посимвольно).
        expect(
          webAuthRedirectUrl(
            'https://web.liza.ru/i/p_X9CRwBb2rq?action=processing#/home',
          ),
          'https://web.liza.ru/auth.html',
        );
      },
    );
  });
}
