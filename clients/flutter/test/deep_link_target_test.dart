// ledger:RL-deeplink-target-resolve
// AC:RL-deeplink-target-resolve/1 AC:RL-deeplink-target-resolve/2

import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/auth_proxy_service.dart';
import 'package:liza/utils/deep_link_target.dart';

void main() {
  group('deepLinkRoutePath', () {
    test('комната → путь чата', () {
      expect(
        deepLinkRoutePath(const DeepLinkRoom('!abc:server')),
        '/rooms/${Uri.encodeComponent('!abc:server')}',
      );
    });

    test('пространство → список пространства, не чат', () {
      expect(
        deepLinkRoutePath(const DeepLinkSpace('!spc:server')),
        '/rooms?spaceId=${Uri.encodeComponent('!spc:server')}',
      );
    });

    test('нейтральный исход → список чатов', () {
      expect(deepLinkRoutePath(const DeepLinkNeutral()), '/rooms');
    });

    test('ошибка несёт собственный путь экрана', () {
      expect(
        deepLinkRoutePath(const DeepLinkFailure('/invite/p_Xy/expired')),
        '/invite/p_Xy/expired',
      );
    });
  });

  group('resolveInviteTarget', () {
    test('target_kind=space даёт DeepLinkSpace, а не комнату', () async {
      final target = await resolveInviteTargetFromResult(
        result: InviteRedeemResult(
          status: 'joined',
          roomId: '!spc:server',
          targetKind: 'space',
        ),
        code: 'p_AbCdEfGh',
        awaitRoom: (roomId, {required expectSpace}) async => true,
        lookupRoomIsSpace: (roomId) => true,
      );
      expect(target, isA<DeepLinkSpace>());
    });

    test('комната не доехала в sync → нейтральный исход, не пустой чат',
        () async {
      final target = await resolveInviteTargetFromResult(
        result: InviteRedeemResult(status: 'joined', roomId: '!abc:server'),
        code: 'p_AbCdEfGh',
        awaitRoom: (roomId, {required expectSpace}) async => false,
        lookupRoomIsSpace: (roomId) => null,
      );
      expect(target, isA<DeepLinkNeutral>());
    });

    test('joined без room_id → нейтральный исход, не экран ошибки', () async {
      final target = await resolveInviteTargetFromResult(
        result: InviteRedeemResult(status: 'joined'),
        code: 'p_AbCdEfGh',
        awaitRoom: (roomId, {required expectSpace}) async => true,
        lookupRoomIsSpace: (roomId) => false,
      );
      expect(target, isA<DeepLinkNeutral>());
    });

    test('неизвестный статус → экран ошибки с кодом в пути', () async {
      final target = await resolveInviteTargetFromResult(
        result: InviteRedeemResult(status: 'nonsense'),
        code: 'p_AbCdEfGh',
        awaitRoom: (roomId, {required expectSpace}) async => true,
        lookupRoomIsSpace: (roomId) => false,
      );
      expect(deepLinkRoutePath(target), '/invite/p_AbCdEfGh/error');
    });
  });
}
