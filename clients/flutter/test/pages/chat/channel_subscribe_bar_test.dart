// ledger:RL-channel-peek-live-feed
// AC:RL-channel-peek-live-feed/4
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/channel_subscribe_bar.dart';
import '../../utils/test_client.dart';

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('показывает кнопку «Подписаться»', (tester) async {
    // runAsync — без него sqflite ffi (реальный I/O в prepareTestClient)
    // виснет на 10 минут внутри fake-async зоны testWidgets: тот же КЛАСС
    // ловушки, что задокументирован в input_bar_menu_suggestion_test.dart
    // (Matrix Client + фейк-таймеры testWidgets), но РЕШЕНИЕ другое: там
    // testWidgets не используется вовсе (голый test()), здесь виджет-тест
    // обязателен — runAsync + pump(Duration) — паттерн новый для проекта.
    late final Client client;
    await tester.runAsync(() async {
      client = await prepareTestClient(loggedIn: true);
    });
    addTearDown(client.dispose);

    await tester.pumpWidget(
      _wrap(
        ChannelSubscribeBar(
          roomId: '!channel:example.invalid',
          client: client,
          onSubscribed: () {},
        ),
      ),
    );
    // Navigator строит начальный маршрут асинхронно (анимация перехода) —
    // pump с durations прогоняет её до конца без pumpAndSettle (который
    // висит из-за фоновых таймеров живого Client, см. выше).
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Подписаться'), findsOneWidget);
  });
}
