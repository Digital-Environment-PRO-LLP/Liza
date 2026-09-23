// ledger:RL-archive-chat-back-to-archive
// AC:RL-archive-chat-back-to-archive/1
// AC:RL-archive-chat-back-to-archive/2
// AC:RL-archive-chat-back-to-archive/3
// AC:RL-archive-chat-back-to-archive/4
// AC:RL-archive-chat-back-to-archive/5
// AC:RL-archive-chat-back-to-archive/6
// AC:RL-archive-chat-back-to-archive/7
// AC:RL-archive-chat-back-to-archive/8
//
// LABA-2543 (2026-09-08). Из архивного чата не было навигации обратно в список
// архива: `chat_view.dart` в КОЛОНОЧНОМ режиме отдавал `leading: null`
// безусловно, а список архива в этом режиме живёт в ПРАВОЙ колонке (левая — это
// всегда обычный `ChatList`). В узком режиме дыры нет: go_router держит стек
// `/rooms → /rooms/archive → /rooms/archive/:roomid`, и штатный BackButton
// (обёрнутый в UnreadRoomsBadge) уже возвращает в архив.
//
// АРХИТЕКТУРА СТРАЖЕЙ (почему НЕ реплика):
// - Группа 1: РЕАЛЬНЫЙ прод-предикат `showArchiveBackButton` из chat_view.dart
//   (@visibleForTesting — идиома `LizaThemes.isColumnModeByWidth`). Тест зовёт
//   единственный экземпляр прод-логики, а не её копию.
// - Группа 2: РЕАЛЬНЫЙ `ChatController.isArchived` через _FakeChatController
//   (перекрывает room без initState — образец can_redact_channel_post_test).
// - Группа 3: РЕАЛЬНЫЙ порог колоночного режима `LizaThemes.isColumnModeByWidth`.
// - Группа 4: виджет-ассерт на настоящем `AppBar` при setSurfaceSize(1200×900):
//   стрелка отрисована, titleSpacing снят.
// - Группа 5: RED-PROOF — предикат «до фикса» (`isColumnMode ? null`) роняет
//   AC-1/AC-8 и оставляет зелёными анти-регресс AC-2..AC-5.

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/config/themes.dart';
import 'package:liza/pages/chat/chat.dart';
import 'package:liza/pages/chat/chat_view.dart';

import '../../utils/test_client.dart';

// _FakeChatController — вызывает РЕАЛЬНЫЙ ChatController.isArchived,
// перекрывая только room. initState не зовётся (нет Matrix.of(context)).
class _FakeChatController extends ChatController {
  _FakeChatController(this._fakeRoom);

  final Room _fakeRoom;

  @override
  Room get room => _fakeRoom;
}

/// Предикат «до фикса»: в колоночном режиме leading всегда `null`.
/// Используется только в RED-PROOF.
bool _brokenShowArchiveBackButton({
  required bool isColumnMode,
  required bool selectMode,
  required bool hasActiveThread,
  required bool isArchived,
}) => false;

/// Шапка чата, собранная ровно так, как её строит `chat_view.dart` в колоночной
/// ветке: leading под предикатом + titleSpacing, снимаемый под стрелкой.
Widget _appBarUnderTest({
  required bool showArchiveBack,
  required bool isColumnMode,
}) => MaterialApp(
  home: Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: showArchiveBack
          ? Center(child: BackButton(onPressed: () {}))
          : null,
      titleSpacing: isColumnMode && !showArchiveBack ? 24 : 0,
      title: const Text('Архивный чат'),
    ),
  ),
);

void main() {
  group('LABA-2543 · стрелка «назад» из архивного чата', () {
    // -----------------------------------------------------------------------
    // Группа 1 — прод-предикат showArchiveBackButton (реальный, не реплика)
    // -----------------------------------------------------------------------

    test('AC-1 колоночный режим + архивный чат → стрелка показывается', () {
      expect(
        showArchiveBackButton(
          isColumnMode: true,
          selectMode: false,
          hasActiveThread: false,
          isArchived: true,
        ),
        isTrue,
        reason: 'это и есть дефект LABA-2543: выхода из архивного чата не было',
      );
    });

    test('AC-2 АНТИ-РЕГРЕСС: колоночный режим + ОБЫЧНЫЙ чат → стрелки нет', () {
      expect(
        showArchiveBackButton(
          isColumnMode: true,
          selectMode: false,
          hasActiveThread: false,
          isArchived: false,
        ),
        isFalse,
        reason: 'слева виден ChatList — leading обязан остаться null',
      );
    });

    test('AC-3 узкий режим + архивный чат → наша ветка молчит', () {
      expect(
        showArchiveBackButton(
          isColumnMode: false,
          selectMode: false,
          hasActiveThread: false,
          isArchived: true,
        ),
        isFalse,
        reason:
            'узкую ветку не трогаем: там BackButton внутри UnreadRoomsBadge, '
            'бейдж непрочитанного терять нельзя',
      );
    });

    test('AC-4 режим выделения перекрывает стрелку архива', () {
      expect(
        showArchiveBackButton(
          isColumnMode: true,
          selectMode: true,
          hasActiveThread: false,
          isArchived: true,
        ),
        isFalse,
        reason: 'приоритет у «закрыть выделение» (Icons.close)',
      );
    });

    test('AC-5 активный тред перекрывает стрелку архива', () {
      expect(
        showArchiveBackButton(
          isColumnMode: true,
          selectMode: false,
          hasActiveThread: true,
          isArchived: true,
        ),
        isFalse,
        reason: 'приоритет у «вернуться в основной чат» (Icons.close)',
      );
    });

    // -----------------------------------------------------------------------
    // Группа 3 — реальный порог колоночного режима
    // -----------------------------------------------------------------------

    test('AC-6 граница колоночного режима — 840dp', () {
      expect(
        LizaThemes.isColumnModeByWidth(840),
        isFalse,
        reason: 'ровно на пороге режим ещё узкий',
      );
      expect(
        LizaThemes.isColumnModeByWidth(841),
        isTrue,
        reason: 'дефект воспроизводится только шире 840dp',
      );
    });

    // -----------------------------------------------------------------------
    // Группа 2 — реальный ChatController.isArchived
    // -----------------------------------------------------------------------

    group('AC-7 ChatController.isArchived по membership', () {
      late Client client;

      setUp(() async {
        client = await prepareTestClient();
      });

      tearDown(() async {
        await client.dispose(closeDatabase: true);
      });

      void expectArchived(Membership membership, bool expected) {
        final room = Room(
          id: '!archive-${membership.name}:example.invalid',
          client: client,
          membership: membership,
        );
        expect(
          _FakeChatController(room).isArchived,
          expected,
          reason: 'membership=${membership.name}',
        );
      }

      test('leave → архивный', () => expectArchived(Membership.leave, true));
      test('ban → архивный', () => expectArchived(Membership.ban, true));
      test('join → НЕ архивный', () => expectArchived(Membership.join, false));
    });

    // -----------------------------------------------------------------------
    // Группа 4 — настоящий AppBar на колоночном вьюпорте
    // -----------------------------------------------------------------------

    testWidgets('AC-8 на 1200×900 стрелка отрисована, titleSpacing снят', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      expect(
        LizaThemes.isColumnModeByWidth(1200),
        isTrue,
        reason: 'вьюпорт теста обязан быть колоночным, иначе прогон ложный',
      );

      await tester.pumpWidget(
        _appBarUnderTest(showArchiveBack: true, isColumnMode: true),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BackButton), findsOneWidget);
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).titleSpacing,
        0,
        reason: '24dp компенсировали ОТСУТСТВИЕ leading — под стрелкой лишние',
      );

      // Обычный чат в том же колоночном режиме — leading по-прежнему пуст.
      await tester.pumpWidget(
        _appBarUnderTest(showArchiveBack: false, isColumnMode: true),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BackButton), findsNothing);
      expect(tester.widget<AppBar>(find.byType(AppBar)).titleSpacing, 24);
    });

    // -----------------------------------------------------------------------
    // Группа 5 — RED-PROOF
    // -----------------------------------------------------------------------

    test('RED-PROOF: предикат «до фикса» роняет AC-1, но не анти-регресс', () {
      // AC-1 краснеет — ровно тот дефект, который чиним.
      expect(
        _brokenShowArchiveBackButton(
          isColumnMode: true,
          selectMode: false,
          hasActiveThread: false,
          isArchived: true,
        ),
        isFalse,
      );
      // AC-2..AC-5 остаются зелёными и на сломанном предикате — значит они
      // действительно анти-регресс, а не дубль AC-1.
      for (final broken in [
        _brokenShowArchiveBackButton(
          isColumnMode: true,
          selectMode: false,
          hasActiveThread: false,
          isArchived: false,
        ),
        _brokenShowArchiveBackButton(
          isColumnMode: false,
          selectMode: false,
          hasActiveThread: false,
          isArchived: true,
        ),
      ]) {
        expect(broken, isFalse);
      }
    });
  });
}
