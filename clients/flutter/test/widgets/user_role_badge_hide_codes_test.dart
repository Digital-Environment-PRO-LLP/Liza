// Страж RL-search-hide-admin-moderator-badge: в поиске людей плашки роли
// `admin`/`moderator` скрыты, остальные роли (ai/developer/manager) показаны.
// Скрытие — через параметр UserRoleBadge.hideRoleCodes (пустой по умолчанию,
// поэтому нетронутые call-site — участники чата/шапка/сообщения — не меняются).
// Фильтр по стабильному role.code, не по серверной подписи.
// Рендерит РЕАЛЬНЫЙ прод-виджет UserRoleBadge через forTest (тот же _render).
// ledger:RL-search-hide-admin-moderator-badge

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/role_view.dart';
import 'package:liza/utils/user_role_service.dart';
import 'package:liza/widgets/user_role_badge.dart';

// Набор, который передают три поисковых call-site (глобальный поиск,
// создание чата, приглашение).
const _searchHide = {
  UserRoleService.adminRole,
  UserRoleService.moderatorRole,
};

// L10n нужен реально: ветка «Бот» (роль ai у не-AI) тянет строку через
// L10n.of(context). forTest с userId==null всегда идёт через ветку «Бот» для
// роли ai (isNonAiBot = code=='ai' && userId==null → true).
Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ru'),
      home: Scaffold(body: child),
    );

// L10n грузится асинхронно — пока делегаты не загрузились, MaterialApp рисует
// заглушку и потомок (UserRoleBadge) не построен. Settle доводит загрузку и
// гасит таймеры локализации.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(_wrap(child));
  await tester.pumpAndSettle();
}

Finder _badge() => find.byType(Container);

void main() {
  group('UserRoleBadge.hideRoleCodes', () {
    // AC-1: admin + {admin,moderator} → плашка скрыта.
    // AC:RL-search-hide-admin-moderator-badge/1
    testWidgets('AC-1: admin в поиске → плашка скрыта', (tester) async {
      const role = RoleView(code: 'admin', label: 'Администратор');
      await _pump(tester, const UserRoleBadge.forTest(role: role, hideRoleCodes: _searchHide));
      expect(_badge(), findsNothing);
      expect(find.text('Администратор'), findsNothing);
    });

    // AC-2: moderator + {admin,moderator} → плашка скрыта.
    // AC:RL-search-hide-admin-moderator-badge/2
    testWidgets('AC-2: moderator в поиске → плашка скрыта', (tester) async {
      const role = RoleView(code: 'moderator', label: 'Модератор');
      await _pump(tester, const UserRoleBadge.forTest(role: role, hideRoleCodes: _searchHide));
      expect(_badge(), findsNothing);
      expect(find.text('Модератор'), findsNothing);
    });

    // AC-3: developer + {admin,moderator} → плашка показана (граница «только два
    // кода»). AC:RL-search-hide-admin-moderator-badge/3
    testWidgets('AC-3: developer в поиске → плашка показана', (tester) async {
      const role = RoleView(code: 'developer', label: 'Разработчик');
      await _pump(tester, const UserRoleBadge.forTest(role: role, hideRoleCodes: _searchHide));
      expect(_badge(), findsOneWidget);
      expect(find.text('Разработчик'), findsOneWidget);
    });

    // AC-4: ai + {admin,moderator} → плашка НЕ скрыта (ai не в наборе). Защита
    // от ошибки места фильтра относительно ветки ai — фильтр не должен задеть
    // ai. Через forTest (userId==null) ветка «Бот» не активна → рендерится
    // role.label «ИИ»; различие ИИ/Бот покрывает RL-bot-ai-badge-real-ai-only.
    // AC:RL-search-hide-admin-moderator-badge/4
    testWidgets('AC-4: ai в поиске → плашка показана (не скрыта)', (tester) async {
      const role = RoleView(code: 'ai', label: 'ИИ', color: Color(0xFF4CAF50));
      await _pump(tester, const UserRoleBadge.forTest(role: role, hideRoleCodes: _searchHide));
      expect(_badge(), findsOneWidget);
      expect(find.text('ИИ'), findsOneWidget);
    });

    // AC-5: admin + {} (дефолт = surface участников чата) → плашка показана
    // (default-preservation нетронутых call-site).
    // AC:RL-search-hide-admin-moderator-badge/5
    testWidgets('AC-5: admin вне поиска (дефолт) → плашка показана', (tester) async {
      const role = RoleView(code: 'admin', label: 'Администратор');
      await _pump(tester, const UserRoleBadge.forTest(role: role));
      expect(_badge(), findsOneWidget);
      expect(find.text('Администратор'), findsOneWidget);
    });

    // AC-6: manager + {admin,moderator} → плашка показана (закрывает квантор
    // «оставить ai/developer/manager» мультикейсно).
    // AC:RL-search-hide-admin-moderator-badge/6
    testWidgets('AC-6: manager в поиске → плашка показана', (tester) async {
      const role = RoleView(code: 'manager', label: 'Менеджер');
      await _pump(tester, const UserRoleBadge.forTest(role: role, hideRoleCodes: _searchHide));
      expect(_badge(), findsOneWidget);
      expect(find.text('Менеджер'), findsOneWidget);
    });
  });
}
