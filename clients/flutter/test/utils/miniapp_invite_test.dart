// Стражи mini-app-инвайта: индивидуальный чат приложения по ссылке + кнопка
// запуска в чате-лаунчере.
// ledger:RL-miniapp-invite-individual-room
//
// Инварианты:
//  1. Ссылка на mini App возвращает status=miniapp_invite + app-метаданные
//     (НЕ joined в общую комнату) — каждый получатель заводит свой чат.
//  2. Кнопка «Открыть» в композере показывается ⇔ в комнате есть валидный
//     com.liza.miniapp.config с непустым https-app_url.

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/auth_proxy_service.dart';
import 'package:liza/utils/miniapp_room.dart';

void main() {
  group('InviteRedeemResult.fromJson — miniapp_invite (wire contract)', () {
    test('парсит app-поля mini-app-инвайта', () {
      final r = InviteRedeemResult.fromJson({
        'status': 'miniapp_invite',
        'server_name': 'synapse.liza.laba.prodamus.tech',
        'app_id': 'stack-001',
        'app_url': 'https://example.com/app',
        'app_name': 'Магазин',
        'app_type': 'third_party',
      });
      expect(r.status, 'miniapp_invite');
      expect(r.appId, 'stack-001');
      expect(r.appUrl, 'https://example.com/app');
      expect(r.appName, 'Магазин');
      expect(r.appType, 'third_party');
      // Это не room-join: room_id отсутствует.
      expect(r.roomId, isNull);
    });

    test('обычный room-инвайт не несёт app-полей', () {
      final r = InviteRedeemResult.fromJson({
        'status': 'joined',
        'room_id': '!r:synapse.liza.laba.prodamus.tech',
        'target_kind': 'group',
      });
      expect(r.status, 'joined');
      expect(r.appUrl, isNull);
      expect(r.appId, isNull);
    });

    test('deep-link app_start_path прокидывается из ответа redeem', () {
      final r = InviteRedeemResult.fromJson({
        'status': 'miniapp_invite',
        'server_name': 'synapse.liza.laba.prodamus.tech',
        'app_id': 'stack-001',
        'app_url': 'https://example.com/app',
        'app_start_path': '#!/tproduct/2413257851-1500470245901',
      });
      expect(r.appStartPath, '#!/tproduct/2413257851-1500470245901');
    });

    test('без deep-link app_start_path == null', () {
      final r = InviteRedeemResult.fromJson({
        'status': 'miniapp_invite',
        'app_url': 'https://example.com/app',
      });
      expect(r.appStartPath, isNull);
    });
  });

  group('miniAppLaunchFromConfig — кнопка «Открыть» в чате-лаунчере', () {
    test('валидный конфиг → параметры запуска', () {
      final launch = miniAppLaunchFromConfig({
        'app_id': 'stack-001',
        'app_url': 'https://example.com/app',
        'app_name': 'Магазин',
        'app_type': 'third_party',
      });
      expect(launch, isNotNull);
      expect(launch!.appUrl, 'https://example.com/app');
      expect(launch.appId, 'stack-001');
      expect(launch.appName, 'Магазин');
      expect(launch.appType, 'third_party');
    });

    test('дефолты для отсутствующих полей (кроме app_url)', () {
      final launch = miniAppLaunchFromConfig({
        'app_url': 'https://example.com/app',
      });
      expect(launch, isNotNull);
      expect(launch!.appId, 'unknown');
      expect(launch.appName, 'Mini App');
      expect(launch.appType, 'third_party');
    });

    test('app_start_path из конфига валидируется как граница', () {
      final ok = miniAppLaunchFromConfig({
        'app_url': 'https://example.com/app',
        'app_start_path': '#!/tproduct/123',
      });
      expect(ok!.appStartPath, '#!/tproduct/123');

      // Небезопасный хвост из недоверенного state-event → главная (пусто).
      final bad = miniAppLaunchFromConfig({
        'app_url': 'https://example.com/app',
        'app_start_path': 'https://evil.com',
      });
      expect(bad!.appStartPath, '');

      // Отсутствует → пусто.
      final none = miniAppLaunchFromConfig({
        'app_url': 'https://example.com/app',
      });
      expect(none!.appStartPath, '');
    });

    test('нет конфига → нет кнопки', () {
      expect(miniAppLaunchFromConfig(null), isNull);
    });

    test('пустой/невалидный app_url → нет кнопки', () {
      expect(miniAppLaunchFromConfig({'app_url': ''}), isNull);
      expect(miniAppLaunchFromConfig({'app_id': 'x'}), isNull);
      expect(miniAppLaunchFromConfig({'app_url': 123}), isNull);
    });
  });
}
