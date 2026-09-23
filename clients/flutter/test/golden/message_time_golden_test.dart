import 'package:flutter/material.dart';

import 'package:alchemist/alchemist.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/config/setting_keys.dart';
import 'package:liza/pages/chat/events/message_time.dart';

// Страж реестра регрессии: ledger:RL-message-time (см. tests/registry/).
// Golden Яруса 0 на футер времени сообщения (Liza-стиль): HH:MM у каждого
// сообщения + у своих индикатор доставки/прочтения рядом со временем.
//
// Рендерим РЕАЛЬНЫЙ виджет [MessageTime] (не копию): правка раскладки/иконок/
// маппинга статусов детерминированно роняет этот эталон. Виджет «глупый»
// (примитивы вместо Event), поэтому golden не требует Matrix Client.

Widget _scenario(MessageTime child) => Padding(
  padding: const EdgeInsets.all(8),
  child: child,
);

const _mutedColor = Color(0xFF888888);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  goldenTest(
    'футер времени: чужое / своё (sending, sent, read, error) / оверлей медиа',
    fileName: 'message_time',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        GoldenTestScenario(
          name: 'чужое — только время',
          child: _scenario(
            const MessageTime(time: '21:04', color: _mutedColor),
          ),
        ),
        GoldenTestScenario(
          name: 'своё — sending',
          child: _scenario(
            const MessageTime(
              time: '21:04',
              color: _mutedColor,
              showStatus: true,
              isSending: true,
            ),
          ),
        ),
        GoldenTestScenario(
          name: 'своё — sent (✓)',
          child: _scenario(
            const MessageTime(
              time: '21:04',
              color: _mutedColor,
              showStatus: true,
            ),
          ),
        ),
        GoldenTestScenario(
          name: 'своё — read (✓✓)',
          child: _scenario(
            const MessageTime(
              time: '21:04',
              color: _mutedColor,
              showStatus: true,
              isRead: true,
            ),
          ),
        ),
        GoldenTestScenario(
          name: 'своё — error',
          child: _scenario(
            const MessageTime(
              time: '21:04',
              color: _mutedColor,
              showStatus: true,
              isError: true,
            ),
          ),
        ),
        GoldenTestScenario(
          name: 'оверлей медиа — read',
          child: _scenario(
            const MessageTime(
              time: '21:04',
              color: _mutedColor,
              showStatus: true,
              isRead: true,
              overlay: true,
            ),
          ),
        ),
      ],
    ),
  );

  // Структурные ассерты — дополняют пиксельный эталон (без магических чисел
  // вёрстки): статус показывается ТОЛЬКО у своих; глиф соответствует состоянию.
  Future<void> pump(WidgetTester tester, MessageTime child) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );

  testWidgets('чужое сообщение: время без индикатора статуса — ledger:RL-message-time', (
    tester,
  ) async {
    await pump(tester, const MessageTime(time: '21:04', color: _mutedColor));
    expect(find.text('21:04'), findsOneWidget);
    expect(find.byIcon(Icons.done_rounded), findsNothing);
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);
    expect(find.byIcon(Icons.access_time_rounded), findsNothing);
  });

  testWidgets('своё прочитанное: время + ✓✓ (done_all) — ledger:RL-message-time', (
    tester,
  ) async {
    await pump(
      tester,
      const MessageTime(
        time: '21:04',
        color: _mutedColor,
        showStatus: true,
        isRead: true,
      ),
    );
    expect(find.text('21:04'), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
  });

  testWidgets('своё доставленное: время + ✓ (done) — ledger:RL-message-time', (
    tester,
  ) async {
    await pump(
      tester,
      const MessageTime(
        time: '21:04',
        color: _mutedColor,
        showStatus: true,
      ),
    );
    expect(find.byIcon(Icons.done_rounded), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);
  });

  testWidgets('своё в отправке: время + часики — ledger:RL-message-time', (
    tester,
  ) async {
    await pump(
      tester,
      const MessageTime(
        time: '21:04',
        color: _mutedColor,
        showStatus: true,
        isSending: true,
      ),
    );
    expect(find.byIcon(Icons.access_time_rounded), findsOneWidget);
  });
}
