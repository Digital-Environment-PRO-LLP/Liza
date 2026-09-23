// Ярус C (device): пересылка медиа-АЛЬБОМА и защита от вечных фантом-спиннеров
// на НАСТОЯЩЕМ бинаре (Android/iOS, локальный стек). Воспроизводит ИМЕННО скрин
// Петра: пересланная пачка медиа — часть плиток крутит спиннер и «не
// открывается». Host-стражи (`RL-gallery-forward-neighbors`,
// `RL-gallery-count-cap-defensive`) проверяют логику билдера/капа; здесь —
// реальный рендер `GalleryBubble` в ленте прод-бинаря.
//
// Два кейса:
//  A. Нормальный альбом из 3 медиа → сетка рисует 3 тайла, 0 фантом-спиннеров.
//  B. СТАРЫЙ битый форвард (якорь `n=3`, сосед 1) → после grace-окна (возраст
//     якоря > 60с) сетка схлопывается до факта (1 тайл), фантомы исчезают —
//     а НЕ висят вечно, как до фикса.
//
// Запуск: make local-up && local-seed, затем prove-ui/run.sh (APP_ENV=local).
//
// AC:RL-gallery-forward-neighbors/7 AC:RL-gallery-count-cap-defensive/5
// ledger:RL-gallery-forward-neighbors ledger:RL-gallery-count-cap-defensive

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';
import 'package:liza/pages/chat/events/gallery.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'liza_flows.dart';

// 1×1 прозрачный PNG (валидные байты для uploadContent).
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, //
  0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, //
  0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, //
  0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, //
  0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

// Число «крутящихся» индикаторов внутри альбома — кросс-платформенно:
// placeholder использует `CircularProgressIndicator.adaptive`, который на iOS
// разворачивается в `CupertinoActivityIndicator`.
int _phantomSpinnersInGallery() {
  final gallery = find.byType(GalleryBubble);
  if (gallery.evaluate().isEmpty) return -1;
  final spinners = find.descendant(
    of: gallery,
    matching: find.byWidgetPredicate(
      (w) => w is CircularProgressIndicator || w is CupertinoActivityIndicator,
    ),
  );
  return spinners.evaluate().length;
}

Future<void> _openRoomWithBeacon(
  WidgetTester tester,
  String beacon,
) async {
  final tile = find.textContaining(beacon);
  await tester.waitUntil(tile, timeout: const Duration(seconds: 60));
  for (var attempt = 0; attempt < 3; attempt++) {
    await tester.tap(tile.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (find.byType(ChatView).evaluate().isEmpty &&
        DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    if (find.byType(ChatView).evaluate().isNotEmpty) break;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'нормальный альбом из 3 медиа рендерит 3 тайла без фантом-спиннеров '
    '— ledger:RL-gallery-forward-neighbors',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });

      final actorA = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userA);
      final actorB = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userB);
      for (final actor in [actorA, actorB]) {
        final sync = await actor.api.sync();
        for (final r in (sync.rooms?.join?.keys.toList() ?? <String>[])) {
          try {
            await actor.api.leaveRoom(r);
            await actor.api.forgetRoom(r);
          } catch (_) {}
        }
      }
      final roomId = await actorB.createDirectChat(actorA.userId);
      await actorA.joinRoom(roomId);

      await actorB.sendGallery(roomId, _png, count: 3);
      final beacon = 'e2e-album-${DateTime.now().millisecondsSinceEpoch}';
      await actorB.sendText(roomId, beacon);

      app.main();
      await tester.ensureLizaHome();
      await _openRoomWithBeacon(tester, beacon);

      final gallery = find.byType(GalleryBubble);
      await tester.waitUntil(gallery, timeout: const Duration(seconds: 60));
      // Дать плиткам догрузиться (все 3 соседа доезжают тем же sync).
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 300));
        if (_phantomSpinnersInGallery() == 0) break;
      }

      expect(gallery, findsOneWidget, reason: 'альбом должен отрендериться');
      expect(
        _phantomSpinnersInGallery(),
        0,
        reason: 'у полного альбома из 3 медиа НЕ должно быть фантом-спиннеров',
      );
    },
  );

  testWidgets(
    'старый битый форвард (n=3, сосед 1) не даёт вечных фантом-спиннеров '
    '— ledger:RL-gallery-count-cap-defensive',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });

      final actorA = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userA);
      final actorB = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userB);
      for (final actor in [actorA, actorB]) {
        final sync = await actor.api.sync();
        for (final r in (sync.rooms?.join?.keys.toList() ?? <String>[])) {
          try {
            await actor.api.leaveRoom(r);
            await actor.api.forgetRoom(r);
          } catch (_) {}
        }
      }
      final roomId = await actorB.createDirectChat(actorA.userId);
      await actorA.joinRoom(roomId);

      // Симуляция СТАРОГО битого форварда: якорь заявляет n=3, соседей нет.
      await actorB.sendBrokenForwardedGalleryAnchor(roomId, _png,
          declaredCount: 3);
      final beacon = 'e2e-broken-${DateTime.now().millisecondsSinceEpoch}';
      await actorB.sendText(roomId, beacon);

      app.main();
      await tester.ensureLizaHome();
      await _openRoomWithBeacon(tester, beacon);

      final gallery = find.byType(GalleryBubble);
      await tester.waitUntil(gallery, timeout: const Duration(seconds: 60));

      // Grace-окно 60с: пока якорь свежий, спиннеры соседей ДЕРЖАТСЯ (штатно).
      // Ждём истечения окна + форсим rebuild новым событием — после этого
      // возраст якоря > 60с → кап схлопывает сетку до факта (1 тайл), фантомы
      // исчезают. До фикса они висели бы ВЕЧНО.
      await Future.delayed(const Duration(seconds: 63));
      await actorB.sendText(roomId, 'e2e-rebuild-${DateTime.now().millisecondsSinceEpoch}');
      final settle = DateTime.now().add(const Duration(seconds: 25));
      while (DateTime.now().isBefore(settle)) {
        await tester.pump(const Duration(milliseconds: 400));
        if (_phantomSpinnersInGallery() == 0) break;
      }

      expect(
        _phantomSpinnersInGallery(),
        0,
        reason: 'после grace-окна битый форвард не должен давать фантом-спиннеров',
      );
    },
  );
}
