import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:liza/utils/user_role_service.dart';

import 'test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late UserRoleService service;

  setUp(() async {
    client = await prepareTestClient();
    service = UserRoleService(() => client);
  });

  tearDown(() async {
    service.dispose();
    await client.dispose(closeDatabase: true);
  });

  group('applyOwnAccountData', () {
    test('uses role_v2 when present', () {
      service.applyOwnAccountData('@a:srv', {
        'role': 'cyber_agronom',
        'role_v2': {
          'code': 'cyber_agronom',
          'label': 'Кибер-Агроном',
          'color': '#7CB342',
        },
      });
      final r = service.getRole('@a:srv');
      expect(r, isNotNull);
      expect(r!.code, 'cyber_agronom');
      expect(r.label, 'Кибер-Агроном');
      expect(r.color, isNotNull);
    });

    test('falls back to _legacyLabels when only role string present', () {
      service.applyOwnAccountData('@a:srv', {'role': 'ai'});
      final r = service.getRole('@a:srv');
      expect(r, isNotNull);
      expect(r!.code, 'ai');
      expect(r.label, 'ИИ');
    });

    test('returns null when role is unknown and no role_v2', () {
      service.applyOwnAccountData('@a:srv', {'role': 'cyber_agronom'});
      // Старый клиент не знает 'cyber_agronom', _legacyLabels не содержит этот код
      expect(service.getRole('@a:srv'), isNull);
    });

    test('isAiUser still works with new model', () {
      service.applyOwnAccountData('@a:srv', {
        'role': 'ai',
        'role_v2': {'code': 'ai', 'label': 'ИИ', 'color': '#4CAF50'},
      });
      expect(service.isAiUser('@a:srv'), isTrue);
      expect(service.isAiUser('@nobody:srv'), isFalse);
    });

    test('isCurrentUserDeveloper still works', () {
      // No userID set yet (client not logged in) -> currentUserRole returns null
      expect(service.isCurrentUserDeveloper, isFalse);
      expect(service.isCurrentUserDeveloper, isFalse);
    });

    // ledger:RL-developer-gates-strict
    test('developer-пункты интерфейса — строго роль developer '
        '[AC:RL-developer-gates-strict/2]', () async {
      // Залогиниться, чтобы client.userID был не null
      final loggedIn = await prepareTestClient(loggedIn: true);
      final roleService = UserRoleService(() => loggedIn);
      try {
        final uid = loggedIn.userID!;
        roleService.applyOwnAccountData(uid, {'role': 'developer'});
        expect(
          roleService.isCurrentUserDeveloper,
          isTrue,
          reason: 'разработчик обязан видеть «Добавить аккаунт» и «Приложения»',
        );

        // «Добавить аккаунт» с 2026-05-15 — только разработчикам (a7608de1).
        // 21–22.09 гейт открывали и администратору — откатили по решению
        // владельца: admin старше по правам, но developer-пунктов не видит.
        for (final code in const [
          'admin',
          'moderator',
          'manager',
          'user',
          'ai',
        ]) {
          roleService.applyOwnAccountData(uid, {'role': code});
          expect(
            roleService.isCurrentUserDeveloper,
            isFalse,
            reason: 'роль $code не должна видеть developer-пункты',
          );
        }

        roleService.applyOwnAccountData(uid, {'role': 'admin'});
        expect(roleService.isCurrentUserAdmin, isTrue);
      } finally {
        roleService.dispose();
        await loggedIn.dispose(closeDatabase: true);
      }
    });

    // Персональная доп. роль (extra_roles) открывает developer-пункты ТОЛЬКО
    // её носителю: владелец — admin + developer; прочие admin — без изменений.
    test('extra_roles: admin + developer видит developer-пункты, '
        'обычный admin — нет [AC:RL-developer-gates-strict/7]', () async {
      final loggedIn = await prepareTestClient(loggedIn: true);
      final roleService = UserRoleService(() => loggedIn);
      try {
        final uid = loggedIn.userID!;
        roleService.applyOwnAccountData(uid, {
          'role': 'admin',
          'extra_roles': ['developer'],
          'role_v2': {
            'code': 'admin',
            'label': 'Администратор',
            'color': null,
            'extra_roles': ['developer'],
          },
        });
        expect(roleService.isCurrentUserDeveloper, isTrue);
        expect(roleService.isCurrentUserAdmin, isTrue);
        expect(roleService.currentUserRole!.label, 'Администратор');

        // legacy-запись без role_v2 — доп. роль берётся из верхнего поля
        roleService.applyOwnAccountData(uid, {
          'role': 'admin',
          'extra_roles': ['developer'],
        });
        expect(roleService.isCurrentUserDeveloper, isTrue);

        // тот же admin без extra_roles — прежнее строгое поведение
        roleService.applyOwnAccountData(uid, {
          'role': 'admin',
          'role_v2': {'code': 'admin', 'label': 'Администратор'},
        });
        expect(roleService.isCurrentUserDeveloper, isFalse);
        expect(roleService.isCurrentUserAdmin, isTrue);

        // to-device от сервера несёт extra_roles во view
        roleService.applyToDeviceEvent(uid, {
          'code': 'admin',
          'label': 'Администратор',
          'extra_roles': ['developer'],
        });
        expect(roleService.isCurrentUserDeveloper, isTrue);
        roleService.applyToDeviceEvent(uid, {
          'code': 'admin',
          'label': 'Администратор',
        });
        expect(roleService.isCurrentUserDeveloper, isFalse);
      } finally {
        roleService.dispose();
        await loggedIn.dispose(closeDatabase: true);
      }
    });

    test('вход новым аккаунтом: developer основной или доп. ролью ведёт на '
        '/backup, admin без доп. роли — нет [AC:RL-developer-gates-strict/12]',
        () {
      const uid = '@new:srv';
      final cases = <Map<String, dynamic>, bool>{
        {'role': 'developer'}: true,
        {'role': 'admin', 'extra_roles': ['developer']}: true,
        {
          'role': 'admin',
          'extra_roles': ['developer'],
          'role_v2': {'code': 'admin', 'label': 'Администратор'},
        }: true,
        {'role': 'admin'}: false,
        {'role': 'user'}: false,
      };
      cases.forEach((content, expected) {
        service.applyOwnAccountData(uid, content);
        expect(service.isDeveloper(uid), expected, reason: '$content');
      });
      expect(service.isDeveloper('@unknown:srv'), isFalse);
    });

    test('developer без доп. ролей не получает admin-пункты '
        '[AC:RL-developer-gates-strict/16]', () async {
      final loggedIn = await prepareTestClient(loggedIn: true);
      final roleService = UserRoleService(() => loggedIn);
      try {
        final uid = loggedIn.userID!;
        roleService.applyOwnAccountData(uid, {
          'role': 'developer',
          'role_v2': {'code': 'developer', 'label': 'Разработчик'},
        });
        expect(roleService.isCurrentUserDeveloper, isTrue);
        expect(roleService.isCurrentUserAdmin, isFalse);
      } finally {
        roleService.dispose();
        await loggedIn.dispose(closeDatabase: true);
      }
    });

    test('роль в lib/ сверяется только через hasRole — прямое сравнение кода '
        'не видит extra_roles [AC:RL-developer-gates-strict/11]', () {
      final direct = RegExp(
        r'\.code\s*==\s*UserRoleService\.(developerRole|adminRole)',
      );
      final hits = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('user_role_service.dart'))
          .where((f) => direct.hasMatch(f.readAsStringSync()))
          .map((f) => f.path)
          .toList();
      expect(hits, isEmpty);
    });

    // AC:RL-developer-gates-strict/5
    test('в клиенте нет расширенного предиката developer-доступа', () {
      final hits = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('hasDeveloperAccess'))
          .map((f) => f.path)
          .toList();
      expect(
        hits,
        isEmpty,
        reason:
            'developer-гейты — только isCurrentUserDeveloper; '
            'предикат «developer или admin» откатан 2026-09-22',
      );
    });

    test('legacy label maps work for all 6 default roles', () {
      const codes = {
        'user': 'Пользователь',
        'ai': 'ИИ',
        'developer': 'Разработчик',
        'moderator': 'Модератор',
        'manager': 'Менеджер',
        'admin': 'Администратор',
      };
      for (final entry in codes.entries) {
        service.applyOwnAccountData('@a:srv', {'role': entry.key});
        final r = service.getRole('@a:srv');
        expect(r, isNotNull, reason: entry.key);
        expect(r!.label, entry.value, reason: entry.key);
        expect(r.code, entry.key, reason: entry.key);
      }
    });
  });

  group('applyToDeviceEvent', () {
    test('sets role from to-device payload', () {
      service.applyToDeviceEvent('@a:srv', {
        'code': 'cyber_agronom',
        'label': 'Кибер-Агроном',
        'color': '#7CB342',
      });
      final r = service.getRole('@a:srv');
      expect(r, isNotNull);
      expect(r!.code, 'cyber_agronom');
    });

    test('null payload clears role', () {
      // first set
      service.applyToDeviceEvent('@a:srv', {
        'code': 'ai',
        'label': 'ИИ',
        'color': '#4CAF50',
      });
      expect(service.getRole('@a:srv'), isNotNull);
      // then clear
      service.applyToDeviceEvent('@a:srv', null);
      expect(service.getRole('@a:srv'), isNull);
    });

    test('updates rolesVersion notifier', () {
      var notifies = 0;
      service.rolesVersion.addListener(() => notifies++);
      service.applyToDeviceEvent('@a:srv', {
        'code': 'ai',
        'label': 'ИИ',
        'color': null,
      });
      expect(notifies, 1);
    });
  });

  group('isCurrentUserAdmin', () {
    test('true когда роль admin', () async {
      // Залогиниться, чтобы client.userID был не null
      final loggedInClient = await prepareTestClient(loggedIn: true);
      final adminService = UserRoleService(() => loggedInClient);
      try {
        adminService.applyOwnAccountData(loggedInClient.userID!, {
          'role': 'admin',
        });
        expect(adminService.isCurrentUserAdmin, isTrue);
      } finally {
        adminService.dispose();
        await loggedInClient.dispose(closeDatabase: true);
      }
    });

    test('false для обычного пользователя', () async {
      final loggedInClient = await prepareTestClient(loggedIn: true);
      final userService = UserRoleService(() => loggedInClient);
      try {
        userService.applyOwnAccountData(loggedInClient.userID!, {
          'role': 'user',
        });
        expect(userService.isCurrentUserAdmin, isFalse);
      } finally {
        userService.dispose();
        await loggedInClient.dispose(closeDatabase: true);
      }
    });

    test('false когда роль неизвестна', () {
      expect(service.isCurrentUserAdmin, isFalse);
    });
  });

  // ledger:RL-liza-news-choice-buttons-by-role
  //
  // Инвариант фикса «кнопки Liza News на Windows/Android»
  // (docs/superpowers/specs/2026-09-02-liza-news-buttons-server-role-ai-design.md):
  // гейт кнопок карточки com.liza.miniapp.choice держится на СЕРВЕРНОЙ роли ai,
  // а НЕ только на клиентском _fallbackAiMxids. Matrix.isAiUser делегирует сюда:
  // `userRoleService.isAiUser(id) || _fallbackAiMxids.contains(id)`. Значит бот с
  // ролью `ai` в кэше (пришедшей по федерации из account_data), даже если его mxid
  // НЕ в fallback-списке, распознаётся как ai → карточка рисует кнопки. Это ровно
  // тот путь, по которому фикс долетает до непересобранного клиента (Windows 3720).
  group('isAiUser держится на серверной роли, не только на fallback', () {
    // Заведомо НЕ входит в _fallbackAiMxids (не bots.liza.ru/liza.local и т.п.).
    const foreignBot = '@liza-news:some-company.example';

    test(
      'AC-1 [AC:RL-liza-news-choice-buttons-by-role/1]: роль ai в кэше → isAiUser true (без участия fallback)',
      () {
        service.applyOwnAccountData(foreignBot, {
          'role': 'ai',
          'role_v2': {'code': 'ai', 'label': 'ИИ', 'color': '#4CAF50'},
        });
        expect(service.isAiUser(foreignBot), isTrue);
      },
    );

    test(
      'AC-1b: bare-роль ai (без role_v2, own-token write) → isAiUser true',
      () {
        service.applyOwnAccountData(foreignBot, {'role': 'ai'});
        expect(service.isAiUser(foreignBot), isTrue);
      },
    );

    test(
      'AC-2 [AC:RL-liza-news-choice-buttons-by-role/2]: роль user в кэше и вне fallback → isAiUser false (red-proof)',
      () {
        service.applyOwnAccountData(foreignBot, {'role': 'user'});
        expect(service.isAiUser(foreignBot), isFalse);
      },
    );
  });
}
