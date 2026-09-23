// Юнит-тесты чистых функций просмотрщика видео:
//  - `buildVideoFailureDiag` — структурная строка мониторинга провала БЕЗ
//    ключа/iv/токена (пин RL-mediadiag-no-secret).
//
// ⚠️ Предикат `shouldShowVideoSaveButton` и его тесты УДАЛЕНЫ (2026-08-31):
// in-viewer кнопка «Сохранить» снесена (требование руководителя «никакого
// скачивания рядом с проблемой воспроизведения»). Намеренное «Сохранить файл»
// теперь ТОЛЬКО в long-press меню сообщения (`message_context_menu.dart`), где
// content-protection гейт (`!contentProtected`) уже пинуется отдельно.
//
// Реестр: tests/registry/RL-video-viewer-save-and-overlay.md,
//         tests/registry/RL-mediadiag-no-secret.md
// Дизайн: docs/superpowers/specs/2026-08-31-video-streaming-no-download-affordances-design.md
//
// ledger:RL-video-viewer-save-and-overlay
// ledger:RL-mediadiag-no-secret

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/image_viewer/video_player.dart';

void main() {
  group('buildVideoFailureDiag (мониторинг без секретов)', () {
    // AC:RL-mediadiag-no-secret/video-fail
    test('несёт безопасные поля, НЕ несёт ключ/iv/токен', () {
      final line = EventVideoPlayerState.buildVideoFailureDiag(
        reason: 'watchdog-no-progress',
        e2ee: true,
        onWeb: false,
        local: false,
        mimetype: 'video/mp4',
        size: 169644629,
        host: 'synapse.liza.laba.prodamus.tech',
      );
      // Безопасные поля присутствуют.
      expect(line, contains('reason=watchdog-no-progress'));
      expect(line, contains('e2ee=true'));
      expect(line, contains('mime=video/mp4'));
      expect(line, contains('size=169644629'));
      expect(line, contains('host=synapse.liza.laba.prodamus.tech'));
      // Секретов нет — структурно (сигнатура не принимает key/iv/token).
      final lower = line.toLowerCase();
      expect(lower.contains('bearer'), isFalse);
      expect(lower.contains('key='), isFalse);
      expect(lower.contains('"k"'), isFalse);
      expect(lower.contains('iv='), isFalse);
      expect(lower.contains('token'), isFalse);
      expect(lower.contains('authorization'), isFalse);
    });

    test('null-поля не роняют и не подставляют секрет', () {
      final line = EventVideoPlayerState.buildVideoFailureDiag(
        reason: 'libmpv-fatal',
        e2ee: false,
        onWeb: true,
        local: true,
        mimetype: null,
        size: null,
        host: null,
      );
      expect(line, contains('reason=libmpv-fatal'));
      expect(line, contains('web=true'));
      expect(line, contains('local=true'));
      expect(line.toLowerCase().contains('bearer'), isFalse);
    });
  });
}
