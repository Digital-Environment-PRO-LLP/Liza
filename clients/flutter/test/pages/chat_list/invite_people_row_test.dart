// ledger:RL-chat-list-invite-people-row
// AC:RL-chat-list-invite-people-row/2
// AC:RL-chat-list-invite-people-row/3
// AC:RL-chat-list-invite-people-row/6
// AC:RL-chat-list-invite-people-row/7
// AC:RL-chat-list-invite-people-row/8
// AC:RL-chat-list-invite-people-row/9
//
// Страж строки «Пригласить людей». Здесь — рендер РЕАЛЬНОГО виджета
// InvitePeopleListTile (guard.render:real-widget): текст по-русски (AC-3, ловит
// дыру intl_ru) + это тап-ListTile с person-add иконкой + геометрия выравнивания
// по ChatListItem (AC-6.x).
// AC-1 (позиция ПОД «Лиза ИИ», только allChats) и AC-2 (тап → нативный share)
// требуют полного ChatListBody + Client (prepareTestClient) и нативного share —
// device-flow/manual residual, см. RL-chat-list-invite-people-row.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat_list/invite_people_list_tile.dart';
import 'package:liza/widgets/avatar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(body: child),
      );

  testWidgets('AC-3: строка «Пригласить людей» рендерится с русским текстом',
      (tester) async {
    await tester.pumpWidget(wrap(const InvitePeopleListTile()));
    await tester.pumpAndSettle();

    expect(find.text('Пригласить людей'), findsOneWidget);
    expect(find.byIcon(Icons.person_add_alt_1), findsOneWidget);

    // Тап-строка (ListTile с onTap != null).
    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.onTap, isNotNull);
  });

  // AC-6.x — геометрия строки выровнена по ChatListItem («на одном уровне с
  // прочими»). Требование пользователя дословно:
  //   «"пригласить людей" должно быть на одном уровне с прочими»
  // Ассерты на РЕАЛЬНОМ InvitePeopleListTile. Величины — тот же инвариант, что и
  // у ChatListItem (chat_list_item.dart:131-141): аватар Avatar.defaultSize=44,
  // contentPadding-старт 16, visualDensity(-0.5); отсюда titleStart = 16+44+16.
  testWidgets(
    // AC:RL-chat-list-invite-people-row/7
    // AC:RL-chat-list-invite-people-row/8
    // AC:RL-chat-list-invite-people-row/9
    'AC-7/8/9: аватар 44×44, visualDensity(-0.5), левый край leading 16px',
    (tester) async {
      await tester.pumpWidget(wrap(const InvitePeopleListTile()));
      await tester.pumpAndSettle();

      final tile = tester.widget<ListTile>(find.byType(ListTile));

      // AC-8: density-паритет высоты строки с ChatListItem.
      expect(tile.visualDensity, const VisualDensity(vertical: -0.5));
      // AC-9: левый край content == 16px (совпадает с обёрнутым чатом 8+8).
      expect(
        tile.contentPadding,
        const EdgeInsets.symmetric(horizontal: 16),
      );

      // AC-7: leading-зона строго Avatar.defaultSize (44), не 48.
      final leadingBox = tester.getSize(find.byType(CircleAvatar));
      expect(leadingBox.width, Avatar.defaultSize);
      expect(leadingBox.height, Avatar.defaultSize);
      final circle = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(circle.radius, Avatar.defaultSize / 2);

      // AC-9 (рендер): левый край аватара == 16 от края строки.
      final tileLeft = tester.getTopLeft(find.byType(ListTile)).dx;
      final avatarLeft = tester.getTopLeft(find.byType(CircleAvatar)).dx;
      expect(avatarLeft - tileLeft, moreOrLessEquals(16, epsilon: 0.5));
    },
  );

  testWidgets(
    // AC:RL-chat-list-invite-people-row/6
    'AC-6: titleStart текста == инвариант ChatListItem (16 + 44 + gap16 = 76)',
    (tester) async {
      await tester.pumpWidget(wrap(const InvitePeopleListTile()));
      await tester.pumpAndSettle();

      final tileLeft = tester.getTopLeft(find.byType(ListTile)).dx;
      final titleLeft =
          tester.getTopLeft(find.text('Пригласить людей')).dx;
      // contentPadding.start(16) + leadingWidth(44) + M3 horizontalTitleGap(16).
      expect(titleLeft - tileLeft, moreOrLessEquals(76, epsilon: 0.5));
    },
  );

  testWidgets(
    // AC:RL-chat-list-invite-people-row/2
    'AC-2: текст приглашения в ru — «Я пользуюсь Liza», не «Лиза» '
    '(бренд-латиница; ловит тихий откат inviteMessageText)',
    (tester) async {
      late final String ru;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) {
              ru = L10n.of(context).inviteMessageText('https://me.liza.ru/i/xyz');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Бренд на латинице: «Liza», НЕ кириллическое «Лиза».
      expect(ru, contains('Liza'));
      expect(ru, isNot(contains('Лиза')));
      // Плейсхолдер-ссылка на месте (строка не потеряла {link}).
      expect(ru, contains('https://me.liza.ru/i/xyz'));
    },
  );
}
