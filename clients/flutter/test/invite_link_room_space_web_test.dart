// ledger:RL-invite-link-opens-room-space-web
// AC:RL-invite-link-opens-room-space-web/1 AC:RL-invite-link-opens-room-space-web/2
// AC:RL-invite-link-opens-room-space-web/3 AC:RL-invite-link-opens-room-space-web/4
// AC:RL-invite-link-opens-room-space-web/5
//
// LABA-2537 (Daniel Furman, 2026-09-02): ссылка-приглашение в ЧАТ и в
// ПРОСТРАНСТВО по кнопке «Открыть в браузере» открывала список чатов, а не
// цель. Корень — web на hash-стратегии: лендинг ведёт на path-форму
// `web.liza.ru/i/<code>`, а go_router применяет `initialLocation` только при
// пустом hash, поэтому без `webInitialLocation(Uri.base)` роутер стартовал с
// `/`. Фикс — bf2c9998 (LABA-2551), общий для всех четырёх типов коротких
// ссылок; здесь он закрепляется ИМЕННО на room/space-ветках.
//
// Red-proof AC-5: `LizaApp.buildAppRouter()` БЕЗ initialLocation (поведение до
// фикса) стартует с `/` — это и есть «список чатов». Ассерт на это отличие
// краснеет, если проводку initialLocation выломают или go_router сменит
// семантику `_effectiveInitialLocation` (версия запинена мягко: ^17.0.1).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/opening/opening_page.dart';
import 'package:liza/utils/auth_proxy_service.dart';
import 'package:liza/utils/deep_link_target.dart';
import 'package:liza/utils/invite_link_parser.dart';
import 'package:liza/widgets/liza_app.dart';

const _roomId = '!chat:example.invalid';
const _spaceId = '!space:example.invalid';
const _code = 'd_zggniT2Ank'; // код из скриншота тикета

/// Полный резолв через ПРОДОВОЕ ядро (`resolveInviteTargetFromResult` +
/// `deepLinkRoutePath`), а не захардкоженная строка пути: иначе тест проверял
/// бы сам себя, а не цепочку, которой идёт пользователь.
Future<String> _resolveVia(InviteRedeemResult result) async {
  final target = await resolveInviteTargetFromResult(
    result: result,
    code: _code,
    awaitRoom: (roomId, {required expectSpace}) async => true,
    lookupRoomIsSpace: (roomId) => roomId == _spaceId,
  );
  return deepLinkRoutePath(target);
}

void main() {
  group('LABA-2537 · резолв цели инвайта', () {
    // AC-1: позитивная room-ветка. До этого стража она не была заасёртена
    // вовсе — проверялись только отрицательные исходы.
    test('AC-1 joined + обычная комната → DeepLinkRoom и путь чата', () async {
      final target = await resolveInviteTargetFromResult(
        result: const InviteRedeemResult(status: 'joined', roomId: _roomId),
        code: _code,
        awaitRoom: (roomId, {required expectSpace}) async {
          expect(expectSpace, isFalse, reason: 'обычный чат — не пространство');
          return true;
        },
        lookupRoomIsSpace: (roomId) => false,
      );
      expect(target, isA<DeepLinkRoom>());
      expect((target as DeepLinkRoom).roomId, _roomId);
      expect(
        deepLinkRoutePath(target),
        '/rooms/${Uri.encodeComponent(_roomId)}',
      );
    });

    test('AC-1 already_joined ведёт себя как joined (идемпотентный redeem)',
        () async {
      final target = await resolveInviteTargetFromResult(
        result: const InviteRedeemResult(
          status: 'already_joined',
          roomId: _roomId,
        ),
        code: _code,
        awaitRoom: (roomId, {required expectSpace}) async => true,
        lookupRoomIsSpace: (roomId) => false,
      );
      expect(target, isA<DeepLinkRoom>());
      expect(deepLinkRoutePath(target), contains(Uri.encodeComponent(_roomId)));
    });

    // AC-2: пространство — ∀ обоих статусов, которые реально отдаёт auth-proxy
    // (`handler.py` возвращает joined | already_joined | user_invite |
    // miniapp_invite | needs_account_on_target_server).
    test('AC-2 ∀ {joined, already_joined} + target_kind=space → DeepLinkSpace',
        () async {
      for (final status in const ['joined', 'already_joined']) {
        final target = await resolveInviteTargetFromResult(
          result: InviteRedeemResult(
            status: status,
            roomId: _spaceId,
            targetKind: 'space',
          ),
          code: _code,
          awaitRoom: (roomId, {required expectSpace}) async {
            expect(expectSpace, isTrue, reason: 'space ждём как space: $status');
            return true;
          },
          lookupRoomIsSpace: (roomId) => true,
        );
        expect(target, isA<DeepLinkSpace>(), reason: status);
        expect(
          deepLinkRoutePath(target),
          '/rooms?spaceId=${Uri.encodeComponent(_spaceId)}',
          reason: status,
        );
      }
    });

    // Пространство без target_kind от бэка: тип берётся из локальной комнаты —
    // иначе space открылся бы как ChatPage.
    test('AC-2 space без target_kind распознаётся по isSpace комнаты',
        () async {
      final target = await resolveInviteTargetFromResult(
        result: const InviteRedeemResult(status: 'joined', roomId: _spaceId),
        code: _code,
        awaitRoom: (roomId, {required expectSpace}) async => true,
        lookupRoomIsSpace: (roomId) => true,
      );
      expect(target, isA<DeepLinkSpace>());
    });
  });

  group('LABA-2537 · реальный OpeningPage доводит до цели', () {
    /// Реальный `OpeningPage` в реальном `GoRouter` с прод-подобными
    /// маршрутами. Экраны-заглушки стоят вместо ChatPage/ChatList намеренно:
    /// проверяется МАРШРУТИЗАЦИЯ (куда довёл резолв), а сами экраны закреплены
    /// своими стражами. Резолв — продовый, не строка.
    Future<String?> pumpAndGetLocation(
      WidgetTester tester,
      InviteRedeemResult result,
    ) async {
      String? landed;
      final router = GoRouter(
        initialLocation: '/opening/$_code',
        routes: [
          GoRoute(
            path: '/opening/:code',
            builder: (context, state) => OpeningPage(
              code: state.pathParameters['code']!,
              resolve: () => _resolveVia(result),
              onNavigated: (_) {},
            ),
          ),
          GoRoute(
            path: '/rooms',
            builder: (context, state) {
              landed = state.uri.toString();
              final space = state.uri.queryParameters['spaceId'];
              return Scaffold(
                body: Text(space == null ? 'CHAT_LIST' : 'SPACE:$space'),
              );
            },
            routes: [
              GoRoute(
                path: ':roomid',
                builder: (context, state) {
                  landed = state.uri.toString();
                  return Scaffold(
                    body: Text('CHAT:${state.pathParameters['roomid']}'),
                  );
                },
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      return landed;
    }

    // AC-3: инвайт в ЧАТ доводит до маршрута чата, а НЕ до списка.
    testWidgets('AC-3 room-инвайт → экран чата, не список чатов',
        (tester) async {
      final landed = await pumpAndGetLocation(
        tester,
        const InviteRedeemResult(status: 'joined', roomId: _roomId),
      );
      expect(find.text('CHAT:$_roomId'), findsOneWidget);
      expect(find.text('CHAT_LIST'), findsNothing);
      expect(landed, '/rooms/${Uri.encodeComponent(_roomId)}');
    });

    // AC-4: инвайт в ПРОСТРАНСТВО доводит до экрана пространства
    // (`/rooms?spaceId=` → SpaceView), а НЕ до общего списка чатов.
    testWidgets('AC-4 space-инвайт → экран пространства, не список чатов',
        (tester) async {
      final landed = await pumpAndGetLocation(
        tester,
        const InviteRedeemResult(
          status: 'joined',
          roomId: _spaceId,
          targetKind: 'space',
        ),
      );
      expect(find.text('SPACE:$_spaceId'), findsOneWidget);
      expect(find.text('CHAT_LIST'), findsNothing);
      expect(landed, '/rooms?spaceId=${Uri.encodeComponent(_spaceId)}');
    });

    // Контроль чувствительности: когда цель действительно не разрешилась,
    // список чатов — корректный исход. Без этого AC-3/AC-4 не отличали бы
    // «довели куда надо» от «маршрутизация всегда даёт чат».
    testWidgets('комната не доехала в sync → список чатов (контроль)',
        (tester) async {
      String? landed;
      final router = GoRouter(
        initialLocation: '/opening/$_code',
        routes: [
          GoRoute(
            path: '/opening/:code',
            builder: (context, state) => OpeningPage(
              code: _code,
              resolve: () async => deepLinkRoutePath(
                await resolveInviteTargetFromResult(
                  result: const InviteRedeemResult(
                    status: 'joined',
                    roomId: _roomId,
                  ),
                  code: _code,
                  awaitRoom: (roomId, {required expectSpace}) async => false,
                  lookupRoomIsSpace: (roomId) => null,
                ),
              ),
              onNavigated: (_) {},
            ),
          ),
          GoRoute(
            path: '/rooms',
            builder: (context, state) {
              landed = state.uri.toString();
              return const Scaffold(body: Text('CHAT_LIST'));
            },
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CHAT_LIST'), findsOneWidget);
      expect(landed, '/rooms');
    });
  });

  group('LABA-2537 · web-инициация: роутер стартует с path-формы ссылки', () {
    // AC-5 (корень тикета, red-proof): на вебе лендинг ведёт на
    // `web.liza.ru/i/<code>` с ПУСТЫМ hash. Без проводки initialLocation
    // роутер стартует с `/` → список чатов. Проверяем ПРОДОВУЮ фабрику
    // `LizaApp.buildAppRouter`, а не реплику GoRouter.
    testWidgets('AC-5 buildAppRouter стартует с /i/<code>, а без него — с /',
        (tester) async {
      const landings = {
        'https://web.liza.ru/i/$_code': '/i/$_code',
        'https://dev.web.liza.ru/i/$_code': '/i/$_code',
      };
      for (final entry in landings.entries) {
        final route = webInitialLocation(Uri.parse(entry.key));
        expect(route, entry.value, reason: entry.key);
        final router = LizaApp.buildAppRouter(initialLocation: route);
        addTearDown(router.dispose);
        expect(
          router.routeInformationProvider.value.uri.toString(),
          entry.value,
          reason: 'роутер обязан стартовать с цели: ${entry.key}',
        );
      }

      // Красное состояние до bf2c9998: стартовый маршрут не передан →
      // приложение открывается на списке чатов.
      final preFix = LizaApp.buildAppRouter();
      addTearDown(preFix.dispose);
      expect(preFix.routeInformationProvider.value.uri.toString(), '/');
    });

    // Перезагрузка вкладки уже НА цели (`#/rooms/…`) не должна перетриггерить
    // стартовый маршрут: go_router применяет initialLocation лишь при пустом
    // hash — парсер про hash не знает и отдаёт path-маршрут как есть.
    testWidgets('AC-5 непустой hash: маршрут из path отдаётся, решает роутер',
        (tester) async {
      expect(
        webInitialLocation(Uri.parse('https://web.liza.ru/i/$_code#/rooms')),
        '/i/$_code',
      );
    });
  });
}
