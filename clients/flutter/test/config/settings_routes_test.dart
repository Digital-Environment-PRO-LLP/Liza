// Адреса пунктов настроек обязаны существовать в дереве маршрутов.
//
// Выстрадано: маршруты `email` и `handle` были вложены внутрь ветки
// `security`, то есть реально отвечали на /rooms/settings/security/email.
// Меню при этом вело на /rooms/settings/email — go_router такого адреса не
// находил и молча уводил в список чатов. Внешне это выглядело как «экран не
// открывается», а ни один тест не краснел: и меню, и маршруты по
// отдельности были корректны, расходились только их адреса.
import 'package:flutter_test/flutter_test.dart';
import 'package:liza/config/app_config.dart';
import 'package:go_router/go_router.dart';

import 'package:liza/config/routes.dart';

/// Собирает полные пути всех маршрутов дерева.
Set<String> _collectPaths(List<RouteBase> routes, [String prefix = '']) {
  final paths = <String>{};
  for (final route in routes) {
    if (route is GoRoute) {
      final path = route.path.startsWith('/')
          ? route.path
          : '$prefix/${route.path}';
      paths.add(path.replaceAll('//', '/'));
      paths.addAll(_collectPaths(route.routes, path));
    } else {
      paths.addAll(_collectPaths(route.routes, prefix));
    }
  }
  return paths;
}

void main() {
  late Set<String> paths;

  setUpAll(() => paths = _collectPaths(AppRoutes.routes));

  group('адреса пунктов настроек существуют в дереве маршрутов', () {
    // Ровно те строки, которые стоят в context.go(...) пунктов меню
    // settings_view.dart. Расхождение = пункт уводит в список чатов.
    const menuTargets = [
      '/rooms/settings/email',
      '/rooms/settings/handle',
      '/rooms/settings/style',
      '/rooms/settings/notifications',
      '/rooms/settings/devices',
      '/rooms/settings/security',
      // Витрина MCP-подключений (бывш. «Интеграции»). Все ТРИ точки входа
      // (меню «+», раздел настроек, «⋮» в чате с Лизой) ходят сюда одной
      // константой AppRoutes.settingsMcp — её и сверяем.
      AppRoutes.settingsMcp,
    ];

    for (final target in menuTargets) {
      test(target, () {
        expect(
          paths,
          contains(target),
          reason:
              'пункт меню ведёт на $target, но такого маршрута нет — '
              'go_router уведёт в список чатов',
        );
      });
    }
  });

  // ledger:RL-keycloak-id-prod
  // AC:RL-keycloak-id-prod/4
  test('prod/dev имеют маршрут phone/email OTP с публичным адресом', () {
    expect(paths.contains('/auth/phone'), AppConfig.phoneAuthEnabled);
    expect(paths.where((path) => path.contains('demo')), isEmpty);
  });

  test('email и handle НЕ вложены в security', () {
    expect(paths, isNot(contains('/rooms/settings/security/email')));
    expect(paths, isNot(contains('/rooms/settings/security/handle')));
  });
}
