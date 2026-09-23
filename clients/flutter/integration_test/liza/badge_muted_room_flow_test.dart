import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/utils/chat_topology.dart';
import 'package:liza/widgets/matrix.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'liza_flows.dart';

/// Страж РЕГРЕССИИ (ledger:RL-badge-muted-room-excluded).
/// AC:RL-badge-muted-room-excluded/6
///
/// Сквозная проверка НА УСТРОЙСТВЕ клик-пути, ради которого писался фикс:
/// «отключить уведомления у чата» → новые сообщения в нём больше НЕ копят
/// счётчик приложения, а в обычном чате копят по-прежнему.
///
/// ⚠️ ЛОВУШКА ЛОЖНО-ЗЕЛЁНОГО (ради неё тест устроен именно так).
/// Наивная форма «открыть чат → замьютить → проверить, что счётчик 0» ничего
/// не доказывает: ОТКРЫТИЕ чата само шлёт read-ресипт и обнуляет
/// `notificationCount` независимо от мьюта. Поэтому мьютим, а затем просим
/// СОБЕСЕДНИКА прислать НОВОЕ сообщение — и проверяем, что оно не подняло
/// счётчик. Контроль (незамьюченный чат) обязателен: без него тест зелен и
/// тогда, когда счётчик сломан целиком и не растёт ни от чего.
///
/// ⚠️ Кнопка мьюта в UI ставит `PushRuleState.mentionsOnly`, а НЕ `dontNotify`
/// (`chat_settings_popup_menu.dart`). Прод 2026-09-09: 665 правил у 88 юзеров
/// против 367 у 29. Именно поэтому первая редакция фикса (только `dontNotify`)
/// покрывала меньшинство — тест обязан идти через РЕАЛЬНУЮ кнопку, а не через
/// прямой вызов SDK, иначе разойдётся с тем, что делает пользователь.

/// Ждёт истинности предиката короткими pump'ами. Локальный, а не в `liza_flows`:
/// общий файл правят параллельные сессии, а нужен он пока только здесь.
Future<void> _waitUntilTrue(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 20),
  String what = 'условие',
}) async {
  final end = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) {
      throw Exception('Не дождались: $what');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Liza e2e: замьюченный чат не копит счётчик приложения', () {
    testWidgets('мьют из меню чата → новые сообщения не поднимают счётчик', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });

      final actorB = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userB);
      final actorA = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userA);

      // Два чата: один замьютим, второй — КОНТРОЛЬ (должен продолжать считаться).
      final mutedRoomId = await actorB.createGroupChat(
        [actorA.userId],
        name: 'Мьют-чат бейджа',
      );
      final controlRoomId = await actorB.createGroupChat(
        [actorA.userId],
        name: 'Контроль-чат бейджа',
      );
      await actorA.joinRoom(mutedRoomId);
      await actorA.joinRoom(controlRoomId);

      app.main();
      await tester.ensureLizaHome();

      final matrix = Matrix.of(tester.element(find.byType(MaterialApp)));
      Room? roomOf(String id) =>
          matrix.client.rooms.where((r) => r.id == id).firstOrNull;

      // Открываем будущий мьют-чат и мьютим его через РЕАЛЬНОЕ меню.
      await tester.tap(find.text('Мьют-чат бейджа').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.tap(find.byIcon(Icons.more_vert_outlined).first);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      final muteItem = find.textContaining('уведомлени');
      await tester.waitUntil(muteItem, timeout: const Duration(seconds: 10));
      await tester.tap(muteItem.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Мьют доехал до сервера и вернулся в /sync.
      await _waitUntilTrue(
        tester,
        () => roomOf(mutedRoomId)?.pushRuleState != PushRuleState.notify,
        what: 'мьют доехал до сервера и вернулся в /sync',
      );

      // Уходим из чата, иначе последующие сообщения гасятся ресиптом активной
      // комнаты и тест снова станет пустым.
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // СОБЕСЕДНИК шлёт новое в ОБА чата.
      await actorB.sendText(mutedRoomId, 'после мьюта — считаться не должно');
      await actorB.sendText(controlRoomId, 'контроль — считаться должен');

      // Контроль обязан подняться: доказывает, что счётчик вообще живой.
      await _waitUntilTrue(
        tester,
        () => roomOf(controlRoomId)?.countsTowardAppBadge == true,
        timeout: const Duration(seconds: 30),
        what: 'КОНТРОЛЬНЫЙ чат поднял счётчик (иначе тест пустой)',
      );

      // Собственно инвариант: замьюченный чат в счёт НЕ идёт.
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(
        roomOf(mutedRoomId)?.countsTowardAppBadge,
        isFalse,
        reason: 'чат с отключёнными уведомлениями не должен копить счётчик '
            'приложения: пользователь в него не заходит и обнулить число '
            'не может',
      );

      await actorA.leaveAndForget(mutedRoomId);
      await actorA.leaveAndForget(controlRoomId);
      await actorB.leaveAndForget(mutedRoomId);
      await actorB.leaveAndForget(controlRoomId);
    });
  });
}
