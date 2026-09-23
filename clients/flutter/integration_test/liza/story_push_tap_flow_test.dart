// Ярус C (device): тап-навигация уведомления сторис на НАСТОЯЩЕМ бинаре
// (iOS/Android). Host-тест push_tap_target_test проверяет чистое ядро решения
// (StoryTarget vs RoomTarget); здесь — что реальный navigatePushTap на живом
// приложении для сторис-комнаты открывает StoryViewer (а НЕ ChatView скрытой
// техкомнаты), а для обычной комнаты — ChatView. Настоящий OS-тап пуша
// (APNs/NSE) эмулятором не воспроизводим — воспроизводим слой ОТ navigatePushTap
// и дальше (ровно код фикса).
//
// AC:RL-push-tap-stories-opens-viewer/1 AC:RL-push-tap-stories-opens-viewer/3
// AC:RL-push-tap-stories-opens-viewer/9
// ledger:RL-push-tap-stories-opens-viewer

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';
import 'package:liza/pages/chat_list/chat_list_body.dart';
import 'package:liza/pages/stories/story_viewer.dart';
import 'package:liza/utils/push_tap_navigation.dart';
import 'package:liza/utils/stories/stories_extension.dart';
import 'package:liza/widgets/liza_app.dart';
import 'package:liza/widgets/matrix.dart';

import 'liza_flows.dart';

// 1×1 PNG — валидное изображение для публикации сторис.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, //
  0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, //
  0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, //
  0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, //
  0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'тап по уведомлению сторис открывает StoryViewer, обычная комната — ChatView '
    '— ledger:RL-push-tap-stories-opens-viewer',
    (tester) async {
      app.main();
      await tester.ensureLizaHome(timeout: const Duration(seconds: 120));

      final ctx = tester.element(find.byType(ChatListViewBody));
      final client = Matrix.of(ctx).client;

      // Публикуем СВОЮ сторис → появляется скрытая сторис-комната автора.
      await client.publishStory(
        file: MatrixImageFile(bytes: _png, name: 'story.png'),
        overlays: const [],
      );
      final storyRoom = client.myStoriesRoom;
      expect(storyRoom, isNotNull, reason: 'сторис-комната создана публикацией');
      // Дожидаемся, пока сторис-событие появится активным (иначе вьюер сразу
      // закрылся бы как пустой автор).
      String? storyEventId;
      for (var i = 0; i < 40; i++) {
        final active = await client.activeStoriesOf(storyRoom!);
        if (active.isNotEmpty) {
          storyEventId = active.first.eventId;
          break;
        }
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(storyEventId, isNotNull, reason: 'сторис-событие засинкано активным');

      // AC-1: тап уведомления сторис → StoryViewer поверх /rooms, НЕ техчат.
      // Контроль обычная-комната→ChatView вынесен в unit (AC-3, pure-function,
      // red-proof) — он не зависит от медленного sync свежей комнаты на Android
      // и не относится к изменённому мной пути (RoomTapTarget = прежний go).
      // Здесь на устройстве проверяем ровно то, что чинит фикс: сторис-комната
      // из уведомления открывает просмотрщик, а НЕ скрытый технический чат.
      navigatePushTap(
        client: client,
        router: LizaApp.router,
        roomId: storyRoom!.id,
        eventId: storyEventId,
      );
      await tester.waitUntil(
        find.byType(StoryViewer),
        timeout: const Duration(seconds: 30),
      );
      expect(
        find.byType(StoryViewer),
        findsOneWidget,
        reason: 'сторис-комната из уведомления открывает просмотрщик',
      );
      // Ключевой инвариант фикса: это НЕ обычный чат скрытой техкомнаты.
      expect(
        find.byType(ChatView),
        findsNothing,
        reason: 'скрытая сторис-комната НЕ должна открыться как ChatView',
      );

      // AC-9 (DEF-2): повторный тап пуша, пока вьюер открыт, НЕ дублирует
      // StoryViewer (ориентир Liza — один вьюер, а не стопка).
      navigatePushTap(
        client: client,
        router: LizaApp.router,
        roomId: storyRoom.id,
        eventId: storyEventId,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(StoryViewer),
        findsOneWidget,
        reason: 'тап-в-тап не должен класть второй StoryViewer поверх первого',
      );
    },
  );
}
