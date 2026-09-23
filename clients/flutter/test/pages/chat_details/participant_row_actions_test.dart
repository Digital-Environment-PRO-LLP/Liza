import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat_details/participant_row_actions.dart';

// Спек 2026-07-30 §1.2, ревью task-2: тап по СТРОКЕ участника
// (ParticipantListItem.build → ListTile.onTap) обязан вести в контекстное
// меню НЕЗАВИСИМО от активности кольца историй. ParticipantListItem целиком
// смонтировать в тесте нечем (нужен настоящий User/Room/Client
// matrix-dart-sdk), поэтому сам выбор колбэка вынесен в чистую функцию
// participantRowTapCallback и покрыт напрямую — так регресс вида «кто-то
// вернул `hasActiveRing ? openStories : openContextMenu` в onTap» ловится
// юнит-тестом, а не пропадает вместе с невозможностью смонтировать виджет.
void main() {
  group('participantRowTapCallback', () {
    test('при активном кольце строка всё равно ведёт в контекстное меню', () {
      final result = participantRowTapCallback<String>(
        hasActiveRing: true,
        openContextMenu: 'menu',
        openStories: 'stories',
      );
      expect(result, 'menu');
    });

    test('без кольца строка ведёт в контекстное меню', () {
      final result = participantRowTapCallback<String>(
        hasActiveRing: false,
        openContextMenu: 'menu',
        openStories: 'stories',
      );
      expect(result, 'menu');
    });
  });
}
