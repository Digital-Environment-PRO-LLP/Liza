// Страж обратной связи диалога отправки: плашка подготовки для вложений БЕЗ
// пузыря-пре-эмита и защита от двойной отправки.
//
// Гоняется РЕАЛЬНЫЙ `SendFileDialog` в реальном `MaterialApp`/`ScaffoldMessenger`
// (не реплика — снимает MOCK_ONLY, ср. инцидент 3704).
//
// ledger:RL-media-send-instant-bubble

library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/send_file_dialog.dart';
import 'package:liza/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

import '../../utils/test_client.dart';

const _roomId = '!feedback:example.invalid';

XFile _img(String name) => XFile.fromData(
  Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
  mimeType: 'image/png',
  path: name,
  name: name,
);

XFile _doc(String name) => XFile.fromData(
  Uint8List.fromList(List<int>.filled(64, 7)),
  mimeType: 'application/pdf',
  path: name,
  name: name,
);

/// Хост с живым `Navigator` и `ScaffoldMessenger`: `_send` зовёт
/// `Navigator.pop()` и `ScaffoldMessenger.of(outerContext)`, поэтому диалог
/// обязан стоять на маршруте, а не быть просто вставлен в дерево.
///
/// **Ловушка, стоившая часа:** делегаты `L10n` грузятся ОТЛОЖЕННО
/// (`use-deferred-loading`). Пока загрузка не резолвится, `MaterialApp` не
/// строит `home` вообще — ни на `pumpWidget`, ни на голом `pump()`. Пробой
/// показал: нужны именно `pump(Duration)` (два по 500 мс), а `runAsync` не
/// помогает. `pumpAndSettle` здесь запрещён: живой `Client` крутит фоновые
/// таймеры, а плашка подготовки — `SnackBar` на 5 минут с
/// `dismissDirection: none`, который никогда не осядет.
Future<BuildContext> _pumpHost(WidgetTester tester) async {
  BuildContext? outer;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            outer = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  return outer!;
}

Future<void> _openDialog(
  WidgetTester tester,
  Room room,
  List<XFile> files,
) async {
  final outer = await _pumpHost(tester);
  showDialog<void>(
    context: outer,
    builder: (_) => SendFileDialog(
      room: room,
      files: files,
      outerContext: outer,
      threadLastEventId: null,
      threadRootEventId: null,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late Client client;
  late Room room;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    room = Room(id: _roomId, client: client);
    SendFileDialogState.sendRunsForTest = 0;
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await client.dispose(closeDatabase: true);
  });

  group(
    'AC:RL-media-send-instant-bubble/17 — индикатор для наборов без пре-эмита',
    () {
      testWidgets(
        'документ: плашка подготовки появляется сразу после тапа «Отправить»',
        (tester) async {
          late final Client c;
          await tester.runAsync(() async {
            c = client;
          });
          expect(c, isNotNull);

          await _openDialog(tester, room, [_doc('contract.pdf')]);

          final l10n = await tester.runAsync(
            () => L10n.delegate.load(const Locale('ru')),
          );
          final sendLabel = l10n!.send;

          expect(
            find.text(sendLabel),
            findsOneWidget,
            reason: 'кнопка «Прислать» обязана быть в диалоге',
          );
          expect(
            find.text(l10n.prepareSendingAttachment),
            findsNothing,
            reason: 'до тапа плашки быть не должно',
          );

          await tester.tap(find.text(sendLabel));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          expect(
            find.text(l10n.prepareSendingAttachment),
            findsOneWidget,
            reason:
                'фото/документы пузыря-пре-эмита не получают — им обратную '
                'связь даёт плашка; без неё жалоба «ничего не происходит» '
                'просто переезжает на не-видео (регресс первой редакции фикса)',
          );

          // AC:RL-media-send-instant-bubble/7 — плашка ОДНА долгоживущая, а не
          // пересоздаваемая. Прежний `showLoadingSnackBar` делал
          // `clearSnackBars()` + `showSnackBar()` на каждый тик: бар каждый раз
          // начинал входную анимацию (~250 мс) заново и на записи экрана не
          // появлялся ВООБЩЕ — это и был корень «ничего не происходит».
          // Тождество Element'а между кадрами и есть «не пересоздана».
          final first = find.byType(SnackBar).evaluate().single;
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final after = find.byType(SnackBar).evaluate().single;
          expect(
            identical(first, after),
            isTrue,
            reason:
                'SnackBar пересоздан — значит вернулся паттерн '
                'clearSnackBars()+showSnackBar() на тик, и индикатор снова '
                'невидим пользователю',
          );
        },
      );
    },
  );

  group(
    'AC:RL-media-send-instant-bubble/18 — двойной тап не даёт двойной отправки',
    () {
      testWidgets('два тапа в одном кадре дают ОДНУ отправку, не две', (
        tester,
      ) async {
        await _openDialog(tester, room, [_doc('contract.pdf')]);

        final l10n = await tester.runAsync(
          () => L10n.delegate.load(const Locale('ru')),
        );
        final sendLabel = l10n!.send;

        // Дёргаем РЕАЛЬНЫЙ обработчик кнопки диалога дважды подряд, без
        // кадра между вызовами — ровно так фреймворк видит два быстрых тапа
        // пользователя, которому «кажется, что ничего не происходит» (жалоба
        // LABA-2559). Через `tester.tap` это не воспроизводится: второй тап
        // молча промахивается по уже уходящему маршруту, и страж становится
        // ложно-зелёным (проверено red-proof'ом — без гарда он оставался
        // зелёным).
        final send = tester
            .widget<AdaptiveDialogAction>(
              find.ancestor(
                of: find.text(sendLabel),
                matching: find.byType(AdaptiveDialogAction),
              ),
            )
            .onPressed!;
        send();
        send();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(seconds: 2));

        expect(
          SendFileDialogState.sendRunsForTest,
          1,
          reason:
              'второй проход _send завёл бы свой набор txid — 2N пузырей и '
              'дублирующая отправка тех же файлов',
        );
      });
    },
  );

  group('AC:RL-media-send-instant-bubble/15 — лента не знает о пре-эмите', () {
    // Граница, а не косметика: вся ценность подхода B′ в том, что для ленты
    // пре-эмитнутое событие — ОБЫЧНОЕ событие таймлайна. Как только список
    // начнёт его особым образом опознавать (импорт `pending_send_echo`,
    // ветка по `txid`/`preEmit`), вернётся отклонённый комиссией кандидат B
    // с карточкой в footer-слоте: индексная арифметика `childCount`/
    // `findChildIndexCallback` разъедется, а члены альбома 2..N (скрытые
    // `gallerySkipEventIds`) дадут фантом-слоты.
    test('chat_event_list.dart не ссылается на механику пре-эмита', () {
      final code = File(
        'lib/pages/chat/chat_event_list.dart',
      ).readAsStringSync();
      expect(
        code.contains('pending_send_echo'),
        isFalse,
        reason: 'лента не должна знать про пре-эмит — он обычное событие',
      );
      expect(
        RegExp('preEmit', caseSensitive: false).hasMatch(code),
        isFalse,
        reason: 'ветка по признаку пре-эмита в ленте = возврат кандидата B',
      );
    });
  });

  group(
    'AC:RL-media-send-instant-bubble/22 — кнопки диалога взаимоисключающи',
    () {
      testWidgets('во время отправки плитка «+» недоступна', (tester) async {
        // Накопление рисуется только для набора изображений — берём его.
        await _openDialog(tester, room, [_img('shot.png')]);

        final l10n = await tester.runAsync(
          () => L10n.delegate.load(const Locale('ru')),
        );

        AdaptiveDialogAction actionOf(String label) => tester.widget(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AdaptiveDialogAction),
          ),
        );

        // Аффорданс накопления переехал из `actions` в ленту превью
        // (RL-send-dialog-two-actions): в ряду действий их теперь ровно два.
        // Ассерт БЕЗУСЛОВНЫЙ — прежняя обёртка `if (найдено)` позволяла бы
        // инварианту `_busy` тихо перестать проверяться.
        InkWell addMoreTile() => tester.widget(
          find.descendant(
            of: find.byKey(const Key('add-more-tile')),
            matching: find.byType(InkWell),
          ),
        );

        expect(
          addMoreTile().onTap,
          isNotNull,
          reason: 'до отправки плитка «+» активна',
        );

        actionOf(l10n!.send).onPressed!();
        await tester.pump();

        // Пока `_send` висит в подготовке, диалог ещё на экране — и вот здесь
        // активная плитка звала бы второй `Navigator.pop()` того же маршрута
        // и открывала новый диалог поверх идущей отправки, а старый `_send`
        // продолжал бы грузить исходный список: два параллельных цикла
        // отправки одних и тех же файлов.
        expect(
          addMoreTile().onTap,
          isNull,
          reason: 'гарды _sending и _addingMore обязаны быть взаимоисключающими',
        );

        // Дать `_send` дойти до `finally` и снять плашку: её `SnackBar` живёт
        // 5 минут, и незавершённый таймер уронил бы тест на
        // «A Timer is still pending» уже ПОСЛЕ ассерта.
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
      });
    },
  );
}
