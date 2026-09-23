// ledger:RL-account-delete-no-mxid
// AC:RL-account-delete-no-mxid/1 AC:RL-account-delete-no-mxid/2
// AC:RL-account-delete-no-mxid/3 AC:RL-account-delete-no-mxid/4
//
// Страж диалога удаления аккаунта (LABA-2550): в нём нет ни слова «Matrix» и
// нет поля ввода, зато целиком видны имя и логин удаляемого аккаунта.
// Диалог принимает данные параметрами и не трогает Matrix — поэтому рендерится
// по-настоящему, без живого клиента (образец — test/support_dialog_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/settings_security/delete_account_dialog.dart';

const _shortLogin = '@user_f86a7e57:user.liza.ru';
const _longLogin = '@user_f86a7e57_with_a_very_long_name:user.liza.ru';

Future<bool?> _pumpDialog(
  WidgetTester tester, {
  required Locale locale,
  String login = _shortLogin,
  String title = 'user_f86a7e57',
  Size? surfaceSize,
}) async {
  bool? result;
  if (surfaceSize != null) {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  // l10n.yaml включает use-deferred-loading, поэтому каждая локаль — отложенная
  // библиотека с настоящим loadLibrary(). pumpAndSettle реальные футуры не
  // крутит, и вторая по счёту локаль в файле дала бы пустое дерево.
  await tester.runAsync(() => L10n.delegate.load(locale));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDeleteAccountDialog(
                context,
                accountTitle: title,
                accountLogin: login,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

/// Все видимые строки поддерева диалога — так проверяем именно то, что читает
/// человек, а не содержимое .arb.
Iterable<String> _visibleTexts(WidgetTester tester) sync* {
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final data = w.data;
    if (data != null) yield data;
  }
  for (final w in tester.widgetList<SelectableText>(find.byType(SelectableText))) {
    final data = w.data;
    if (data != null) yield data;
  }
}

void main() {
  // AC-1: ни «Matrix», ни поля ввода. Ловит откат к confirmMatrixId/supposedMxid.
  // AC:RL-account-delete-no-mxid/1
  for (final locale in const [Locale('ru'), Locale('en')]) {
    testWidgets(
      'AC-1: в диалоге нет слова Matrix и нет поля ввода (${locale.languageCode})',
      (tester) async {
        await _pumpDialog(tester, locale: locale);

        final offenders = _visibleTexts(
          tester,
        ).where((t) => t.toLowerCase().contains('matrix')).toList();
        expect(
          offenders,
          isEmpty,
          reason: 'Пользователю не показываем внутренний термин Matrix: '
              '${offenders.join(" | ")}',
        );
        expect(
          find.byType(TextField),
          findsNothing,
          reason: 'Ввод технической строки убран — подтверждение без набора',
        );
        expect(find.byType(TextFormField), findsNothing);

        // Закрываем диалог: незакрытый маршрут утекает в следующий кейс.
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      },
    );
  }

  // AC-2: имя и логин видны ЦЕЛИКОМ, на узких экранах тоже, без overflow.
  // AC:RL-account-delete-no-mxid/2
  for (final login in const [_shortLogin, _longLogin]) {
    for (final width in const [320.0, 360.0, 414.0]) {
      testWidgets(
        'AC-2: логин ${login.length} симв. виден целиком при ширине $width',
        (tester) async {
          await _pumpDialog(
            tester,
            locale: const Locale('ru'),
            login: login,
            surfaceSize: Size(width, 800),
          );

          expect(
            _visibleTexts(tester),
            contains(login),
            reason: 'Логин должен быть показан целиком, не обрезан',
          );
          expect(
            find.text('user_f86a7e57'),
            findsOneWidget,
            reason: 'Видно, ЧЕЙ аккаунт удаляется',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'Раскладка не должна переполняться на узком экране',
          );
        },
      );
    }
  }

  // AC-3: отмена не подтверждает, и деструктивная кнопка не автофокусная.
  // AC:RL-account-delete-no-mxid/3
  testWidgets('AC-3: «Отмена» возвращает false', (tester) async {
    await _pumpDialog(tester, locale: const Locale('ru'));

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(find.text('Удалить этот аккаунт?'), findsNothing);
  });

  testWidgets('AC-3: дисмисс по barrier возвращает false', (tester) async {
    await _pumpDialog(tester, locale: const Locale('ru'));

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Удалить этот аккаунт?'), findsNothing);
  });

  // Enter не должен сносить аккаунт: фокус по умолчанию на «Отмена».
  // AC:RL-account-delete-no-mxid/3
  testWidgets('AC-3: деструктивная кнопка не autofocus', (tester) async {
    await _pumpDialog(tester, locale: const Locale('ru'));

    final buttons = tester.widgetList<TextButton>(find.byType(TextButton));
    for (final b in buttons) {
      final label = b.child;
      if (label is Text && label.data == 'Удалить аккаунт') {
        expect(
          b.autofocus,
          isFalse,
          reason: 'Деструктив не должен срабатывать по Enter',
        );
      }
    }
  });

  // AC-4: подтверждение — единственный путь к true.
  // AC:RL-account-delete-no-mxid/4
  testWidgets('AC-4: подтверждение возвращает true', (tester) async {
    bool? result;
    await tester.runAsync(() => L10n.delegate.load(const Locale('ru')));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDeleteAccountDialog(
                  context,
                  accountTitle: 'user_f86a7e57',
                  accountLogin: _shortLogin,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(result, isNull, reason: 'До выбора диалог ничего не возвращает');

    await tester.tap(find.text('Удалить аккаунт'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
