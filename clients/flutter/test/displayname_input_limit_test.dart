// Страж реестра регрессии: ledger:RL-displayname-input-limit (см. tests/registry/).
//
// LABA-2549: поле «Отображаемое имя» не имело лимита — диалог разрастался на
// десятки строк, а «Displayname is too long (max 256)» прилетало от Synapse уже
// ПОСЛЕ нажатия «Ок». Тест рендерит РЕАЛЬНЫЙ прод-диалог
// (showDisplaynameInputDialog из lib/pages/settings/settings.dart), а не реплику.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/settings/settings.dart';

/// Семья ZWJ: одна грапема, семь кодпойнтов. 100 таких проходят грапемный
/// `maxLength: 256`, но дают ~700 рун — Synapse считает именно руны.
const _zwjFamily = '\u{1F468}‍\u{1F469}‍\u{1F467}‍\u{1F466}';

Future<String?> _pumpDialog(
  WidgetTester tester, {
  String initialText = '',
  TargetPlatform platform = TargetPlatform.android,
}) async {
  String? result;
  var closed = false;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ru'),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDisplaynameInputDialog(
                context,
                initialText: initialText,
              );
              closed = true;
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
  addTearDown(() => closed);
  return result;
}

Finder get _field => find.byType(EditableText);

/// Значение поля после применения всех input-formatters.
String _text(WidgetTester tester) =>
    tester.widget<EditableText>(_field).controller.text;

Future<void> _tapOk(WidgetTester tester) async {
  await tester.tap(find.text('Ок').last);
  await tester.pumpAndSettle();
}

/// Корень LABA-2549 — `maxLines: null` растил поле до размеров окна. Меряем
/// высоту самого диалога: на Material это [Dialog], на Cupertino —
/// [CupertinoAlertDialog].
Future<void> _expectDialogHeightStable(
  WidgetTester tester,
  TargetPlatform platform,
) async {
  await _pumpDialog(tester, platform: platform);
  final dialog = platform == TargetPlatform.android
      ? find.byType(Dialog)
      : find.byType(CupertinoAlertDialog);

  await tester.enterText(_field, 'a' * 5);
  await tester.pumpAndSettle();
  final small = tester.getSize(dialog);

  await tester.enterText(_field, 'a' * 300);
  await tester.pumpAndSettle();

  expect(
    tester.getSize(dialog).height,
    small.height,
    reason: 'диалог вырос на $platform (регресс maxLines: null)',
  );
  expect(tester.takeException(), isNull);

  // Перевод строки тоже не должен растить поле.
  await tester.enterText(_field, 'a\nb\nc');
  await tester.pumpAndSettle();
  expect(tester.getSize(dialog).height, small.height);
}

void main() {
  group('лимит отображаемого имени — ledger:RL-displayname-input-limit', () {
    testWidgets('257-й символ не принимается — AC:RL-displayname-input-limit/1', (
      tester,
    ) async {
      await _pumpDialog(tester);
      await tester.enterText(_field, 'a' * 300);
      await tester.pumpAndSettle();

      expect(_text(tester).characters.length, maxDisplaynameLength);
    });

    testWidgets(
      'окно не растёт на Material — AC:RL-displayname-input-limit/2',
      (tester) async => _expectDialogHeightStable(tester, TargetPlatform.android),
    );

    testWidgets(
      'окно не растёт на Cupertino — AC:RL-displayname-input-limit/2',
      (tester) async => _expectDialogHeightStable(tester, TargetPlatform.iOS),
    );

    testWidgets('ровно 256 символов — валидное значение — AC:RL-displayname-input-limit/3', (
      tester,
    ) async {
      await _pumpDialog(tester);
      await tester.enterText(_field, 'a' * maxDisplaynameLength);
      await tester.pumpAndSettle();
      await _tapOk(tester);

      // Диалог закрылся — значит validator промолчал.
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('счётчик виден на Material: 0/256 и 256/256 — AC:RL-displayname-input-limit/4', (
      tester,
    ) async {
      await _pumpDialog(tester);
      expect(find.text('0/$maxDisplaynameLength'), findsOneWidget);

      await tester.enterText(_field, 'a' * maxDisplaynameLength);
      await tester.pumpAndSettle();
      expect(
        find.text('$maxDisplaynameLength/$maxDisplaynameLength'),
        findsOneWidget,
      );
    });

    testWidgets(
      'длинное initialText: «Ок» не закрывает диалог, показана ошибка — AC:RL-displayname-input-limit/5',
      (tester) async {
        // Формматтеры применяются к ПРАВКАМ, начальное значение они не режут:
        // без validator «Ок» без единой правки уехал бы в 400 от Synapse.
        await _pumpDialog(tester, initialText: 'a' * 300);
        await _tapOk(tester);

        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Не длиннее 256 символов'), findsOneWidget);
      },
    );

    testWidgets(
      'ZWJ-эмодзи: грапем ≤ 256, рун > 256 — «Ок» заблокирован — AC:RL-displayname-input-limit/6',
      (tester) async {
        final emojiName = _zwjFamily * 100;
        expect(emojiName.characters.length, lessThanOrEqualTo(maxDisplaynameLength));
        expect(emojiName.runes.length, greaterThan(maxDisplaynameLength));

        await _pumpDialog(tester, initialText: emojiName);
        await _tapOk(tester);

        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Не длиннее 256 символов'), findsOneWidget);
      },
    );
  });
}
