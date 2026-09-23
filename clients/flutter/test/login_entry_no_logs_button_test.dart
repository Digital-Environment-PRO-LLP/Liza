@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Кнопка «Отправить логи» (иконка жука) убрана с ЭКРАНА ВХОДА.
///
/// Проверка идёт по исходнику, а не по отрисованному экрану: живой
/// `HomeserverPickerController` тянет Matrix-клиент, version-gate и сеть —
/// в widget-тесте он не поднимается. Инвариант при этом ровно текстовый:
/// в `actions` AppBar первого экрана не должно быть кнопки логов.
void main() {
  final view = File(
    'lib/pages/homeserver_picker/homeserver_picker_view.dart',
  ).readAsStringSync();

  group('экран входа', () {
    test('кнопки логов в AppBar больше нет', () {
      expect(
        view,
        isNot(contains('Icons.bug_report_outlined')),
        reason: 'иконка жука убрана с экрана входа',
      );
      expect(view, isNot(contains('sendLogs')));
      expect(view, isNot(contains('shareLogs')));
    });

    test('неиспользуемый импорт FileLogger вычищен', () {
      expect(view, isNot(contains('file_logger.dart')));
    });

    test('AppBar на месте — стрелка «назад» и Hero-логотип не пострадали', () {
      // Кнопку убрали, а не весь AppBar: без него ломается переход-Hero и
      // системный отступ сверху.
      expect(view, contains('appBar: AppBar('));
      expect(view, contains("tag: 'info-logo'"));
    });
  });

  group('логи остаются достижимы из настроек', () {
    test('пункт «Логи приложения» в настройках не тронут', () {
      // Второе место входа в логи — единственное оставшееся, поэтому оно
      // обязано пережить удаление кнопки с экрана входа.
      final settings = File(
        'lib/pages/settings/settings_view.dart',
      ).readAsStringSync();
      expect(settings, contains('Icons.bug_report_outlined'));
      expect(settings, contains('logsMenuAction'));
    });
  });
}
