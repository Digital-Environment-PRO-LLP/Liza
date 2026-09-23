import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/utils/background_push.dart';
import 'package:liza/config/app_config.dart';

import 'liza_flows.dart';

/// Device-flow для фикса Android-pusher app_id (RL-android-push-app-id).
///
/// Живой прогон на РЕАЛЬНЫХ iOS+Android: `app.main()` + логин `ensureLizaHome()`
/// исполняет реальный `setupPush()` в жизненном цикле приложения — на Android он
/// зовёт `androidDataMessageAppId` (изменённый прод-путь). Проверяем, что:
///   1) деривация app_id на живом рантайме = base + '.data_message' (прод-код,
///      не реплика) — ловит регрессию суффикса;
///   2) приложение доходит до Home на обеих платформах, т.е. изменённый
///      `background_push.dart` не ломает старт/пуш-сетап на устройстве.
///
/// Полную сквозную ДОСТАВКУ пуша device-flow не покрывает (iOS-симулятор не
/// выдаёт remote-push токен; FCM на эмуляторе требует google-services) — это
/// manual AC-5/AC-6 реестра, проверено серверным смоуком против боевого FCM.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android регистрирует pusher com.prodamus.laba.liza.data_message '
      '(сборка с PUSH_APP_ID фикса), старт не ломается', (tester) async {
    // Прод-код деривации на РЕАЛЬНОМ устройстве (не host-VM).
    expect(
      BackgroundPush.androidDataMessageAppId('com.prodamus.laba.liza'),
      'com.prodamus.laba.liza.data_message',
    );

    // НЕ тавтология: прогон ОБЯЗАН идти с --dart-define=PUSH_APP_ID=
    // com.prodamus.laba.liza (как build-android.sh после фикса). Без него дефолт =
    // ru.prodamus.liza (регрессия миграции) → этот ассерт КРАСНЫЙ. Так device-flow
    // воспроизводит именно СБОРКУ ФИКСА, а не дефолтную (баговую).
    if (defaultTargetPlatform == TargetPlatform.android) {
      expect(
        AppConfig.pushNotificationsAppId,
        'com.prodamus.laba.liza',
        reason: 'Android-сборка обязана нести PUSH_APP_ID=com.prodamus.laba.liza '
            '(build-android.sh), иначе pusher уедет на несуществующий '
            'ru.prodamus.liza.data_message',
      );
      // app_id, который РЕАЛЬНО зарегистрирует setupPusher на этой сборке.
      expect(
        BackgroundPush.androidDataMessageAppId(AppConfig.pushNotificationsAppId),
        'com.prodamus.laba.liza.data_message',
      );
    }

    // Реальный запуск: setupPush() отрабатывает в лайфцикле; на Android дергает
    // изменённый путь и постит pusher с этим app_id (видно в логе прогона).
    // Доходим до Home — значит старт/пуш-сетап не сломан.
    app.main();
    await tester.ensureLizaHome();
    debugPrint('[push_app_id_flow] Home достигнут, base='
        '${AppConfig.pushNotificationsAppId} '
        'isAndroid=${defaultTargetPlatform == TargetPlatform.android}');
  });
}
