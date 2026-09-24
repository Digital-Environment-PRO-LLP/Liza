// ledger:RL-read-receipt-viewport-based
// AC:RL-read-receipt-viewport-based/13
//
// LABA-2632 (AC-13): «чат с 50 непрочитанными, открыть и не листать — все 50
// отмечаются прочитанными». Корень: при открытии лента грузит из БД 30
// событий, `m.fully_read` в них нет → `requestHistory` → onUpdate → updateView
// → setReadMarker() ДО прокрутки к сепаратору (`_scrolledUp == false`) →
// ПОЛНАЯ квитанция на последнее событие. При 12 непрочитанных догрузка не
// нужна — поэтому LABA-2604 проверку прошла.
//
// Оракул — СЕРВЕР, не виджет: `m.fully_read` пользователя A и его
// `notification_count` по /sync отдельного устройства. Пользователь видит
// ровно это: вернулся в чат — «Непрочитанное» на месте, плитка не обнулилась.

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';
import 'package:liza/pages/chat_list/chat_list_body.dart';
import 'package:liza/widgets/liza_app.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'liza_flows.dart';

Future<String?> _fullyRead(E2eActor actor, String roomId) async {
  try {
    final data = await actor.api.getAccountDataPerRoom(
      actor.userId,
      roomId,
      'm.fully_read',
    );
    return data['event_id'] as String?;
  } catch (_) {
    return null;
  }
}

Future<int?> _notificationCount(E2eActor actor, String roomId) async {
  final sync = await actor.api.sync(timeout: 0);
  return sync.rooms?.join?[roomId]?.unreadNotifications?.notificationCount;
}

/// ∀N: 12 — сепаратор в первых 30 событиях (без догрузки), 31 и 50 — за
/// границей 30 (`requestHistory`, детерминированное окно бага).
const _unreadCases = [12, 31, 50];

class _Seeded {
  final int n;
  final String roomId;
  final List<String> sent;
  final String stamp;
  _Seeded(this.n, this.roomId, this.sent, this.stamp);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LABA-2632: ∀N∈$_unreadCases непрочитанных → открыл, не листал → '
      'квитанция на видимое, НЕ на последнее; счётчик не обнулён', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'chat.fluffy.show_no_google': false,
    });

    final actorA = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userA);
    final actorB = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userB);

    final seeded = <_Seeded>[];
    try {
      for (final n in _unreadCases) {
        // Группа, а не DM: у пары A–B один DM, повторный переиспользуется.
        final roomId = await actorB.createGroupChat([
          actorA.userId,
        ], name: 'LABA-2632 N=$n');
        await actorA.joinRoom(roomId);
        final stamp = '${DateTime.now().millisecondsSinceEpoch}-$n';
        // Якорь: до него A всё прочитал (m.fully_read + m.read).
        final anchor = await actorB.sendText(roomId, 'anchor $stamp');
        await actorA.api.setReadMarker(
          roomId,
          mFullyRead: anchor,
          mRead: anchor,
        );
        final sent = <String>[];
        for (var i = 1; i <= n; i++) {
          sent.add(await actorB.sendText(roomId, 'unread $i · $stamp'));
        }
        seeded.add(_Seeded(n, roomId, sent, stamp));
      }

      app.main();
      await tester.ensureLizaHome();
      // Под integration_test движок не присылает lifecycle-сообщение, и
      // `lifecycleState` остаётся `inactive` → readableForeground=none глушит
      // ВСЕ квитанции (тест ложно-зелёный, баг маскируется). У пользователя
      // открытый чат — всегда `resumed`.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      for (final c in seeded) {
        final roomTile = find.textContaining('unread ${c.n} · ${c.stamp}');
        await tester.waitUntil(roomTile, timeout: const Duration(seconds: 60));
        await tester.tap(roomTile.first);
        await tester.waitUntil(find.byType(ChatView));

        // Не листаем: открытию, догрузке истории, позиционированию и
        // дебаунсу квитанции — с запасом.
        final settle = DateTime.now().add(const Duration(seconds: 8));
        while (DateTime.now().isBefore(settle)) {
          await tester.pump(const Duration(milliseconds: 200));
        }

        final fullyRead = await _fullyRead(actorA, c.roomId);
        final count = await _notificationCount(actorA, c.roomId);
        final index = c.sent.indexOf(fullyRead ?? '');
        debugPrint(
          'LABA-2632 oracle N=${c.n}: fully_read index=$index '
          '(last=${c.n - 1}) notification_count=$count',
        );

        expect(
          fullyRead,
          isNot(c.sent.last),
          reason: 'N=${c.n}: открыл и не листал — все помечены прочитанными',
        );
        expect(
          count,
          greaterThan(0),
          reason: 'N=${c.n}: сервер обнулил счётчик — квитанция на последнее',
        );
        // LABA-1894: квитанция при открытии ОБЯЗАНА уйти — на видимое
        // (строго после якоря), иначе бейдж залипает до докрута.
        expect(
          index,
          greaterThanOrEqualTo(0),
          reason:
              'N=${c.n}: квитанция на видимое после позиционирования '
              'не ушла',
        );

        LizaApp.router.go('/rooms');
        await tester.waitUntil(find.byType(ChatListViewBody));
        await tester.pump(const Duration(milliseconds: 500));
      }
    } finally {
      for (final c in seeded) {
        await actorA.leaveAndForget(c.roomId);
        await actorB.leaveAndForget(c.roomId);
      }
      await actorB.logout();
      await actorA.logout();
    }
  });
}
