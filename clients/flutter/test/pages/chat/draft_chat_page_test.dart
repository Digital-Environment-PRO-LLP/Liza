// ledger:RL-direct-chat-draft-on-first-send
// AC:RL-direct-chat-draft-on-first-send/1
// guard.render:real-widget
//
// Real-widget страж чернового экрана DraftChatPage: показывает подсказку «чат
// появится после первого сообщения» и держит кнопку отправки ВЫКЛЮЧЕННОЙ пока
// поле пусто (первое сообщение — осознанное действие, а не побочка открытия).
// Рендерится РЕАЛЬНЫЙ DraftChatPage (не реплика). Materialize/навигация требуют
// MatrixState и покрыты юнитами в test/utils/direct_chat_draft_test.dart.
//
// Red-proof: если кнопка отправки была бы активна на пустом поле (тап → создание
// комнаты «ни с чем») — expect(onPressed, isNull) упадёт.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/draft_chat_page.dart';

// Avatar (даже без mxContent) заводит MxcImage._tryLoad с exp-backoff
// (2/4/8/16/30с). Автофокус-TextField даёт периодический cursor-таймер →
// pumpAndSettle не сходится. Сливаем backoff-таймеры вручную, как в
// test/pages/contacts/contacts_screen_test.dart.
Future<void> _drainAvatarRetryTimers(WidgetTester tester) async {
  for (final delay in const [
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 9),
    Duration(seconds: 17),
    Duration(seconds: 31),
  ]) {
    await tester.pump(delay);
  }
}

void main() {
  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: child,
      );

  IconButton sendButton(WidgetTester tester) => tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.send_outlined),
      );

  testWidgets(
    'AC-1(UI): подсказка видна, кнопка отправки выключена пока поле пусто, '
    'включается при вводе',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          DraftChatPage(
            '@bob:server',
            initialProfile: Profile(
              userId: '@bob:server',
              displayName: 'Боб',
            ),
          ),
        ),
      );
      // Deferred-локализация ru грузится через future — даём кадры.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Подсказка (русская строка — ловит и дыру intl_ru).
      expect(
        find.text('Чат появится после отправки первого сообщения.'),
        findsOneWidget,
      );
      // Имя собеседника в шапке.
      expect(find.text('Боб'), findsOneWidget);

      // Пусто → отправка выключена.
      expect(sendButton(tester).onPressed, isNull);

      // Ввод текста → отправка включается.
      await tester.enterText(find.byType(TextField), 'привет');
      await tester.pump();
      expect(sendButton(tester).onPressed, isNotNull);

      // Стёрли (пробелы) → снова выключена.
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(sendButton(tester).onPressed, isNull);

      await _drainAvatarRetryTimers(tester);
    },
  );
}
