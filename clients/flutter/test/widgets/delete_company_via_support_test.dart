// «Удалить компанию через поддержку» на РЕАЛЬНОМ меню шапки (LABA-2533).
//
// Компания = Synapse-инстанс: single_space_guard отвечает на leave 403, а
// удалить её = вывести сервер из эксплуатации — это делает поддержка. Админу
// своей компании вместо пустоты (LABA-2540) даём вход: диалог → DM с @support,
// в композере готовая заявка. Ничего не отправляется и не удаляется на месте.
//
// ledger:RL-delete-company-via-support
// guard.render:real-widget

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/reply_draft_store.dart';
import 'package:liza/utils/support_chat.dart';
import 'package:liza/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:liza/widgets/chat_settings_popup_menu.dart';
import 'package:liza/widgets/matrix.dart';

import '../utils/test_client.dart';

const _item = 'Удалить компанию через поддержку';
const _supportDm = '!support:bots.liza.ru';

void main() {
  late Client client;
  late SharedPreferences store;
  late List<String> started;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    client = await prepareTestClient(loggedIn: true);
    client.backgroundSync = false;
    store = await SharedPreferences.getInstance();
    FakeMatrixApi.calledEndpoints.clear();
    started = [];
    supportChatStartOverride = (mxid) async {
      started.add(mxid);
      return _supportDm;
    };
  });

  tearDown(() async {
    supportChatStartOverride = null;
    await client.dispose(closeDatabase: true);
  });

  /// Ahem-шрифт раздувает соседний пункт «Отключить уведомления» шире меню —
  /// артефакт тестового шрифта, глушим ровно overflow.
  void ignoreAhemOverflow() {
    final defaultOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('A RenderFlex overflowed')) {
        return;
      }
      defaultOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = defaultOnError);
  }

  /// [ownPowerLevel] — явная запись в `m.room.power_levels.users`; `null` —
  /// события нет, PL берётся по SDK-фолбэку (создатель 100, остальные 0).
  /// [creator] — sender `m.room.create`.
  /// Домен тест-клиента: «своя» компания = top-level space на нём
  /// (`foreignCompanyKind` сравнивает домены mxid и room_id).
  String ownDomain() => client.userID!.split(':').last;

  Room buildRoom({
    String? id,
    bool isSpace = true,
    String? chatType,
    Membership membership = Membership.join,
    int? ownPowerLevel,
    String creator = '@creator:example.invalid',
    String name = 'Компания 1',
  }) {
    id ??= '!company:${ownDomain()}';
    final room = Room(id: id, client: client, membership: membership);
    room.setState(
      Event(
        eventId: '\$create',
        senderId: creator,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        type: EventTypes.RoomCreate,
        content: {
          'creator': creator,
          if (chatType != null) 'com.liza.chat.type': chatType,
          if (isSpace) 'type': 'm.space',
        },
        room: room,
        stateKey: '',
      ),
    );
    room.setState(
      Event(
        eventId: '\$name',
        senderId: creator,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        type: EventTypes.RoomName,
        content: {'name': name},
        room: room,
        stateKey: '',
      ),
    );
    if (ownPowerLevel != null) {
      room.setState(
        Event(
          eventId: '\$pl',
          senderId: creator,
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
          type: EventTypes.RoomPowerLevels,
          content: {
            'users': {client.userID!: ownPowerLevel},
            'users_default': 0,
          },
          room: room,
          stateKey: '',
        ),
      );
    }
    client.rooms.add(room);
    return room;
  }

  /// Суб-пространство: делает [child] дочерним для нового top-level space.
  void nestUnder(Room child) {
    final parent = buildRoom(id: '!parent:${ownDomain()}', name: 'Родитель');
    parent.setState(
      Event(
        eventId: '\$child',
        senderId: '@creator:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        type: EventTypes.SpaceChild,
        content: {
          'via': [ownDomain()],
        },
        room: parent,
        stateKey: child.id,
      ),
    );
  }

  Future<void> pump(WidgetTester tester, Room room) async {
    ignoreAhemOverflow();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Matrix(
            clients: [client],
            store: store,
            child: Scaffold(
              appBar: AppBar(actions: [ChatSettingsPopupMenu(room, true)]),
            ),
          ),
        ),
        GoRoute(
          path: '/rooms/:roomId',
          builder: (context, state) =>
              Scaffold(body: Text('ROOM ${state.pathParameters['roomId']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('ru'),
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10n.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  // AC:RL-delete-company-via-support/1 — ∀ способ стать админом.
  testWidgets('админ своей компании: ровно один пункт, без корзины и выхода', (
    tester,
  ) async {
    final admins = <String, Room Function()>{
      'PL100 через power_levels.users': () => buildRoom(ownPowerLevel: 100),
      'создатель без power_levels': () => buildRoom(creator: client.userID!),
    };
    for (final entry in admins.entries) {
      await pump(tester, entry.value());
      await openMenu(tester);

      expect(find.text(_item), findsOneWidget, reason: entry.key);
      expect(
        find.byIcon(Icons.support_agent_outlined),
        findsOneWidget,
        reason: '${entry.key}: иконка поддержки, не корзина',
      );
      expect(
        find.byIcon(Icons.delete_outlined),
        findsNothing,
        reason: entry.key,
      );
      for (final stale in [
        'Выйти из чата',
        'Покинуть',
        'Отписаться',
        'Удалить чат',
      ]) {
        expect(find.text(stale), findsNothing, reason: '${entry.key}: $stale');
      }
      await teardownTree(tester);
      client.rooms.clear();
    }
  });

  // AC:RL-delete-company-via-support/2 — NEGATIVE, ∀ не-админ / не-своя.
  testWidgets('пункта нет у участника, в чужой компании и вне компании', (
    tester,
  ) async {
    final cases = <String, ({Room Function() build, String? instead})>{
      'PL0 своя компания': (
        build: () => buildRoom(ownPowerLevel: 0),
        instead: null,
      ),
      'PL50 своя компания': (
        build: () => buildRoom(ownPowerLevel: 50),
        instead: null,
      ),
      'чужая компания PL100': (
        build: () => buildRoom(id: '!c:other.invalid', ownPowerLevel: 100),
        instead: 'Отписаться',
      ),
      'суб-пространство PL100': (
        build: () {
          final sub = buildRoom(id: '!sub:${ownDomain()}', ownPowerLevel: 100);
          nestUnder(sub);
          return sub;
        },
        instead: 'Покинуть',
      ),
      'группа PL100': (
        build: () => buildRoom(
          id: '!g:${ownDomain()}',
          isSpace: false,
          ownPowerLevel: 100,
        ),
        instead: 'Выйти из чата',
      ),
      'приглашение в свою компанию, PL100': (
        build: () =>
            buildRoom(membership: Membership.invite, ownPowerLevel: 100),
        instead: null,
      ),
    };
    for (final entry in cases.entries) {
      await pump(tester, entry.value.build());
      await openMenu(tester);

      expect(find.text(_item), findsNothing, reason: entry.key);
      if (entry.value.instead case final instead?) {
        expect(find.text(instead), findsOneWidget, reason: entry.key);
      }
      await teardownTree(tester);
      client.rooms.clear();
    }
  });

  // AC:RL-delete-company-via-support/4
  testWidgets('диалог называет компанию и поддержку; отмена ничего не делает', (
    tester,
  ) async {
    await pump(tester, buildRoom(ownPowerLevel: 100));
    await openMenu(tester);
    await tester.tap(find.text(_item).last);
    await settle(tester);

    expect(find.textContaining('Компанию «Компания 1»'), findsOneWidget);
    expect(find.textContaining('поддержк'), findsWidgets);
    expect(find.text('Вы уверены?'), findsNothing);
    expect(
      find.widgetWithText(AdaptiveDialogAction, 'Перейти в поддержку'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(AdaptiveDialogAction, 'Отмена'));
    await settle(tester);

    expect(started, isEmpty, reason: 'отмена не создаёт DM');
    expect(store.getString('draft_$_supportDm'), isNull);
    expect(find.textContaining('ROOM '), findsNothing);
    await teardownTree(tester);
  });

  // AC:RL-delete-company-via-support/5 + AC:RL-delete-company-via-support/6
  // + AC:RL-delete-company-via-support/7
  testWidgets(
    'подтверждение: DM с @support, заявка в композере, ничего не отправлено',
    (tester) async {
      // Живой reply-контекст и форматирование чужой длины не должны прилипнуть к заявке.
      await store.setString('draftfmt_$_supportDm', '[{"s":0,"e":3,"b":1}]');
      await store.setString(ReplyDraftStore.keyFor(_supportDm), '\$old');

      await pump(tester, buildRoom(ownPowerLevel: 100));
      await openMenu(tester);
      await tester.tap(find.text(_item).last);
      await settle(tester);
      await tester.tap(
        find.widgetWithText(AdaptiveDialogAction, 'Перейти в поддержку'),
      );
      await settle(tester);
      await settle(tester);

      expect(started, ['@support:bots.liza.ru'], reason: 'ровно один старт DM');
      expect(
        find.text('ROOM $_supportDm'),
        findsOneWidget,
        reason: 'переход в DM',
      );

      final draft = store.getString('draft_$_supportDm');
      expect(draft, contains('Компания 1'));
      expect(draft, contains('!company:${ownDomain()}'));
      expect(store.getString('draftfmt_$_supportDm'), isNull);
      expect(store.getString(ReplyDraftStore.keyFor(_supportDm)), isNull);

      final called = FakeMatrixApi.calledEndpoints.keys.join('\n');
      for (final forbidden in ['/leave', '/forget', '/send/m.room.message']) {
        expect(
          called.contains(forbidden),
          isFalse,
          reason:
              '$forbidden: заявку отправляет пользователь, клиент ничего не удаляет',
        );
      }
      await teardownTree(tester);
    },
  );

  // AC:RL-delete-company-via-support/6 — собственный черновик не затирается.
  testWidgets(
    'существующий черновик в чате поддержки дописывается, не затирается',
    (tester) async {
      await store.setString('draft_$_supportDm', 'Здравствуйте, ещё вопрос');

      await pump(tester, buildRoom(ownPowerLevel: 100));
      await openMenu(tester);
      await tester.tap(find.text(_item).last);
      await settle(tester);
      await tester.tap(
        find.widgetWithText(AdaptiveDialogAction, 'Перейти в поддержку'),
      );
      await settle(tester);
      await settle(tester);

      final draft = store.getString('draft_$_supportDm')!;
      expect(draft, startsWith('Здравствуйте, ещё вопрос\n\n'));
      expect(draft, contains('Прошу удалить компанию «Компания 1»'));
      await teardownTree(tester);
    },
  );

  // AC:RL-delete-company-via-support/5 — ошибка старта: ни перехода, ни черновика.
  testWidgets('DM не создался: перехода нет и черновик не записан', (
    tester,
  ) async {
    supportChatStartOverride = (mxid) async {
      started.add(mxid);
      throw Exception('federation down');
    };
    await pump(tester, buildRoom(ownPowerLevel: 100));
    await openMenu(tester);
    await tester.tap(find.text(_item).last);
    await settle(tester);
    await tester.tap(
      find.widgetWithText(AdaptiveDialogAction, 'Перейти в поддержку'),
    );
    await settle(tester);
    await settle(tester);

    expect(started, hasLength(1));
    expect(find.textContaining('ROOM '), findsNothing);
    expect(store.getString('draft_$_supportDm'), isNull);
    await teardownTree(tester);
  });
}
