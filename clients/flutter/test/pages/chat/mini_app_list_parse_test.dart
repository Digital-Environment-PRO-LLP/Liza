import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat/events/mini_app_list_content.dart';

// Разбор строк списка mini App (msgtype com.liza.miniapp.list). Чистая функция
// parseItems — контракт с сервером (botfather/miniapp.py:_myapps_list_content):
// порядок сохраняется (сервер отдаёт новые сверху), мусорные записи отсеиваются,
// длинные значения режутся, потолок строк держится.

void main() {
  group('MiniAppListContent.parseItems', () {
    test('порядок строк сохраняется (сервер: новые сверху)', () {
      final items = MiniAppListContent.parseItems([
        {'item_id': 'app2', 'title': 'Витрина', 'action_button_id': 'myapps.show.app2'},
        {'item_id': 'app1', 'title': 'Магазин', 'action_button_id': 'myapps.show.app1'},
      ]);
      expect(items.map((i) => i.itemId).toList(), ['app2', 'app1']);
      expect(items.first.buttonId, 'myapps.show.app2');
      expect(items.first.title, 'Витрина');
    });

    test('запись без action_button_id/title отбрасывается', () {
      final items = MiniAppListContent.parseItems([
        {'title': 'Без кнопки'},
        {'action_button_id': 'b', 'title': ''},
        {'item_id': 'ok', 'title': 'Ок', 'action_button_id': 'myapps.show.ok'},
      ]);
      expect(items.length, 1);
      expect(items.single.itemId, 'ok');
    });

    test('item_id по умолчанию = action_button_id; subtitle пустой если нет', () {
      final items = MiniAppListContent.parseItems([
        {'title': 'App', 'action_button_id': 'myapps.show.x'},
      ]);
      expect(items.single.itemId, 'myapps.show.x');
      expect(items.single.subtitle, '');
      expect(items.single.icon, isNull);
    });

    test('длинные title/subtitle режутся', () {
      final longTitle = 'т' * 200;
      final longSub = 'о' * 200;
      final items = MiniAppListContent.parseItems([
        {'title': longTitle, 'subtitle': longSub, 'action_button_id': 'b'},
      ]);
      expect(items.single.title.length, 96);
      expect(items.single.subtitle.length, 120);
    });

    test('icon парсится в Uri', () {
      final items = MiniAppListContent.parseItems([
        {'title': 'App', 'action_button_id': 'b', 'icon': 'mxc://s/abc'},
      ]);
      expect(items.single.icon.toString(), 'mxc://s/abc');
    });

    test('потолок maxItems соблюдается', () {
      final raw = [
        for (var i = 0; i < MiniAppListContent.maxItems + 10; i++)
          {'title': 'App $i', 'action_button_id': 'myapps.show.$i'},
      ];
      final items = MiniAppListContent.parseItems(raw);
      expect(items.length, MiniAppListContent.maxItems);
    });

    test('null → пустой список', () {
      expect(MiniAppListContent.parseItems(null), isEmpty);
    });
  });
}
