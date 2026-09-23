import 'package:flutter_test/flutter_test.dart';
import 'package:liza/config/app_config.dart';

void main() {
  group('pushNotificationsAppId', () {
    test('совпадает со значением из окружения сборки', () {
      // app_id пушера обязан совпадать с ключом в sygnal.yaml.
      // Без --dart-define это старый bundle id; со сборкой под новый
      // аккаунт значение приезжает из PUSH_APP_ID. Тест зелёный в обоих
      // случаях — иначе прогон под новым аккаунтом «падал» бы штатно.
      const expected = String.fromEnvironment(
        'PUSH_APP_ID',
        defaultValue: 'ru.prodamus.liza',
      );
      expect(AppConfig.pushNotificationsAppId, expected);
    });

    test('является compile-time const', () {
      // const-контекст не скомпилируется, если значение перестанет быть
      // константой: background_push.dart использует его в const-выражениях.
      const value = AppConfig.pushNotificationsAppId;
      expect(value, isNotEmpty);
    });
  });

  group('production service domains', () {
    test('использует новые canonical API-адреса', () {
      expect(AppConfig.versionGateBaseUrl, 'https://versions.tech.liza.ru');
      expect(AppConfig.authProxyBaseUrl, 'auth.tech.liza.ru');
      expect(
        AppConfig.lizaBotApiBaseForHomeserver(null),
        'https://bot.tech.liza.ru',
      );
      expect(AppConfig.developerPortalUrl, 'https://developer.tech.liza.ru');
      expect(AppConfig.miniAppPaymentBaseUrl, 'https://store.app.tech.liza.ru');
      expect(AppConfig.shellHostBaseUrl, 'https://shell.app.tech.liza.ru');
      expect(AppConfig.transcribeHost, 'transcribe.tech.liza.ru');
    });
  });
}
