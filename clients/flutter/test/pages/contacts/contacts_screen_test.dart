// ledger:RL-contacts-screen-match-invite
// AC:RL-contacts-screen-match-invite/1 AC:RL-contacts-screen-match-invite/2
// AC:RL-contacts-screen-match-invite/3 AC:RL-contacts-screen-match-invite/4
//
// Страж экрана «Контакты»: matched-контакт → «Написать» (тайл зовёт onWrite),
// unmatched → «Пригласить» (нативный share). Рендерятся РЕАЛЬНЫЕ виджеты
// ContactListTile / ContactsPermissionView (не реплики) — guard.render:real-widget.
// С 2026-09-03 «Написать» ведёт не в немедленный startDirectChat, а через
// openDirectChatOrDraft (черновик, если DM ещё нет) — см.
// RL-direct-chat-draft-on-first-send. Тайл по-прежнему зовёт onWrite → AC-1 цел.
// AC-5 (graceful federation-fail) — device/manual residual, теперь всплывает при
// первой отправке из черновика, не при тапе «Написать».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/contacts/contacts_page.dart';

// Avatar без MatrixState/uri запускает MxcImage._tryLoad с exp-backoff
// (2/4/8/16/30с) → без прокачки тест падает на «A Timer is still pending».
// Паттерн из test/golden/deleted_bot_avatar_golden_test.dart.
Future<void> _drainMxcImageRetryTimers(WidgetTester tester) async {
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
        home: Scaffold(body: child),
      );

  testWidgets(
    'AC-1: matched-контакт (есть mxid) → кнопка «Написать», тап зовёт onWrite',
    (tester) async {
      String? written;
      var invited = false;
      await tester.pumpWidget(wrap(
        ContactListTile(
          displayName: 'Бабушка',
          subtitle: '+79141799386',
          mxid: '@granny:synapse.liza.laba.prodamus.tech',
          onWrite: (mxid) => written = mxid,
          onInvite: () => invited = true,
        ),
      ));
      await tester.pumpAndSettle();

      // AC-3: ассерт по русскому тексту (ловит дыру intl_ru).
      expect(find.text('Написать'), findsOneWidget);
      expect(find.text('Пригласить'), findsNothing);

      await tester.tap(find.text('Написать'));
      await tester.pumpAndSettle();
      expect(written, '@granny:synapse.liza.laba.prodamus.tech');
      expect(invited, isFalse);
      await _drainMxcImageRetryTimers(tester);
    },
  );

  testWidgets(
    'AC-2: unmatched-контакт (mxid == null) → «Пригласить», тап зовёт onInvite, '
    'НЕ onWrite',
    (tester) async {
      String? written;
      var invited = false;
      await tester.pumpWidget(wrap(
        ContactListTile(
          displayName: 'Дедушка',
          subtitle: '89141729877',
          mxid: null,
          onWrite: (mxid) => written = mxid,
          onInvite: () => invited = true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Пригласить'), findsOneWidget);
      expect(find.text('Написать'), findsNothing);

      await tester.tap(find.text('Пригласить'));
      await tester.pumpAndSettle();
      expect(invited, isTrue);
      expect(written, isNull);
      await _drainMxcImageRetryTimers(tester);
    },
  );

  testWidgets(
    'AC-4: доступ запрещён → объяснение + «Открыть настройки», не краш/белый экран',
    (tester) async {
      var opened = false;
      await tester.pumpWidget(wrap(
        ContactsPermissionView(onOpenSettings: () => opened = true),
      ));
      await tester.pumpAndSettle();

      // Объяснение (не пустой экран) + кнопка настроек по русскому тексту.
      expect(
        find.textContaining('Доступ к контактам'),
        findsOneWidget,
      );
      expect(find.text('Открыть настройки'), findsOneWidget);

      await tester.tap(find.text('Открыть настройки'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
    },
  );
}
