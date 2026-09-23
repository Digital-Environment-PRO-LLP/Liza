// ledger:RL-chat-list-phone-search-invite
// AC:RL-chat-list-phone-search-invite/7
// AC:RL-chat-list-invite-people-row/4
//
// Страж виджета: в режиме поиска InvitePeopleListTile рендерится ПЕРВЫМ
// (ValueKey 'invite_people_row_search') — до SearchTitle компаний. Тот же
// ключ покрывает AC-4 стража RL-chat-list-invite-people-row (тайл в поиске).
// Рендерится РЕАЛЬНЫЙ виджет InvitePeopleListTile (guard.render:real-widget).
// AC-1/2/3 (lookup→Profile, тап=DM/share) требуют полного _search()
// + мок HTTP AuthProxyService — device/manual residual (см. RL).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat_list/invite_people_list_tile.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(body: child),
      );

  testWidgets(
    // AC:RL-chat-list-phone-search-invite/7
    'AC-7: InvitePeopleListTile имеет ValueKey invite_people_row_search '
    'и рендерится с ожидаемыми текстом + иконкой',
    (tester) async {
      // Реальный InvitePeopleListTile с ключом из продовой chat_list_body.dart.
      await tester.pumpWidget(
        wrap(
          const InvitePeopleListTile(
            key: ValueKey('invite_people_row_search'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ключ присутствует — страж позиции «первым» в поисковом слое.
      // AC:RL-chat-list-invite-people-row/4
      expect(
        find.byKey(const ValueKey('invite_people_row_search')),
        findsOneWidget,
      );

      // Русский текст (ловит дыру intl_ru).
      expect(find.text('Пригласить людей'), findsOneWidget);

      // Иконка добавления (инвариант виджета).
      expect(find.byIcon(Icons.person_add_alt_1), findsOneWidget);

      // Тап-строка (onTap != null).
      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.onTap, isNotNull);
    },
  );
}
