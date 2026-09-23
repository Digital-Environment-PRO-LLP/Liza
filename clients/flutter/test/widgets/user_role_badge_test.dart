import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/role_view.dart';
import 'package:liza/widgets/user_role_badge.dart';

void main() {
  group('UserRoleBadge.forTest', () {
    testWidgets('renders nothing when role is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: UserRoleBadge.forTest(role: null)),
      );
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('renders nothing for default user role', (tester) async {
      // Роль "user" есть у всех зарегистрированных аккаунтов как
      // поведенческий маркер (currentUserRole для гейтинга UI), но
      // тегом не показывается - иначе у каждого юзера в чат-листе
      // висел бы зелёный лейбл "Пользователь".
      const role = RoleView(code: 'user', label: 'Пользователь');
      await tester.pumpWidget(
        const MaterialApp(home: UserRoleBadge.forTest(role: role)),
      );
      expect(find.byType(Container), findsNothing);
      expect(find.text('Пользователь'), findsNothing);
    });

    testWidgets('renders label with default green when color is null',
        (tester) async {
      const role = RoleView(code: 'agronom', label: 'Агроном');
      await tester.pumpWidget(
        const MaterialApp(home: UserRoleBadge.forTest(role: role)),
      );
      expect(find.text('Агроном'), findsOneWidget);
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF4CAF50));
    });

    testWidgets('renders with custom color from catalog', (tester) async {
      const role = RoleView(
        code: 'cyber_agronom',
        label: 'Кибер-Агроном',
        color: Color(0xFF7CB342),
      );
      await tester.pumpWidget(
        const MaterialApp(home: UserRoleBadge.forTest(role: role)),
      );
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF7CB342));
      expect(find.text('Кибер-Агроном'), findsOneWidget);
    });

    testWidgets('renders any catalog code, not just hardcoded ones',
        (tester) async {
      // Регрессионный тест: до Task 14 виджет имел Map<String,String>
      // _labels всего на 5 ролей. Любой новый код из каталога (например,
      // только что добавленный 'cyber_agronom') не отрисовывался. Теперь
      // отрисовывается всё, что приходит с сервера в RoleView.
      const role = RoleView(
        code: 'completely_new_role',
        label: 'Совсем Новая Роль',
        color: Color(0xFF000000),
      );
      await tester.pumpWidget(
        const MaterialApp(home: UserRoleBadge.forTest(role: role)),
      );
      expect(find.text('Совсем Новая Роль'), findsOneWidget);
    });

    testWidgets('white text on dark background', (tester) async {
      const role = RoleView(
        code: 'x',
        label: 'X',
        color: Color(0xFF000000),
      );
      await tester.pumpWidget(
        const MaterialApp(home: UserRoleBadge.forTest(role: role)),
      );
      final text = tester.widget<Text>(find.text('X'));
      expect(text.style?.color, Colors.white);
    });

    testWidgets('black text on light background', (tester) async {
      const role = RoleView(
        code: 'x',
        label: 'X',
        color: Color(0xFFFFFFFF),
      );
      await tester.pumpWidget(
        const MaterialApp(home: UserRoleBadge.forTest(role: role)),
      );
      final text = tester.widget<Text>(find.text('X'));
      expect(text.style?.color, Colors.black);
    });
  });
}
