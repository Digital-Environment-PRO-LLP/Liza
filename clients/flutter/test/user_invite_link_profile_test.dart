// ledger:RL-user-invite-link-opens-profile
// AC:RL-user-invite-link-opens-profile/2 AC:RL-user-invite-link-opens-profile/3
// AC:RL-user-invite-link-opens-profile/4 AC:RL-user-invite-link-opens-profile/8
// AC:RL-user-invite-link-opens-profile/11
// AC:RL-deeplink-target-resolve/1
//
// Резолв user-инвайта («Пригласить друзей», LABA-2551): цель — профиль
// пользователя, а НЕ немедленный DM. Red-proof: на коде до фикса
// `resolveInviteTarget` звал `client.startDirectChat` — для своей ссылки
// Synapse отвечал 403 и цель схлопывалась в DeepLinkNeutral («список чатов»),
// для чужой — createRoom+invite уходили до первого сообщения; тест на счётчик
// createRoom == 0 и на тип DeepLinkUser краснел.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:liza/utils/auth_proxy_service.dart';
import 'package:liza/utils/deep_link_target.dart';

import 'utils/test_client.dart';

const _bob = '@bob:example.invalid';
const _alice = '@alice:example.invalid';

AuthProxyService _redeemService(String targetUserId) => AuthProxyService(
  httpClient: MockClient((request) async {
    expect(request.url.path, endsWith('/redeem'));
    return http.Response(
      jsonEncode({
        'status': 'user_invite',
        'target_user_id': targetUserId,
        'server_name': 'example.invalid',
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

void main() {
  test('createUserInvite отправляет homeserver цели, а не автора', () async {
    Map<String, dynamic>? sentBody;
    final service = AuthProxyService(
      httpClient: MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'code': 'p_crosshs001',
            'url': 'https://me.liza.ru/i/p_crosshs001',
            'created_at': '2026-09-17T05:06:58Z',
            'created_by_mxid': '@alice:synapse.example',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await service.createUserInvite(
      targetUserId: '@bob:user.liza.ru',
      accessToken: 'token',
    );

    expect(sentBody?['server_name'], 'user.liza.ru');
    expect(sentBody?['target_user_id'], '@bob:user.liza.ru');
    expect(sentBody?['target_type'], 'user');
  });

  group('resolveInviteTargetFromResult user_invite', () {
    // AC-2: чужая ссылка → DeepLinkUser с mxid цели.
    test('чужая ссылка → DeepLinkUser(target), не комната', () async {
      final target = await resolveInviteTargetFromResult(
        result: const InviteRedeemResult(
          status: 'user_invite',
          targetUserId: _bob,
        ),
        code: 'd_KH3HsAxgUB',
        awaitRoom: (roomId, {required expectSpace}) async =>
            fail('user-инвайт не ждёт комнату'),
        lookupRoomIsSpace: (roomId) => null,
      );
      expect(target, isA<DeepLinkUser>());
      expect((target as DeepLinkUser).userId, _bob);
      expect(deepLinkRoutePath(target), '/rooms');
    });

    // AC-3: своя ссылка → DeepLinkUser(self) — раньше 403 → «список чатов».
    test('своя ссылка → DeepLinkUser(self), а не нейтральный исход', () async {
      final target = await resolveInviteTargetFromResult(
        result: const InviteRedeemResult(
          status: 'user_invite',
          targetUserId: _alice,
        ),
        code: 'd_KH3HsAxgUB',
        awaitRoom: (roomId, {required expectSpace}) async => true,
        lookupRoomIsSpace: (roomId) => null,
      );
      expect(target, const TypeMatcher<DeepLinkUser>());
      expect((target as DeepLinkUser).userId, _alice);
    });

    test(
      'user_invite без target_user_id → нейтральный исход, не ошибка',
      () async {
        final target = await resolveInviteTargetFromResult(
          result: const InviteRedeemResult(status: 'user_invite'),
          code: 'd_KH3HsAxgUB',
          awaitRoom: (roomId, {required expectSpace}) async => true,
          lookupRoomIsSpace: (roomId) => null,
        );
        expect(target, isA<DeepLinkNeutral>());
      },
    );
  });

  group('deepLinkSideEffect', () {
    // AC-4: exhaustive switch — карточка только у DeepLinkUser.
    test('DeepLinkUser → OpenUserProfile(userId)', () {
      final effect = deepLinkSideEffect(const DeepLinkUser(_bob));
      expect(effect, isA<OpenUserProfile>());
      expect((effect as OpenUserProfile).userId, _bob);
    });

    test('остальные цели побочного эффекта не имеют', () {
      const targets = <DeepLinkTarget>[
        DeepLinkRoom('!r:s'),
        DeepLinkSpace('!s:s'),
        DeepLinkStory('!r:s', r'$e'),
        DeepLinkMiniApp(opened: true),
        DeepLinkNeutral(),
        DeepLinkFailure('/invite/x/error'),
      ];
      for (final target in targets) {
        expect(deepLinkSideEffect(target), isNull, reason: '$target');
      }
    });
  });

  group('resolveInviteTarget с живым клиентом', () {
    late Client client;
    var createRoomCalls = 0;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
      createRoomCalls = 0;
      final api = (client.httpClient as dynamic).inner as FakeMatrixApi;
      api.api['POST']!['/client/v3/createRoom'] = (_) {
        createRoomCalls++;
        return {'room_id': '!created:example.invalid'};
      };
    });

    tearDown(() => client.dispose());

    // AC-2 (red-proof по счётчику): ноль createRoom при резолве чужой ссылки.
    test('чужая ссылка: DeepLinkUser и НИ ОДНОГО createRoom', () async {
      final target = await resolveInviteTarget(
        client: client,
        service: _redeemService(_bob),
        code: 'd_KH3HsAxgUB',
      );
      expect(target, isA<DeepLinkUser>());
      expect(createRoomCalls, 0);
      expect(client.getDirectChatFromUserId(_bob), isNull);
    });

    // AC-3: своя ссылка не уходит в 403-ветку — createRoom не вызывается.
    test('своя ссылка: DeepLinkUser(self), createRoom не вызывался', () async {
      final target = await resolveInviteTarget(
        client: client,
        service: _redeemService(client.userID!),
        code: 'd_KH3HsAxgUB',
      );
      expect(target, isA<DeepLinkUser>());
      expect((target as DeepLinkUser).userId, client.userID);
      expect(createRoomCalls, 0);
    });
  });
}
