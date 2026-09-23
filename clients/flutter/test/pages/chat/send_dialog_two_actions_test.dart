// Страж раскладки диалога отправки: в ряду действий РОВНО два действия, а
// кнопка отправки и поле подписи видны без прокрутки внутри диалога — включая
// малый экран и открытую клавиатуру.
//
// Гоняется РЕАЛЬНЫЙ `SendFileDialog` в реальном `MaterialApp`/`Navigator`
// (не реплика — снимает MOCK_ONLY, ср. инцидент 3704).
//
// Почему НЕ ассертим «обе кнопки на одной горизонтали»: `CupertinoAlertDialog`
// ставит ряд только при ровно двух действиях И достаточной ширине, а русские
// «Отмена» + «Прислать» и вдвоём могут лечь столбцом. Измеримое — ЧИСЛО
// действий и ВИДИМОСТЬ последнего.
//
// ledger:RL-send-dialog-two-actions

library;

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/send_file_dialog.dart';
import 'package:liza/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

import '../../utils/test_client.dart';

const _roomId = '!twoactions:example.invalid';

XFile _file(String name, String mime) => XFile.fromData(
  Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
  mimeType: mime,
  path: name,
  name: name,
);

XFile _img(String name) => _file(name, 'image/png');

/// Наборы, на которых инвариант обязан держаться. Чистый видео-набор сюда НЕ
/// входит осознанно: `_isDesktop` читает `dart:io` (не `ThemeData.platform`),
/// поэтому на host он уходит в `_VideoThumbnailView` и падает на
/// `MediaKit.ensureInitialized`. Для видео третьей кнопки не было и раньше
/// (гейт `uniqueFileType == 'image'`), покрытие — manual-пунктом реестра.
final _sets = <String, List<XFile>>{
  'одно изображение': [_img('shot.png')],
  'три изображения': [_img('a.png'), _img('b.png'), _img('c.png')],
  'документ': [_file('contract.pdf', 'application/pdf')],
  'аудио': [_file('voice.mp3', 'audio/mpeg')],
  'смешанный фото+видео': [_img('a.png'), _file('clip.mp4', 'video/mp4')],
};

/// Хост с живым `Navigator`: `_send` зовёт `Navigator.pop()`.
///
/// **Ловушка, стоившая часа** (та же, что в `send_file_dialog_feedback_test`):
/// делегаты `L10n` грузятся ОТЛОЖЕННО (`use-deferred-loading`), до резолва
/// `MaterialApp` не строит `home` вовсе — нужны именно два `pump(500ms)`.
/// `pumpAndSettle` запрещён: живой `Client` крутит фоновые таймеры.
Future<void> _openDialog(
  WidgetTester tester,
  Room room,
  List<XFile> files, {
  required TargetPlatform platform,
  double keyboard = 0,
}) async {
  BuildContext? outer;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: ThemeData(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
        child: child!,
      ),
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

  showDialog<void>(
    context: outer!,
    builder: (_) => SendFileDialog(
      room: room,
      files: files,
      outerContext: outer!,
      threadLastEventId: null,
      threadRootEventId: null,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void _setScreen(WidgetTester tester, Size logical) {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = logical * 2.0;
  addTearDown(tester.view.reset);
}

void main() {
  late Client client;
  late Room room;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    room = Room(id: _roomId, client: client);
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  group('AC:RL-send-dialog-two-actions/1 — в ряду действий ровно два', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final entry in _sets.entries) {
        testWidgets('${entry.key} / ${platform.name}', (tester) async {
          _setScreen(tester, const Size(390, 844));
          await _openDialog(tester, room, entry.value, platform: platform);

          expect(
            find.byType(AdaptiveDialogAction),
            findsNWidgets(2),
            reason:
                'третье действие ломает раскладку: Cupertino ставит кнопки в '
                'ряд только при ровно двух, Material OverflowBar сваливается '
                'в столбец по ширине',
          );
        });
      }
    }
  });

  group('AC:RL-send-dialog-two-actions/8 — плитка «+» жива вместо кнопки', () {
    testWidgets('есть при наборе изображений, активна до отправки', (
      tester,
    ) async {
      _setScreen(tester, const Size(390, 844));
      await _openDialog(
        tester,
        room,
        [_img('shot.png')],
        platform: TargetPlatform.android,
      );

      final tile = find.byKey(const Key('add-more-tile'));
      expect(
        tile,
        findsOneWidget,
        reason: 'накопление не должно потеряться вместе с третьей кнопкой',
      );
      final inkWell = tester.widget<InkWell>(
        find.descendant(of: tile, matching: find.byType(InkWell)),
      );
      expect(inkWell.onTap, isNotNull);
    });

    testWidgets('нет при наборе-документе (гейт тот же, что был у кнопки)', (
      tester,
    ) async {
      _setScreen(tester, const Size(390, 844));
      await _openDialog(
        tester,
        room,
        [_file('contract.pdf', 'application/pdf')],
        platform: TargetPlatform.android,
      );

      expect(find.byKey(const Key('add-more-tile')), findsNothing);
    });
  });

  group('раскладка влезает в экран', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final screen in [const Size(375, 667), const Size(390, 844)]) {
        for (final keyboard in [0.0, 336.0]) {
          final label =
              '${platform.name} ${screen.width.toInt()}x'
              '${screen.height.toInt()} kb=${keyboard.toInt()}';

          testWidgets('AC:RL-send-dialog-two-actions/3 — «Прислать» видна: '
              '$label', (tester) async {
            _setScreen(tester, screen);
            await _openDialog(
              tester,
              room,
              [_img('shot.png')],
              platform: platform,
              keyboard: keyboard,
            );
            final l10n = await tester.runAsync(
              () => L10n.delegate.load(const Locale('ru')),
            );

            final available = screen.height - keyboard;
            final sendRect = tester.getRect(
              find.byWidget(
                tester.widget(
                  find.ancestor(
                    of: find.text(l10n!.send),
                    matching: find.byType(AdaptiveDialogAction),
                  ),
                ),
              ),
            );
            expect(
              sendRect.bottom,
              lessThanOrEqualTo(available),
              reason:
                  'кнопка отправки за пределами вьюпорта = «ловил прокрутку '
                  'внутри, чтобы найти клавиши»',
            );
          });

          testWidgets('AC:RL-send-dialog-two-actions/5 — подпись видна: $label',
              (tester) async {
            _setScreen(tester, screen);
            await _openDialog(
              tester,
              room,
              [_img('shot.png')],
              platform: platform,
              keyboard: keyboard,
            );
            final l10n = await tester.runAsync(
              () => L10n.delegate.load(const Locale('ru')),
            );

            final available = screen.height - keyboard;
            final captionRect = tester.getRect(
              find.text(l10n!.optionalMessage).first,
            );
            expect(
              captionRect.bottom,
              lessThanOrEqualTo(available),
              reason: 'поле подписи не должно уезжать под кнопки/за экран',
            );
          });

          testWidgets('AC:RL-send-dialog-two-actions/4 — нет overflow: $label',
              (tester) async {
            _setScreen(tester, screen);
            await _openDialog(
              tester,
              room,
              [_img('shot.png')],
              platform: platform,
              keyboard: keyboard,
            );

            expect(
              tester.takeException(),
              isNull,
              reason: 'RenderFlex overflow = вёрстка не влезла',
            );
          });
        }
      }
    }
  });
}
