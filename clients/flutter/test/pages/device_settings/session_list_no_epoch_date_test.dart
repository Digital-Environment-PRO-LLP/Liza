// Экран «Сеансы» не имеет права печатать «1 янв. 1970 г.» (LABA-2546).
//
// `last_seen_ts` в спеке Matrix необязателен, а Synapse заполняет его лишь
// отложенным батчем `client_ips` — на проде так приходит каждый шестой сеанс
// (55 из 316 видимых устройств). Прежний код подставлял epoch (`?? 0`) и
// честно форматировал его как дату, из-за чего у пользователя в списке висел
// «Unknown device / Посещение: 1 янв. 1970 г.».
//
// Тест гоняет РЕАЛЬНЫЙ UserDeviceListItem (а не реплику подписи): чистая
// функция не доказала бы, что строка дошла до экрана и что тот же фикс закрыл
// заголовок попапа, где раньше рендерился литерал `null`.
//
// ledger:RL-session-list-no-epoch-date

// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/device_settings/user_device_list_item.dart';
import 'package:liza/utils/matrix_sdk_extensions/device_extension.dart';
import 'package:liza/widgets/matrix.dart';

import '../../utils/test_client.dart';

void main() {
  late Client client;
  late SharedPreferences store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    client = await prepareTestClient(loggedIn: true);
    // Фоновый sync-цикл держит таймер живым и роняет тест на
    // «A Timer is still pending even after the widget tree was disposed».
    client.backgroundSync = false;
    store = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  Future<void> pump(
    WidgetTester tester,
    Device device, {
    String locale = 'ru',
  }) async {
    // l10n.yaml несёт use-deferred-loading: вторая локаль в файле не успевает
    // загрузиться под fakeAsync и даёт ПУСТОЕ дерево. Предзагружаем в реальном
    // времени — см. reference_flutter_l10n_deferred_fakeasync_hang.
    await tester.runAsync(() => L10n.delegate.load(Locale(locale)));
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10n.supportedLocales,
        home: Matrix(
          clients: [client],
          store: store,
          child: Scaffold(
            body: UserDeviceListItem(
              device,
              remove: (_) {},
              rename: (_) {},
              verify: (_) {},
              block: (_) {},
              unblock: (_) {},
            ),
          ),
        ),
      ),
    );
    // Matrix отдаёт child не сразу (async init) — несколько pump'ов.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  }

  /// Весь текст, реально попавший в дерево виджетов.
  List<String> renderedTexts(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((s) => s.isNotEmpty)
      .toList();

  // Мультикейсный квантор «во всех локалях» — требование про «1970» не
  // привязано к языку: en-формат даёт «Jan 1, 1970», ru — «1 янв. 1970 г.».
  const locales = ['ru', 'en'];

  group('AC:RL-session-list-no-epoch-date/1 last_seen отсутствует', () {
    for (final locale in locales) {
      testWidgets('$locale: подпись = deviceId, никакой даты 1970', (
        tester,
      ) async {
        await pump(
          tester,
          Device(deviceId: 'VEFUPUKKOP', displayName: 'Liza web'),
          locale: locale,
        );

        final texts = renderedTexts(tester);
        expect(
          texts.any((t) => t.contains('1970')),
          isFalse,
          reason: 'на экране «Сеансы» не должно быть даты 1970: $texts',
        );
        expect(texts, contains('VEFUPUKKOP'));

        await teardownTree(tester);
      });
    }
  });

  group('AC:RL-session-list-no-epoch-date/2 last_seen == 0', () {
    for (final locale in locales) {
      testWidgets('$locale: epoch трактуется как «неизвестно»', (tester) async {
        await pump(
          tester,
          Device(
            deviceId: 'QBIUTWQAQN',
            displayName: 'Liza android',
            lastSeenTs: 0,
          ),
          locale: locale,
        );

        final texts = renderedTexts(tester);
        expect(texts.any((t) => t.contains('1970')), isFalse);
        expect(texts, contains('QBIUTWQAQN'));

        await teardownTree(tester);
      });
    }
  });

  group('AC:RL-session-list-no-epoch-date/3 анти-регресс: время есть', () {
    for (final locale in locales) {
      testWidgets('$locale: живой сеанс по-прежнему показывает дату', (
        tester,
      ) async {
        // Заведомо прошлый год — попадает в ветку yMMMd форматтера, поэтому
        // строка стабильна и не зависит от дня прогона.
        final ts = DateTime(DateTime.now().year - 2, 3, 14).millisecondsSinceEpoch;
        await pump(
          tester,
          Device(
            deviceId: 'ZMSCTPZXGA',
            displayName: 'Liza macos',
            lastSeenTs: ts,
          ),
          locale: locale,
        );

        final texts = renderedTexts(tester);
        expect(
          texts.any((t) => t.contains('${DateTime.now().year - 2}')),
          isTrue,
          reason: 'подпись должна остаться датой последней активности: $texts',
        );
        // deviceId подставляется ТОЛЬКО когда времени нет.
        expect(texts.contains('ZMSCTPZXGA'), isFalse);

        await teardownTree(tester);
      });
    }
  });

  group('AC:RL-session-list-no-epoch-date/4 имя сеанса локализовано', () {
    for (final displayName in <String?>[null, '']) {
      testWidgets('ru: displayName=${displayName ?? 'null'} → «Неизвестный сеанс»', (
        tester,
      ) async {
        await pump(
          tester,
          Device(deviceId: 'AIWWITSWGL', displayName: displayName),
        );

        expect(renderedTexts(tester), contains('Неизвестный сеанс'));

        await teardownTree(tester);
      });
    }

    test('литерала Unknown device не осталось в lib/', () {
      // В en-локали заглушка совпадает с прежним хардкодом, поэтому
      // «строка пришла из L10n, а не из кода» доказывается структурно.
      final hits = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          // lib/l10n/l10n_*.dart генерируются из .arb — там en-перевод и должен
          // лежать литералом; ловим хардкод в нашем собственном коде.
          .where((f) => !f.path.startsWith('lib/l10n/'))
          .where((f) => f.readAsStringSync().contains("'Unknown device'"))
          .map((f) => f.path)
          .toList();
      expect(hits, isEmpty);
    });
  });

  group('AC:RL-session-list-no-epoch-date/5 попап без литерала null', () {
    for (final displayName in <String?>[null, '']) {
      testWidgets('displayName=${displayName ?? 'null'}', (tester) async {
        await pump(
          tester,
          Device(deviceId: 'URQUCHRRHX', displayName: displayName),
        );

        await tester.tap(find.byType(ListTile));
        await tester.pumpAndSettle();

        final texts = renderedTexts(tester);
        expect(
          texts.any((t) => t.contains('null')),
          isFalse,
          reason: 'заголовок попапа не должен печатать литерал null: $texts',
        );
        expect(
          texts.any((t) => t.contains('URQUCHRRHX')),
          isTrue,
          reason: 'deviceId в заголовке попапа обязателен: $texts',
        );

        await teardownTree(tester);
      });
    }
  });

  group('AC:RL-session-list-no-epoch-date/6 иконка не зависит от локали', () {
    test('платформа определяется по сырому имени от клиента', () {
      expect(
        Device(deviceId: 'A', displayName: 'Liza android').icon,
        Icons.phone_android_outlined,
      );
      expect(
        Device(deviceId: 'B', displayName: 'Liza macos').icon,
        Icons.desktop_mac_outlined,
      );
      expect(
        Device(deviceId: 'C', displayName: 'Liza web').icon,
        Icons.web_outlined,
      );
      // Безымянный сеанс — «неизвестное устройство» независимо от того, на
      // каком языке ему подставили заглушку в UI.
      expect(
        Device(deviceId: 'D').icon,
        Icons.device_unknown_outlined,
      );
      expect(
        Device(deviceId: 'E', displayName: '').icon,
        Icons.device_unknown_outlined,
      );
    });
  });
}
