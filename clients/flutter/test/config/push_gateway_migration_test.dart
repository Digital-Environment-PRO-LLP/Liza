import 'package:flutter_test/flutter_test.dart';
import 'package:liza/config/setting_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('migrateLegacyPushGatewayUrl', () {
    test('переносит сохранённый известный прежний gateway Liza', () async {
      // domain-migration-legacy:flutter-push-gateway
      SharedPreferences.setMockInitialValues({
        AppSettings.pushNotificationsGatewayUrl.key: legacyPushGatewayUrl,
      });

      await AppSettings.init(loadWebConfigFile: false);

      expect(
        AppSettings.pushNotificationsGatewayUrl.value,
        canonicalPushGatewayUrl,
      );
    });

    test('не меняет пользовательский gateway', () {
      const customGateway =
          'https://matrix.gateway.unifiedpush.org/_matrix/push/v1/notify';
      expect(migrateLegacyPushGatewayUrl(customGateway), customGateway);
    });
  });
}
