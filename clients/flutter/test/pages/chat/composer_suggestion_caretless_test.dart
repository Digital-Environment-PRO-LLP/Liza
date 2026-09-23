// Страж РЕГРЕССИИ ledger:RL-composer-suggestion-insert-caretless.
//
// Прод-дефект (GlitchTip issue 184: 29 событий, 13 юзеров, 2026-06-08 … 09-07,
// включая свежую сборку 3746; macOS 22 / iOS 6):
//   ArgumentError: RangeError (end): Invalid value: Only valid value is 0: -1
//   #1 _StringBase.substring
//   #2 _InputBarState.insertSuggestion (input_bar.dart:470)
//   #3 _RawAutocompleteState._onChangedField (autocomplete.dart:488)
//
// Цепочка (воспроизводима, НЕ гонка): `insertSuggestion` подвешена как
// `displayStringForOption`. Flutter считает эту функцию ЧИСТОЙ (option → строка),
// а она читает ЖИВОЙ controller. После выбора подсказки `_RawAutocompleteState`
// держит `_selection` не-null; пользователь сразу отправляет сообщение, и
// `send()` делает `sendController.text = pendingText` — сеттер
// `TextEditingController.text` ПРИНУДИТЕЛЬНО ставит `collapsed(offset: -1)`.
// Изменение будит `_onChangedField`, тот после `await optionsBuilder` зовёт
// `displayStringForOption` → `''.substring(0, -1)`.
//
// Формулировка «Only valid value is 0» доказывает `text.length == 0`, то есть это
// именно путь очистки после отправки.
//
// Ущерб: uncaught async zone error (не краш) — но `_onChangedField` обрывается до
// `_updateOptionsViewVisibility()`, а `_selection` залипает не-null, поэтому
// следующая отправка с пустого поля бросает снова (серии у одного юзера).
//
// Инвариант в проекте УЖЕ принят, просто не был применён здесь: соседние
// `optionsBuilder`-хелперы (input_bar.dart:142-146, 153-157) проверяют
// `baseOffset < 0`, а `Chat.insertEmojiIntoText` нормализует каретку с
// комментарием ровно про `baseOffset == -1` (страж RL-composer-emoji-picker-toggle).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:liza/pages/chat/input_bar.dart';
import 'package:liza/widgets/matrix.dart' as liza_matrix;

import '../../utils/test_client.dart';

// InputBar тянет клиента через Matrix.of(context) в optionsBuilder — подменяем
// только геттер client (конвенция forwarded_attribution/channel_peek_message_render:
// полноценный Matrix-виджет неоправданно тяжёл).
class _TestMatrixState extends liza_matrix.MatrixState {
  _TestMatrixState(this._client);
  final Client _client;
  @override
  Client get client => _client;
}

void main() {
  group('AC-1 — caretOffset нормализует отсутствующую каретку (∀ кейсы)', () {
    // Квантор «всегда» из разбора: подсказки бывают command/emoji/emote/user/room,
    // а текст — пустой и непустой. Нормализация обязана быть тотальной, поэтому
    // проверяем предикат на всех граничных входах, а не на одном примере.
    test('AC:RL-composer-suggestion-insert-caretless/1 — offset -1 → конец текста',
        () {
      expect(InputBar.caretOffset('', -1), 0);
      expect(InputBar.caretOffset('/men', -1), 4);
      expect(InputBar.caretOffset('привет @ali', -1), 11);
    });

    test(
        'AC:RL-composer-suggestion-insert-caretless/1 — валидная каретка не '
        'трогается', () {
      expect(InputBar.caretOffset('/menu', 0), 0);
      expect(InputBar.caretOffset('/menu', 3), 3);
      expect(InputBar.caretOffset('/menu', 5), 5);
    });

    test(
        'AC:RL-composer-suggestion-insert-caretless/1 — каретка за пределами '
        'текста прижимается (гонка «текст укоротили, offset остался»)', () {
      expect(InputBar.caretOffset('ab', 99), 2);
      expect(InputBar.caretOffset('', 7), 0);
    });
  });

  group('AC-2 — прод-функция displayStringForOption не падает без каретки', () {
    // guard.render:real-widget — берём НЕ реплику логики, а само замыкание
    // `displayStringForOption` из смонтированного прод-`RawAutocomplete`
    // (это и есть `_InputBarState.insertSuggestion`, привязанный к живому state).
    // Так тест проверяет ровно ту функцию, чей кадр стоит в прод-стеке.
    //
    // Почему не «эмулируем гонку целиком»: боевое окно между сеттером `.text`
    // (ставит offset −1) и нормализацией selection у сфокусированного
    // EditableText в host-тесте недетерминированно — при `enterText` поле в
    // фокусе и каретка сразу становится 0. Дёргать функцию напрямую с боевым
    // состоянием контроллера — честнее, чем подгонять окружение под зелёный.
    late Client client;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
      client.backgroundSync = false;
    });

    tearDown(() async => client.dispose());

    Future<String Function(Map<String, String?>)> mountAndGetDisplayString(
      WidgetTester tester,
      TextEditingController controller,
    ) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<liza_matrix.MatrixState>.value(
            value: _TestMatrixState(client),
            child: Scaffold(
              body: InputBar(
                room: Room(id: '!chat:example.invalid', client: client),
                controller: controller,
                focusNode: FocusNode(),
                minLines: 1,
                maxLines: 5,
                decoration:
                    const InputDecoration(hintText: 'Напишите сообщение…'),
                suggestionEmojis: const [],
                // Прод-виджет разыменовывает эти поля через `!` — в реальном
                // композере их всегда задаёт вызывающая сторона.
                keyboardType: TextInputType.multiline,
                autofocus: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester
          .widget<RawAutocomplete<Map<String, String?>>>(
            find.byType(RawAutocomplete<Map<String, String?>>),
          )
          .displayStringForOption;
    }

    testWidgets(
        'AC:RL-composer-suggestion-insert-caretless/2 — каретки нет (offset −1) '
        'на ПУСТОМ поле: ∀ типов подсказки без исключения', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final displayString = await mountAndGetDisplayString(tester, controller);

      // Боевое состояние: ровно то, что оставляет `sendController.text = ''`
      // в chat.dart (сеттер .text форсит collapsed(offset: -1)).
      controller.value = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: -1),
      );
      expect(controller.selection.baseOffset, -1,
          reason: 'анти-тавтология: без −1 тест воспроизводит не тот сценарий');

      // Квантор «∀ типов» из разбора: подсказка бывает пяти видов, и до фикса
      // падал ЛЮБОЙ — substring рушился раньше веток по типу.
      for (final suggestion in <Map<String, String?>>[
        {'type': 'command', 'name': 'menu'},
        {'type': 'emoji', 'emoji': '🙂', 'current_word': ':smi'},
        {'type': 'emote', 'name': 'party', 'pack': 'pack1'},
        {'type': 'user', 'mention': '@ali:example.invalid'},
        {'type': 'room', 'mxid': '#room:example.invalid'},
      ]) {
        expect(() => displayString(suggestion), returnsNormally,
            reason: 'тип ${suggestion['type']} бросил на пустом поле без каретки');
      }
    });

    testWidgets(
        'AC:RL-composer-suggestion-insert-caretless/3 — каретки нет на '
        'НЕПУСТОМ поле: подстановка идёт в конец, текст не теряется',
        (tester) async {
      // Вторая половина инварианта: нормализация обязана не только не падать,
      // но и вести себя осмысленно — иначе «фикс» молча съедал бы текст.
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final displayString = await mountAndGetDisplayString(tester, controller);

      controller.value = const TextEditingValue(
        text: 'привет @ali',
        selection: TextSelection.collapsed(offset: -1),
      );

      final result = displayString(
          {'type': 'user', 'mention': '@ali:example.invalid'});
      expect(result, contains('@ali:example.invalid'));
      expect(result, startsWith('привет '));
    });
  });
}
