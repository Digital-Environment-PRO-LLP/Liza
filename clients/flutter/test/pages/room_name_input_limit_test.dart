// Страж реестра регрессии: ledger:RL-room-name-input-limit (см. tests/registry/).
//
// LABA-2536: переименование группы не имело лимита — диалог разрастался на
// тысячи строк и выдавливал кнопки «Отмена/Ок», а длинное имя сохранялось и
// потом ломало вёрстку там, где рендерится (тултип компании в nav-rail).
// Главный экран создания (NewGroup) лимита тоже не имел — вопреки тексту
// тикета, 64 жили ровно в одном месте (space_view).
//
// Тесты бьют по РЕАЛЬНЫМ прод-виджетам (showRoomNameInputDialog, NewGroup,
// NaviRailItem), а не по репликам раскладки.

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat_details/chat_details.dart';
import 'package:liza/pages/chat_list/navi_rail_item.dart';
import 'package:liza/pages/chat_list/space_view.dart';
import 'package:liza/pages/new_group/new_group.dart';
import 'package:liza/utils/room_name_limit.dart';
import 'package:liza/widgets/matrix.dart';

import '../utils/test_client.dart';

Finder get _field => find.byType(EditableText);

String _text(WidgetTester tester) =>
    tester.widget<EditableText>(_field).controller.text;

Widget _wrap(
  Widget child, {
  TargetPlatform platform = TargetPlatform.android,
}) => MaterialApp(
  theme: ThemeData(platform: platform),
  locale: const Locale('ru'),
  localizationsDelegates: const [
    L10n.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: L10n.supportedLocales,
  home: child,
);

/// Вычисляемое SDK имя безымянной группы — в диалог идёт подсказкой.
const _computedName = 'Группа с Анной';

/// Открывает РЕАЛЬНЫЙ диалог переименования; результат (после закрытия) — в
/// [sink]. [initialText] — текущее `m.room.name` комнаты.
Future<void> _pumpRenameDialog(
  WidgetTester tester, {
  String initialText = '',
  TargetPlatform platform = TargetPlatform.android,
  void Function(String?)? sink,
}) async {
  await tester.pumpWidget(
    _wrap(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final name = await showRoomNameInputDialog(
                context,
                currentName: initialText,
                computedName: _computedName,
              );
              sink?.call(name);
            },
            child: const Text('open'),
          ),
        ),
      ),
      platform: platform,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// `find.byType(Dialog)` на Cupertino пуст даже при открытом окне.
Finder _dialogOf(TargetPlatform platform) => platform == TargetPlatform.android
    ? find.byType(Dialog)
    : find.byType(CupertinoAlertDialog);

Future<void> _tapOk(WidgetTester tester) async {
  await tester.tap(find.text('Ок').last);
  await tester.pumpAndSettle();
}

/// Корень скриншота 1 — `maxLines: null` растил поле до размеров окна.
Future<void> _expectDialogHeightStable(
  WidgetTester tester,
  TargetPlatform platform,
) async {
  await _pumpRenameDialog(tester, platform: platform);
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

  await tester.enterText(_field, 'a\nb\nc');
  await tester.pumpAndSettle();
  expect(tester.getSize(dialog).height, small.height);
}

/// Текст ошибки пустого имени — тип-НЕЙТРАЛЬНЫЙ (`pleaseEnterAName`).
const _emptyNameError = 'Введите название';

/// Строка, из-за которой заведён LABA-2535: обещала выбор из вариантов.
const _oldMisleadingError = 'Пожалуйста, выберите';

void main() {
  group('пустое название чата — ledger:RL-room-name-input-limit', () {
    // AC-10/AC-11/AC-12 гоняются на РЕАЛЬНОМ showAddRoomNameDialog: сам
    // SpaceView в widget-тесте неподъёмен (power levels на m.space.child +
    // сетевой singleSpaceService.fetch() в initState), поэтому диалог вынесен
    // в top-level функцию — как showRoomNameInputDialog.
    /// Открывает РЕАЛЬНЫЙ прод-диалог; в [sink] ложится его результат.
    Future<void> openDialog(
      WidgetTester tester,
      AddRoomType roomType, {
      TargetPlatform platform = TargetPlatform.android,
      void Function(String?)? sink,
    }) async {
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final name = await showAddRoomNameDialog(context, roomType);
                  sink?.call(name);
                },
                child: const Text('open'),
              ),
            ),
          ),
          platform: platform,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> tapCreate(WidgetTester tester) async {
      await tester.tap(find.text('Создать').last);
      await tester.pumpAndSettle();
    }

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final roomType in AddRoomType.values) {
        testWidgets(
          'пустое имя (${roomType.name}, $platform): понятная ошибка, диалог жив '
          '— AC:RL-room-name-input-limit/10',
          (tester) async {
            await openDialog(tester, roomType, platform: platform);
            await tapCreate(tester);

            expect(
              find.text(_emptyNameError),
              findsOneWidget,
              reason: 'нет понятного текста ошибки пустого имени',
            );
            expect(
              find.text(_oldMisleadingError),
              findsNothing,
              reason: 'вернулась строка LABA-2535 «$_oldMisleadingError»',
            );
            // Видимое состояние, а не возвращённое значение: null отдаёт и
            // «Отмена», такой ассерт зелен на закрытом диалоге.
            expect(
              platform == TargetPlatform.android
                  ? find.byType(Dialog)
                  : find.byType(CupertinoAlertDialog),
              findsOneWidget,
              reason: 'диалог закрылся на пустом имени',
            );
          },
        );

        testWidgets(
          'имя из одних пробелов (${roomType.name}, $platform) не проходит '
          '— AC:RL-room-name-input-limit/11',
          (tester) async {
            await openDialog(tester, roomType, platform: platform);
            await tester.enterText(_field, '   ');
            await tester.pumpAndSettle();
            await tapCreate(tester);

            expect(
              find.text(_emptyNameError),
              findsOneWidget,
              reason: 'пробельное имя создало чат с невидимым названием',
            );
          },
        );
      }
    }

    testWidgets(
      'валидное имя возвращается обрезанным — AC:RL-room-name-input-limit/11',
      (tester) async {
        String? result;
        await openDialog(
          tester,
          AddRoomType.chat,
          sink: (name) => result = name,
        );

        await tester.enterText(_field, '  Отдел  ');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Создать').last);
        await tester.pumpAndSettle();

        expect(
          result,
          'Отдел',
          reason: 'пробелы по краям уехали бы в m.room.name',
        );
      },
    );

    testWidgets(
      'ошибка гаснет при вводе символа — AC:RL-room-name-input-limit/12',
      (tester) async {
        // Корень LABA-2535 не только в словах: error ставился по «Ок» и не
        // снимался никогда — любая формулировка висела под заполненным полем.
        await openDialog(tester, AddRoomType.chat);
        await tester.tap(find.text('Создать').last);
        await tester.pumpAndSettle();
        expect(find.text(_emptyNameError), findsOneWidget);

        await tester.enterText(_field, 'О');
        await tester.pumpAndSettle();

        expect(
          find.text(_emptyNameError),
          findsNothing,
          reason: 'ошибка залипла под уже заполненным полем',
        );
      },
    );
  });

  group('лимит названия чата — ledger:RL-room-name-input-limit', () {
    testWidgets(
      '65-й символ не принимается при переименовании — AC:RL-room-name-input-limit/1',
      (tester) async {
        await _pumpRenameDialog(tester);
        await tester.enterText(_field, 'a' * 300);
        await tester.pumpAndSettle();

        expect(_text(tester).characters.length, maxRoomNameLength);
      },
    );

    testWidgets(
      'окно переименования не растёт на Material — AC:RL-room-name-input-limit/2',
      (tester) => _expectDialogHeightStable(tester, TargetPlatform.android),
    );

    testWidgets(
      'окно переименования не растёт на Cupertino — AC:RL-room-name-input-limit/2',
      (tester) => _expectDialogHeightStable(tester, TargetPlatform.iOS),
    );

    testWidgets('легаси-имя длиннее лимита: диалог цел, укорачивание проходит '
        '— AC:RL-room-name-input-limit/4', (tester) async {
      // Формматтеры применяются к ПРАВКАМ — подставленное длинное имя они не
      // режут. Пользователь обязан иметь возможность его укоротить, а не
      // упереться в заблокированный «Ок» (валидатора здесь нет намеренно).
      await _pumpRenameDialog(tester, initialText: 'a' * 300);
      expect(tester.takeException(), isNull);
      expect(_text(tester).characters.length, 300);

      await tester.enterText(_field, 'Короткое имя');
      await tester.pumpAndSettle();
      await _tapOk(tester);

      expect(find.byType(Dialog), findsNothing);
    });

    // LABA-2534: переименование в пустое сохраняло группу как «Пустой чат».
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final input in ['', '   ']) {
        testWidgets('переименование в «$input» ($platform) отбивается '
            '— AC:RL-room-name-input-limit/18', (tester) async {
          await _pumpRenameDialog(
            tester,
            initialText: 'Старое имя',
            platform: platform,
          );
          await tester.enterText(_field, input);
          await tester.pumpAndSettle();
          await _tapOk(tester);

          expect(
            find.text(_emptyNameError),
            findsOneWidget,
            reason: 'пустое имя ушло бы в m.room.name → «Пустой чат»',
          );
          // Видимое состояние: null отдаёт и «Отмена», и незакрытый диалог.
          expect(
            _dialogOf(platform),
            findsOneWidget,
            reason: 'диалог закрылся на пустом имени',
          );
        });
      }
    }

    testWidgets('переименование возвращает имя без пробелов по краям '
        '— AC:RL-room-name-input-limit/19', (tester) async {
      String? result;
      await _pumpRenameDialog(
        tester,
        initialText: 'Старое имя',
        sink: (name) => result = name,
      );
      await tester.enterText(_field, '  Имя  ');
      await tester.pumpAndSettle();
      await _tapOk(tester);

      expect(result, 'Имя');
    });

    for (final initial in ['Старое имя', 'a' * 300]) {
      testWidgets('«Ок» без правок закрывает диалог (${initial.length} симв.) '
          '— AC:RL-room-name-input-limit/20', (tester) async {
        // Анти-оверфикс: валидатор непустоты не должен превратиться в залок
        // уже сохранённого (в т.ч. легаси-длинного) имени.
        String? result;
        await _pumpRenameDialog(
          tester,
          initialText: initial,
          sink: (name) => result = name,
        );
        await _tapOk(tester);

        expect(find.byType(Dialog), findsNothing, reason: 'появился залок');
        expect(result, initial);
      });
    }

    testWidgets(
      'ошибка переименования гаснет при вводе — AC:RL-room-name-input-limit/21',
      (tester) async {
        await _pumpRenameDialog(tester, initialText: 'Старое имя');
        await tester.enterText(_field, '');
        await tester.pumpAndSettle();
        await _tapOk(tester);
        expect(find.text(_emptyNameError), findsOneWidget);

        await tester.enterText(_field, 'Н');
        await tester.pumpAndSettle();

        expect(find.text(_emptyNameError), findsNothing);
      },
    );

    testWidgets(
      'безымянная группа: поле пустое, вычисляемое имя — подсказкой, «Ок» '
      'отбивается — AC:RL-room-name-input-limit/22',
      (tester) async {
        // Раньше в поле стояло «Группа с Анной», и «Ок» замораживал его в
        // m.room.name — имя переставало следить за участниками.
        await _pumpRenameDialog(tester);

        expect(_text(tester), '');
        expect(find.text(_computedName), findsOneWidget);

        await _tapOk(tester);
        expect(find.text(_emptyNameError), findsOneWidget);
        expect(find.byType(Dialog), findsOneWidget);
      },
    );

    testWidgets('у названной группы вычисляемого имени в подсказке нет '
        '— AC:RL-room-name-input-limit/23', (tester) async {
      await _pumpRenameDialog(tester, initialText: 'Старое имя');
      await tester.enterText(_field, '');
      await tester.pumpAndSettle();

      expect(
        find.text(_computedName),
        findsNothing,
        reason: 'подсказка обещала бы сброс к вычисляемому, а он запрещён',
      );
    });

    test('roomRenameTarget: что уходит в m.room.name '
        '— AC:RL-room-name-input-limit/24', () {
      const current = 'Старое имя';
      expect(roomRenameTarget(null, currentName: current), isNull);
      expect(roomRenameTarget('', currentName: current), isNull);
      expect(roomRenameTarget('   ', currentName: current), isNull);
      expect(roomRenameTarget(' Старое имя ', currentName: current), isNull);
      expect(roomRenameTarget('  X  ', currentName: current), 'X');
      expect(roomRenameTarget('X', currentName: ''), 'X');
    });

    testWidgets(
      'счётчик виден на Material: 0/64 и 64/64 — AC:RL-room-name-input-limit/5',
      (tester) async {
        await _pumpRenameDialog(tester);
        expect(find.text('0/$maxRoomNameLength'), findsOneWidget);

        await tester.enterText(_field, 'a' * maxRoomNameLength);
        await tester.pumpAndSettle();
        expect(
          find.text('$maxRoomNameLength/$maxRoomNameLength'),
          findsOneWidget,
        );
      },
    );
  });

  group('лимит на экране создания — ledger:RL-room-name-input-limit', () {
    late Client client;
    late SharedPreferences store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      client = await prepareTestClient(loggedIn: true);
      // Фоновый sync держит таймер живым и роняет тест на «A Timer is still
      // pending even after the widget tree was disposed».
      client.backgroundSync = false;
      store = await SharedPreferences.getInstance();
    });

    tearDown(() async {
      await client.dispose(closeDatabase: true);
    });

    Future<void> pumpNewGroup(WidgetTester tester, CreateGroupType type) async {
      await tester.pumpWidget(
        _wrap(
          Matrix(
            clients: [client],
            store: store,
            child: NewGroup(createGroupType: type),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    for (final type in CreateGroupType.values) {
      testWidgets('создание ${type.name}: 65-й символ не принимается '
          '— AC:RL-room-name-input-limit/3', (tester) async {
        await pumpNewGroup(tester, type);
        await tester.enterText(_field.first, 'a' * 300);
        await tester.pump();

        expect(
          _text(tester).characters.length,
          maxRoomNameLength,
          reason: 'поле имени на экране создания ${type.name} без лимита',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(minutes: 1));
      });
    }

    /// Кнопку ищем по типу: её подпись совпадает с заголовком AppBar
    /// («Создать канал»/«Создать компанию»), и find.text даёт два виджета.
    Future<void> tapCreate(WidgetTester tester) async {
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
    }

    Future<void> teardownScreen(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 1));
    }

    // Компания и канал: пустое имя — ошибка. У публичного канала alias
    // выводится из имени, а Synapse пустой localpart НЕ отвергает — первый
    // такой канал молча получал мусорный alias «#:<домен>», второй падал с
    // M_ROOM_IN_USE сырой английской строкой.
    for (final type in [CreateGroupType.channel, CreateGroupType.space]) {
      for (final input in ['', '   ']) {
        testWidgets('создание ${type.name}: имя «$input» не проходит '
            '— AC:RL-room-name-input-limit/13', (tester) async {
          await pumpNewGroup(tester, type);
          if (input.isNotEmpty) {
            await tester.enterText(_field.first, input);
            await tester.pump();
          }
          await tapCreate(tester);

          expect(
            find.text(_emptyNameError),
            findsOneWidget,
            reason: 'пустое имя ${type.name} ушло на сервер',
          );
          await teardownScreen(tester);
        });
      }
    }

    testWidgets(
      'ошибка стоит НАД кнопкой создания — AC:RL-room-name-input-limit/16',
      (tester) async {
        await pumpNewGroup(tester, CreateGroupType.channel);
        await tapCreate(tester);
        await tester.pumpAndSettle();

        final errorDy = tester.getTopLeft(find.text(_emptyNameError)).dy;
        final buttonDy = tester.getTopLeft(find.byType(ElevatedButton)).dy;
        expect(
          errorDy,
          lessThan(buttonDy),
          reason: 'ошибка под кнопкой — на скролле её не видно',
        );
        await teardownScreen(tester);
      },
    );

    // Анти-оверфикс: безымянная группа — поддерживаемое состояние продукта
    // (_createGroup шлёт groupName: null, SDK считает имя по участникам).
    // Красный этот тест станет на кандидате «валидатор во всех точках».
    for (final input in ['', '   ']) {
      testWidgets('создание group: имя «$input» гейтом НЕ блокируется '
          '— AC:RL-room-name-input-limit/14', (tester) async {
        await pumpNewGroup(tester, CreateGroupType.group);
        if (input.isNotEmpty) {
          await tester.enterText(_field.first, input);
          await tester.pump();
        }
        await tapCreate(tester);

        expect(
          find.text(_emptyNameError),
          findsNothing,
          reason: 'у безымянной группы отобрали право на пустое имя',
        );
        tester.takeException();
        await teardownScreen(tester);
      });
    }
  });

  group('тултип компании в nav-rail — ledger:RL-room-name-input-limit', () {
    Future<void> pumpRail(WidgetTester tester, String toolTip) async {
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: NaviRailItem(
              toolTip: toolTip,
              isSelected: false,
              onTap: () {},
              icon: const Icon(Icons.home),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(Icon)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets(
      'длинное имя компании не разносит тултип — AC:RL-room-name-input-limit/7',
      (tester) async {
        await pumpRail(tester, 'Очень длинное имя компании ' * 20);

        final tooltipText = find.descendant(
          of: find.byType(Tooltip),
          matching: find.byType(Text),
        );
        expect(tooltipText, findsWidgets);
        final size = tester.getSize(tooltipText.last);
        expect(
          size.width,
          lessThanOrEqualTo(240.0),
          reason: 'тултип шире ограничителя — плашка на пол-экрана (LABA-2536)',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'короткое имя сохраняет стиль темы тултипа — AC:RL-room-name-input-limit/8',
      (tester) async {
        // richMessage, в отличие от message, НЕ наследует TooltipThemeData —
        // без явного стиля короткие тултипы теряли контраст.
        await pumpRail(tester, 'Лаба');

        final texts = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(Tooltip),
                matching: find.byType(Text),
              ),
            )
            .toList();
        expect(texts, isNotEmpty);
        expect(
          texts.last.style?.color,
          isNotNull,
          reason: 'у текста тултипа нет явного цвета — риск «тёмное на тёмном»',
        );
      },
    );
  });
}
