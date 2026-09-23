import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/utils/monitoring.dart';

import 'liza_flows.dart';

/// Device-flow для клиентского push-health сигнала (RL-push-health-signal-client).
///
/// Правка `background_push.dart` — телеметрическая (fire-and-forget
/// `Monitoring.reportPushIssue`), user-visible interaction-эффекта у неё нет
/// (сигнал — no-op без DSN-сборки; полноту даёт СЕРВЕРНЫЙ слой). Поэтому device-flow
/// здесь = РЕГРЕСС-СМОУК изменённого прод-пути на РЕАЛЬНЫХ iOS+Android:
///   1) `Monitoring.pushIssueTitle` на живом рантайме устройства (прод-код, не
///      host-VM) даёт стабильный PII-safe маркер;
///   2) `app.main()` + `ensureLizaHome()` исполняет реальный `setupPush()` в
///      лайфцикле — на Android без google-services `getToken()` вернёт null и
///      отработает ДОБАВЛЕННАЯ ветка `reportPushIssue('fcm_token_unavailable')`
///      перед `_noFcmWarning`; доход до Home доказывает, что телеметрия НЕ ломает
///      старт/пуш-сетап на устройстве.
///
/// Сам факт эмита в мониторинг device-flow не наблюдает (no-op без DSN) — это
/// manual AC-5 реестра (нативная release-сборка + прод-DSN). Первичный серверный
/// детектор (`analytics.pusher_app_id_dist`) — не клиентский, проверяется отдельно.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('push-health: маркер стабилен на устройстве + старт/пуш-сетап не '
      'ломается изменённым background_push', (tester) async {
    // Прод-код построения title на РЕАЛЬНОМ устройстве (не host-VM). Контракт с
    // notifier/поллером (`[push-fail]`), без счётчика/PII.
    expect(
      Monitoring.pushIssueTitle('fcm_token_unavailable'),
      '[push-fail] reason=fcm_token_unavailable',
    );
    expect(Monitoring.pushFailurePrefix, '[push-fail]');
    // Инертность: без DSN-сборки reportPushIssue — no-op, не бросает (тот же гейт,
    // что защищает от эмита из фонового FCM-изолята).
    expect(Monitoring.isActive, isFalse);
    Monitoring.reportPushIssue('fcm_token_unavailable'); // не должно бросить

    // Реальный запуск: setupPush() отрабатывает в лайфцикле, исполняя изменённый
    // background_push.dart (в т.ч. добавленную ветку fcm_token_unavailable на
    // Android-эмуляторе без Firebase). Доходим до Home — старт/пуш-сетап целы.
    app.main();
    await tester.ensureLizaHome();
    debugPrint('[push_health_signal_flow] Home достигнут, '
        'isAndroid=${defaultTargetPlatform == TargetPlatform.android}');
  });
}
