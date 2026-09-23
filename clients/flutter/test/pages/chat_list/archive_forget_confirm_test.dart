// Предохранитель на удалении архивного чата (LABA-2544) — на РЕАЛЬНОМ
// ChatListItem, а не на реплике: сам `forget()` необратим без повторного join,
// поэтому проверять надо именно ту кнопку, по которой пользователь промахивается,
// и именно тот колбэк, который дальше зовёт room.forget().
//
// ledger:RL-archive-forget-confirm

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat_list/chat_list_item.dart';
import 'package:liza/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:liza/widgets/matrix.dart';

import '../../utils/test_client.dart';

void main() {
  late Client client;
  late SharedPreferences store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    client = await prepareTestClient(loggedIn: true);
    // Фоновый sync-цикл держит таймер живым и роняет тест на
    // «A Timer is still pending even after the widget tree was disposed».
    client.backgroundSync = false;
    store = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  /// Архивный чат: пользователь уже вышел (membership leave), поэтому такая
  /// комната и попадает в список `Archive`.
  Room buildArchivedRoom({
    required bool isDirect,
    String id = '!a:example.invalid',
  }) {
    final room = Room(id: id, client: client, membership: Membership.leave);
    room.setState(
      Event(
        eventId: '\$create',
        senderId: '@creator:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        type: EventTypes.RoomCreate,
        content: const {'creator': '@creator:example.invalid'},
        room: room,
        stateKey: '',
      ),
    );
    room.setState(
      Event(
        eventId: '\$name',
        senderId: '@creator:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        type: EventTypes.RoomName,
        content: {'name': isDirect ? 'Алиса' : 'Групповой чат'},
        room: room,
        stateKey: '',
      ),
    );
    if (isDirect) {
      room.setState(
        Event(
          eventId: '\$member',
          senderId: '@bob:example.invalid',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
          type: EventTypes.RoomMember,
          content: const {'membership': 'join'},
          room: room,
          stateKey: '@bob:example.invalid',
        ),
      );
    }
    return room;
  }

  Future<void> pump(
    WidgetTester tester,
    Room room,
    VoidCallback onForget,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10n.supportedLocales,
        home: Matrix(
          clients: [client],
          store: store,
          child: Scaffold(
            body: ChatListItem(room, onTap: () {}, onForget: onForget),
          ),
        ),
      ),
    );
    // Matrix отдаёт child не сразу (async init) — несколько pump'ов, чтобы
    // дерево устоялось.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tapTrash(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.delete_outlined));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tapDialogButton(WidgetTester tester, String label) async {
    final button = find.widgetWithText(AdaptiveDialogAction, label);
    expect(button, findsOneWidget, reason: 'кнопка «$label» в диалоге');
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  }

  // AC:RL-archive-forget-confirm/1 — DM: диалог ДО вызова onForget.
  testWidgets('личный чат: тап по корзине открывает подтверждение, не удаляя', (
    tester,
  ) async {
    var forgetCalls = 0;
    await pump(tester, buildArchivedRoom(isDirect: true), () => forgetCalls++);
    await tapTrash(tester);

    expect(
      find.text(
        'Чат исчезнет из архива, история станет вам недоступна. '
        'У собеседника чат сохранится.',
      ),
      findsOneWidget,
    );
    expect(forgetCalls, 0, reason: 'forget не зовётся до подтверждения');
    await tapDialogButton(tester, 'Отмена');
    await teardownTree(tester);
  });

  // AC:RL-archive-forget-confirm/1 — групповой чат: тот же предохранитель.
  //
  // ledger:RL-leave-chat-not-delete
  // AC:RL-leave-chat-not-delete/9 — корзина «Архива» остаётся ЕДИНСТВЕННЫМ
  // местом, где слово «Удалить» правдиво: здесь действительно зовётся
  // Room.forget(). Ключ `deleteChat` до LABA-2540 обслуживал ещё и пункт
  // выхода (room.leave()), и правка его значения испортила бы этот диалог —
  // поэтому ключ разведён, а тест закрепляет, что здесь текст не поехал.
  testWidgets('групповой чат: тап по корзине открывает подтверждение', (
    tester,
  ) async {
    var forgetCalls = 0;
    await pump(tester, buildArchivedRoom(isDirect: false), () => forgetCalls++);
    await tapTrash(tester);

    expect(find.text('Удалить чат'), findsOneWidget);
    expect(
      find.text(
        'Чат исчезнет из архива, история станет вам недоступна. '
        'У собеседника чат сохранится.',
      ),
      findsOneWidget,
      reason: 'правдивое «удалить» на forget() не должно было пострадать',
    );
    expect(forgetCalls, 0);
    await tapDialogButton(tester, 'Отмена');
    await teardownTree(tester);
  });

  // AC:RL-archive-forget-confirm/2 — отмена не удаляет.
  testWidgets('«Отмена» закрывает диалог и НЕ вызывает удаление', (
    tester,
  ) async {
    var forgetCalls = 0;
    await pump(tester, buildArchivedRoom(isDirect: true), () => forgetCalls++);
    await tapTrash(tester);
    await tapDialogButton(tester, 'Отмена');

    expect(forgetCalls, 0, reason: 'отказ не удаляет чат');
    expect(
      find.byType(AdaptiveDialogAction),
      findsNothing,
      reason: 'диалог закрыт',
    );
    expect(
      find.byIcon(Icons.delete_outlined),
      findsOneWidget,
      reason: 'строка чата осталась на экране',
    );
    await teardownTree(tester);
  });

  // AC:RL-archive-forget-confirm/3 — подтверждение удаляет ровно один раз.
  testWidgets('«Да» вызывает удаление ровно один раз', (tester) async {
    var forgetCalls = 0;
    await pump(tester, buildArchivedRoom(isDirect: true), () => forgetCalls++);
    await tapTrash(tester);
    await tapDialogButton(tester, 'Да');

    expect(forgetCalls, 1);
    await teardownTree(tester);
  });

  // AC:RL-archive-forget-confirm/4 — кнопка подтверждения окрашена как
  // деструктивная (isDestructive: true), иначе предохранитель не читается как
  // предупреждение.
  testWidgets('кнопка «Да» окрашена в error-цвет', (tester) async {
    await pump(tester, buildArchivedRoom(isDirect: true), () {});
    await tapTrash(tester);

    final okText = tester.widget<Text>(
      find.descendant(
        of: find.widgetWithText(AdaptiveDialogAction, 'Да'),
        matching: find.text('Да'),
      ),
    );
    final errorColor = Theme.of(
      tester.element(find.text('Да')),
    ).colorScheme.error;
    expect(okText.style?.color, errorColor);

    await tapDialogButton(tester, 'Отмена');
    await teardownTree(tester);
  });
}
