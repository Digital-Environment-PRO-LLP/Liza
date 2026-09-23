import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Спек 2026-07-30 §1.3-1.4: в попапе прав нет инпута числа и нет кнопки
// «установить уровень пользовательских разрешений»; названия ролей — без
// численного уровня.
void main() {
  String source(String path) => File(path).readAsStringSync();

  test('в диалоге прав больше нет инпута и кнопки произвольного уровня', () {
    final code = source('lib/widgets/permission_slider_dialog.dart');
    expect(code.contains('DialogTextField'), isFalse,
        reason: 'инпут произвольного уровня должен быть удалён');
    expect(code.contains('setCustomPermissionLevel'), isFalse,
        reason: 'кнопка произвольного уровня должна быть удалена');
    expect(code.contains('setPermissionsLevelDescription'), isFalse,
        reason: 'описание-подзаголовок должно быть удалено');
  });

  test('названия ролей не содержат плейсхолдера уровня', () {
    final ru = jsonDecode(source('lib/l10n/intl_ru.arb'))
        as Map<String, dynamic>;
    final en = jsonDecode(source('lib/l10n/intl_en.arb'))
        as Map<String, dynamic>;
    for (final key in ['userLevel', 'moderatorLevel', 'adminLevel']) {
      expect(ru[key], isNot(contains('{level}')), reason: 'ru.$key');
      expect(en[key], isNot(contains('{level}')), reason: 'en.$key');
    }
    expect(ru['normalUser'], 'Пользователь');
  });
}
