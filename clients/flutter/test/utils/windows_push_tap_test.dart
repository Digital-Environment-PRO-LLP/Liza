import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/notification_background_handler.dart';
import 'package:liza/utils/push_helper.dart';

import 'test_client.dart';

// Клик по уведомлению на Windows открывает чат (GlitchTip #2069, 2026-09-25,
// сборка 3764): плагин `flutter_local_notifications_windows` 1.0.3 объявляет
// «действием» любую активацию с аргументами, а аргументы тоста — наш payload.
// Клик по телу приходил как `selectedNotificationAction` с `actionId = payload`,
// `notificationTap` бросал «action but no action ID», и чат не открывался.
//
// ledger:RL-windows-push-tap-opens-room
void main() {
  final payload = LizaPushPayload(
    'Liza Widget Tests',
    '!room:example.invalid',
    r'$event',
  ).toString();

  // Форма ответа, которую реально отдаёт Windows-плагин на клик по телу тоста.
  NotificationResponse windowsBodyClick() => NotificationResponse(
    notificationResponseType:
        NotificationResponseType.selectedNotificationAction,
    payload: payload,
    actionId: payload,
  );

  group('effectiveNotificationResponseType', () {
    test('AC:RL-windows-push-tap-opens-room/1 — ∀ форм ответа: неизвестное '
        '«действие» = тап; наши действия и обычный тап не меняются', () {
      // Windows: клик по телу, actionId = payload.
      expect(
        effectiveNotificationResponseType(windowsBodyClick()),
        NotificationResponseType.selectedNotification,
      );
      // «Действие» без id вовсе.
      expect(
        effectiveNotificationResponseType(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
            payload: payload,
          ),
        ),
        NotificationResponseType.selectedNotification,
      );
      // Настоящие кнопки Android/iOS — остаются действиями.
      for (final action in LizaNotificationActions.values) {
        expect(
          effectiveNotificationResponseType(
            NotificationResponse(
              notificationResponseType:
                  NotificationResponseType.selectedNotificationAction,
              payload: payload,
              actionId: action.name,
            ),
          ),
          NotificationResponseType.selectedNotificationAction,
          reason: action.name,
        );
      }
      // Обычный тап — как был.
      expect(
        effectiveNotificationResponseType(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: payload,
          ),
        ),
        NotificationResponseType.selectedNotification,
      );
    });
  });

  test('AC:RL-windows-push-tap-opens-room/2 — notificationTap на Windows-клике '
      'идёт веткой тапа, а не бросает «action but no action ID»', () async {
    final client = await prepareTestClient(loggedIn: true);
    // Без роутера ветка тапа завершается тихо (фоновый режим) — ровно это и
    // доказывает, что ответ ушёл в selectedNotification: ветка действия
    // бросила бы исключение ДО любых проверок роутера.
    await expectLater(
      notificationTap(windowsBodyClick(), clients: [client]),
      completes,
    );
    await client.dispose(closeDatabase: false);
  });
}
