// ledger:RL-user-handles AC:RL-user-handles/11
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/invite_link_parser.dart';

void main() {
  group('parseInviteCode', () {
    test('liza://invite/<code> -> code', () {
      expect(
        parseInviteCode(Uri.parse('liza://invite/p_X9CRwBb2rq')),
        'p_X9CRwBb2rq',
      );
    });

    test('https://liza.laba.pro/i/<code> -> code', () {
      expect(
        parseInviteCode(Uri.parse('https://liza.laba.pro/i/p_X9CRwBb2rq')),
        'p_X9CRwBb2rq',
      );
    });

    test('https://me.liza.ru/i/<code> -> code', () {
      expect(
        parseInviteCode(Uri.parse('https://me.liza.ru/i/p_X9CRwBb2rq')),
        'p_X9CRwBb2rq',
      );
    });

    test('http://liza.laba.pro/i/<code> -> code', () {
      expect(
        parseInviteCode(Uri.parse('http://liza.laba.pro/i/d_abc123')),
        'd_abc123',
      );
    });

    test('liza://invite without path -> null', () {
      expect(parseInviteCode(Uri.parse('liza://invite')), null);
    });

    test('liza://chat/... (другой scheme path) -> null', () {
      expect(parseInviteCode(Uri.parse('liza://chat/foo')), null);
    });

    test('https://liza.laba.pro/other/path -> null', () {
      expect(parseInviteCode(Uri.parse('https://liza.laba.pro/foo/bar')), null);
    });

    test('https://liza.laba.pro/<slug>/<code> -> code', () {
      expect(
        parseInviteCode(
          Uri.parse('https://liza.laba.pro/mySuperMiniApp/p_DKvhaNQUUi'),
        ),
        'p_DKvhaNQUUi',
      );
    });

    test('custom slug со случайным вторым сегментом (не код) -> null', () {
      expect(
        parseInviteCode(Uri.parse('https://liza.laba.pro/about/team')),
        null,
      );
    });

    test('.well-known никогда не инвайт -> null', () {
      expect(
        parseInviteCode(
          Uri.parse('https://liza.laba.pro/.well-known/p_DKvhaNQUUi'),
        ),
        null,
      );
    });

    test('https://other-domain.com/i/<code> -> null', () {
      expect(parseInviteCode(Uri.parse('https://example.com/i/abc')), null);
    });

    test('matrix.to URL -> null', () {
      expect(
        parseInviteCode(Uri.parse('https://matrix.to/#/!room:server.tld')),
        null,
      );
    });
  });

  group('parseStoryLinkCode', () {
    test('https://me.liza.ru/s/<code> -> code [ledger:RL-stories-link]', () {
      expect(
        parseStoryLinkCode(Uri.parse('https://me.liza.ru/s/p_abc123DEFG')),
        'p_abc123DEFG',
      );
    });

    test('https://liza.laba.pro/s/<code> -> code [ledger:RL-stories-link]', () {
      expect(
        parseStoryLinkCode(Uri.parse('https://liza.laba.pro/s/p_abc123DEFG')),
        'p_abc123DEFG',
      );
    });

    test('liza://story/<code> -> code [ledger:RL-stories-link]', () {
      expect(
        parseStoryLinkCode(Uri.parse('liza://story/p_abc123DEFG')),
        'p_abc123DEFG',
      );
    });

    test('чужой хост -> null [ledger:RL-stories-link]', () {
      expect(parseStoryLinkCode(Uri.parse('https://evil.com/s/p_x')), null);
    });

    test('invite-путь /i/<code> -> null [ledger:RL-stories-link]', () {
      expect(
        parseStoryLinkCode(Uri.parse('https://liza.laba.pro/i/p_abc123DEFG')),
        null,
      );
    });

    test('liza://story без пути -> null', () {
      expect(parseStoryLinkCode(Uri.parse('liza://story')), null);
    });

    test('liza://invite/... (другой host) -> null', () {
      expect(parseStoryLinkCode(Uri.parse('liza://invite/p_abc123DEFG')), null);
    });
  });

  test(
    'parseInviteCode не путает /s/<code> с инвайт-слагом [ledger:RL-stories-link]',
    () {
      expect(
        parseInviteCode(Uri.parse('https://liza.laba.pro/s/p_abc123DEFG')),
        null,
      );
    },
  );

  group('parseChannelHandle [ledger:RL-channel-link-open]', () {
    test('https://me.liza.ru/c/<ник> -> ник [AC:RL-channel-link-open/1]', () {
      expect(
        parseChannelHandle(Uri.parse('https://me.liza.ru/c/rozental')),
        'rozental',
      );
    });

    test(
      'legacy-домен liza.laba.pro/c/<ник> -> ник [AC:RL-channel-link-open/1]',
      () {
        expect(
          parseChannelHandle(Uri.parse('https://liza.laba.pro/c/rozental')),
          'rozental',
        );
      },
    );

    test(
      'deep link liza://channel/<ник> -> ник [AC:RL-channel-link-open/1]',
      () {
        expect(
          parseChannelHandle(Uri.parse('liza://channel/rozental')),
          'rozental',
        );
      },
    );

    test(
      'ник нормализуется к нижнему регистру [AC:RL-channel-link-open/1]',
      () {
        expect(
          parseChannelHandle(Uri.parse('https://me.liza.ru/c/RoZenTal')),
          'rozental',
        );
      },
    );

    test('невалидный ник (короткий) -> null [AC:RL-channel-link-open/2]', () {
      expect(parseChannelHandle(Uri.parse('https://me.liza.ru/c/abc')), null);
    });

    test(
      'невалидный ник (сигил/спецсимволы) -> null [AC:RL-channel-link-open/2]',
      () {
        expect(
          parseChannelHandle(Uri.parse('https://me.liza.ru/c/%40rozental')),
          null,
        );
        expect(
          parseChannelHandle(Uri.parse('https://me.liza.ru/c/roz-ental')),
          null,
        );
      },
    );

    test('зарезервированный ник -> null [AC:RL-channel-link-open/2]', () {
      expect(
        parseChannelHandle(Uri.parse('https://me.liza.ru/c/support')),
        null,
      );
    });

    test('чужой хост -> null [AC:RL-channel-link-open/2]', () {
      expect(
        parseChannelHandle(Uri.parse('https://evil.com/c/rozental')),
        null,
      );
    });

    test('лишний сегмент пути -> null [AC:RL-channel-link-open/2]', () {
      expect(
        parseChannelHandle(Uri.parse('https://me.liza.ru/c/rozental/extra')),
        null,
      );
    });

    test('liza://channel без пути -> null [AC:RL-channel-link-open/2]', () {
      expect(parseChannelHandle(Uri.parse('liza://channel')), null);
    });

    test(
      'соседние типы ссылок (/i/, /s/) каналом не перехватываются [AC:RL-channel-link-open/3]',
      () {
        expect(
          parseChannelHandle(Uri.parse('https://me.liza.ru/i/p_abc123DEFG')),
          null,
        );
        expect(
          parseChannelHandle(Uri.parse('https://me.liza.ru/s/p_abc123DEFG')),
          null,
        );
        expect(
          parseChannelHandle(Uri.parse('liza://invite/p_abc123DEFG')),
          null,
        );
        expect(
          parseChannelHandle(Uri.parse('liza://story/p_abc123DEFG')),
          null,
        );
      },
    );

    test(
      'канал-ссылку /c/<ник> не перехватывают инвайт и сторис [AC:RL-channel-link-open/3]',
      () {
        expect(
          parseInviteCode(Uri.parse('https://me.liza.ru/c/rozental')),
          null,
        );
        expect(
          parseInviteCode(Uri.parse('https://liza.laba.pro/c/rozental')),
          null,
        );
        expect(
          parseStoryLinkCode(Uri.parse('https://me.liza.ru/c/rozental')),
          null,
        );
      },
    );
  });

  // ledger:RL-deeplink-single-path
  //
  // Фиксируем САМ ФАКТ коллизии custom-scheme с go_router как инвариант, чтобы
  // никто не «починил» его обратно, включив платформенный deep-linking.
  //
  // go_router матчит маршрут ТОЛЬКО по `uri.path`, отбрасывая scheme и host
  // (go_router-15.1.3: parser.dart:82, match.dart:71/226/248). Для
  // `liza://<host>/<code>` host — это тип ссылки, и он теряется: путь
  // вырождается в `/<code>`, который либо не матчит ничего, либо (что хуже)
  // случайно совпадёт с чужим роутом. Поэтому разбирать custom-scheme обязан
  // ТОЛЬКО ручной путь app_links → _processIncomingUris, работающий по
  // scheme+host.
  group(
    'custom-scheme URI несовместим с go_router [ledger:RL-deeplink-single-path]',
    () {
      test(
        'парсеры разбирают custom-scheme корректно [AC:RL-deeplink-single-path/1]',
        () {
          expect(
            parseInviteCode(Uri.parse('liza://invite/p_X9CRwBb2rq')),
            'p_X9CRwBb2rq',
          );
          expect(
            parseStoryLinkCode(Uri.parse('liza://story/s_Ab12Cd34Ef')),
            's_Ab12Cd34Ef',
          );
          expect(
            parseChannelHandle(Uri.parse('liza://channel/rozental')),
            'rozental',
          );
        },
      );

      test('uri.path custom-scheme НЕ равен целевому роуту — host потерян '
          '[AC:RL-deeplink-single-path/2]', () {
        // Ровно та величина, которую видит go_router. Если хоть одно из
        // равенств станет истинным — значит поведение Uri/роутера изменилось
        // и решение «единственный путь через app_links» надо пересматривать.
        final invite = Uri.parse('liza://invite/p_X9CRwBb2rq');
        expect(invite.path, '/p_X9CRwBb2rq');
        expect(invite.path, isNot('/i/p_X9CRwBb2rq'));
        expect(invite.host, 'invite');

        final story = Uri.parse('liza://story/s_Ab12Cd34Ef');
        expect(story.path, '/s_Ab12Cd34Ef');
        expect(story.path, isNot('/s/s_Ab12Cd34Ef'));
        expect(story.host, 'story');

        final channel = Uri.parse('liza://channel/rozental');
        expect(channel.path, '/rozental');
        expect(channel.path, isNot('/c/rozental'));
        expect(channel.host, 'channel');
      });

      test(
        'https-ссылки, наоборот, совпадают с роутом — их go_router матчил бы '
        'верно [AC:RL-deeplink-single-path/3]',
        () {
          // Асимметрия и есть причина, по которой баг выглядел «через раз»:
          // App Links работали, а лендинговые `liza://` — нет.
          expect(
            Uri.parse('https://me.liza.ru/i/p_X9CRwBb2rq').path,
            '/i/p_X9CRwBb2rq',
          );
          expect(
            Uri.parse('https://me.liza.ru/s/s_Ab12Cd34Ef').path,
            '/s/s_Ab12Cd34Ef',
          );
          expect(
            Uri.parse('https://me.liza.ru/c/rozental').path,
            '/c/rozental',
          );
        },
      );
    },
  );

  group('parseWebInviteCode [ledger:RL-pending-invite-persist] '
      '[AC:RL-pending-invite-persist/3]', () {
    // Регресс 2026-08-04: в вебе переход `/i/<code>` → форма логина — полная
    // перезагрузка страницы, статика PendingInviteCode обнулялась, и запрос
    // уходил как `/api/auth/registration?return_url=...` БЕЗ invite_code →
    // вместо register_via_invite отрабатывала обычная классификация
    // (no_accounts): «зарегался, но не пускает». Код берём из URL самого
    // веб-клиента, поэтому хост здесь НЕ из списка коротких ссылок.
    test('dev.web.liza.ru/i/<code> -> code', () {
      expect(
        parseWebInviteCode(Uri.parse('https://dev.web.liza.ru/i/d_rHAM5BjzHP')),
        'd_rHAM5BjzHP',
      );
    });

    test('web.liza.ru/i/<code> -> code', () {
      expect(
        parseWebInviteCode(Uri.parse('https://web.liza.ru/i/p_X9CRwBb2rq')),
        'p_X9CRwBb2rq',
      );
    });

    test('localhost с портом (dev-прогон) -> code', () {
      expect(
        parseWebInviteCode(Uri.parse('http://localhost:8080/i/d_abc123DEFG')),
        'd_abc123DEFG',
      );
    });

    test('хвост после кода не мешает', () {
      expect(
        parseWebInviteCode(Uri.parse('https://web.liza.ru/i/p_X9CRwBb2rq/x')),
        'p_X9CRwBb2rq',
      );
    });

    test('не-инвайтный путь -> null', () {
      expect(parseWebInviteCode(Uri.parse('https://web.liza.ru/')), null);
      expect(parseWebInviteCode(Uri.parse('https://web.liza.ru/rooms')), null);
      expect(
        parseWebInviteCode(Uri.parse('https://web.liza.ru/s/s_Ab12Cd34Ef')),
        null,
      );
    });

    test('/i/ с непохожим на код сегментом -> null', () {
      // `auth.html` резолвится относительно `/i/`, и без проверки формата
      // кода он ложно опознавался бы как инвайт.
      expect(
        parseWebInviteCode(Uri.parse('https://web.liza.ru/i/auth.html')),
        null,
      );
      expect(parseWebInviteCode(Uri.parse('https://web.liza.ru/i/abc')), null);
    });
  });

  group('webInitialLocation [ledger:RL-user-invite-link-opens-profile] '
      '[AC:RL-user-invite-link-opens-profile/1]', () {
    // LABA-2551: залогиненный веб-пользователь по path-ссылке
    // `web.liza.ru/i/<code>` (кнопка «Открыть в браузере» на лендинге)
    // попадал в список чатов — роутер на hash-стратегии стартовал с `/`.
    test('все четыре типа короткой ссылки → внутренний маршрут', () {
      expect(
        webInitialLocation(Uri.parse('https://dev.web.liza.ru/i/d_KH3HsAxgUB')),
        '/i/d_KH3HsAxgUB',
      );
      expect(
        webInitialLocation(Uri.parse('https://web.liza.ru/s/s_Ab12Cd34Ef')),
        '/s/s_Ab12Cd34Ef',
      );
      expect(
        webInitialLocation(Uri.parse('https://web.liza.ru/c/mychannel')),
        '/c/mychannel',
      );
      expect(
        webInitialLocation(Uri.parse('https://web.liza.ru/u/rozental')),
        '/u/rozental',
      );
    });

    test('обычный старт и внутренние пути → null (роутер стартует с /)', () {
      for (final url in const [
        'https://web.liza.ru/',
        'https://web.liza.ru/rooms',
        'https://web.liza.ru/#/rooms',
        'https://web.liza.ru/#/rooms/!abc:server',
        'https://web.liza.ru/auth.html?code=1',
      ]) {
        expect(webInitialLocation(Uri.parse(url)), isNull, reason: url);
      }
    });

    test('не похожие на код/ник сегменты → null', () {
      // `auth.html` под `/i/` и мусорный ник не должны ложно стартовать
      // резолв — те же гарды, что у parseWeb*.
      expect(
        webInitialLocation(Uri.parse('https://web.liza.ru/i/auth.html')),
        isNull,
      );
      expect(webInitialLocation(Uri.parse('https://web.liza.ru/i/abc')), isNull);
      expect(webInitialLocation(Uri.parse('https://web.liza.ru/u/x')), isNull);
    });

    test('hash уже с маршрутом, но path — ссылка: маршрут из path', () {
      // Решает роутер (initialLocation применяется только при пустом hash);
      // парсер про hash не знает и отдаёт path-маршрут как есть.
      expect(
        webInitialLocation(
          Uri.parse('https://web.liza.ru/i/d_KH3HsAxgUB#/rooms'),
        ),
        '/i/d_KH3HsAxgUB',
      );
    });
  });

  group('parseUserHandle', () {
    test('https://me.liza.ru/u/<ник> -> ник', () {
      expect(
        parseUserHandle(Uri.parse('https://me.liza.ru/u/rozental')),
        'rozental',
      );
    });

    test('legacy-домен liza.laba.pro/u/<ник> -> ник', () {
      expect(
        parseUserHandle(Uri.parse('https://liza.laba.pro/u/rozental')),
        'rozental',
      );
    });

    test('deep link liza://user/<ник> -> ник', () {
      expect(
        parseUserHandle(Uri.parse('liza://user/rozental')),
        'rozental',
      );
    });

    test('ник нормализуется к нижнему регистру', () {
      expect(
        parseUserHandle(Uri.parse('https://me.liza.ru/u/RoZenTal')),
        'rozental',
      );
    });

    test('невалидный ник (короткий) -> null', () {
      expect(parseUserHandle(Uri.parse('https://me.liza.ru/u/abc')), null);
    });

    test('невалидный ник (сигил/спецсимволы) -> null', () {
      expect(
        parseUserHandle(Uri.parse('https://me.liza.ru/u/%40rozental')),
        null,
      );
      expect(
        parseUserHandle(Uri.parse('https://me.liza.ru/u/roz-ental')),
        null,
      );
    });

    test('зарезервированный ник -> null', () {
      expect(
        parseUserHandle(Uri.parse('https://me.liza.ru/u/support')),
        null,
      );
    });

    test('чужой хост -> null', () {
      expect(parseUserHandle(Uri.parse('https://evil.com/u/rozental')), null);
    });

    test('лишний сегмент пути -> null', () {
      expect(
        parseUserHandle(Uri.parse('https://me.liza.ru/u/rozental/extra')),
        null,
      );
    });

    test('liza://user без пути -> null', () {
      expect(parseUserHandle(Uri.parse('liza://user')), null);
    });

    test('соседние типы ссылок (/i/, /s/, /c/) пользователем не '
        'перехватываются', () {
      expect(
        parseUserHandle(Uri.parse('https://me.liza.ru/i/p_abc123DEFG')),
        null,
      );
      expect(
        parseUserHandle(Uri.parse('https://me.liza.ru/s/p_abc123DEFG')),
        null,
      );
      expect(
        parseUserHandle(Uri.parse('https://me.liza.ru/c/rozental')),
        null,
      );
    });

    test('/u/<ник> не перехватывается инвайтом, сторисом и каналом', () {
      expect(
        parseInviteCode(Uri.parse('https://me.liza.ru/u/rozental')),
        null,
      );
      expect(
        parseInviteCode(Uri.parse('https://liza.laba.pro/u/rozental')),
        null,
      );
      expect(
        parseStoryLinkCode(Uri.parse('https://me.liza.ru/u/rozental')),
        null,
      );
      expect(
        parseChannelHandle(Uri.parse('https://me.liza.ru/u/rozental')),
        null,
      );
    });

    // Мутационная находка ревью: ник `rozental` не годится для проверки
    // исключения `first != 'u'` в legacy-ветке parseInviteCode — он и без
    // исключения не проходит _looksLikeInviteCode (нет `_` + ≥8 симв.
    // после). `p_DKvhaNQUUi` валиден ОДНОВРЕМЕННО как ник
    // (validateChannelHandle) и как формат инвайт-кода (`^[a-z0-9]+_[A-Za-
    // z0-9]{8,}$`) — без исключения `u` в parseInviteCode такая ссылка на
    // профиль ложно уехала бы в обработчик инвайтов.
    test(
      'ник, похожий на инвайт-код (p_DKvhaNQUUi), не перехватывается '
      'legacy-инвайт-веткой [мутационная защита first != u]',
      () {
        // Фикстура заведомо валидна и как ник (^[a-z][a-z0-9_]{4,31}$), и
        // как формат инвайт-кода (^[a-z0-9]+_[A-Za-z0-9]{8,}$) — иначе
        // проверка ничего не различает.
        expect(
          parseUserHandle(Uri.parse('https://liza.laba.pro/u/p_DKvhaNQUUi')),
          'p_dkvhanquui',
          reason: 'фикстура обязана быть валидным ником',
        );
        expect(
          parseInviteCode(Uri.parse('https://liza.laba.pro/u/p_DKvhaNQUUi')),
          null,
        );
      },
    );
  });
}
