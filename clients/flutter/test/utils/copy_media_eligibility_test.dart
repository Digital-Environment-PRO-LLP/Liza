import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/copy_media_eligibility.dart';

/// ledger:RL-copy-media-eligibility
void main() {
  group('canCopyMediaDecision', () {
    bool copy(
      String type, {
      bool isSent = true,
      bool redacted = false,
      bool platform = true,
    }) => canCopyMediaDecision(
      messageType: type,
      isSent: isSent,
      redacted: redacted,
      platformSupportsImageClipboard: platform,
    );

    test('показывает для изображения и стикера', () {
      expect(copy(MessageTypes.Image), isTrue);
      expect(copy(MessageTypes.Sticker), isTrue);
    });

    test('скрывает для видео/аудио/файла/текста — не image-буфер', () {
      expect(copy(MessageTypes.Video), isFalse);
      expect(copy(MessageTypes.Audio), isFalse);
      expect(copy(MessageTypes.File), isFalse);
      expect(copy(MessageTypes.Text), isFalse);
      expect(copy(MessageTypes.BadEncrypted), isFalse);
    });

    test('скрывает на web/Linux (writeImage не поддержан)', () {
      expect(copy(MessageTypes.Image, platform: false), isFalse);
    });

    test('скрывает у не-отправленного и redacted', () {
      expect(copy(MessageTypes.Image, isSent: false), isFalse);
      expect(copy(MessageTypes.Image, redacted: true), isFalse);
    });
  });

  group('shouldOfferCopyText', () {
    test('текст — всегда показываем', () {
      expect(shouldOfferCopyText(isMedia: false, hasCaption: false), isTrue);
      expect(shouldOfferCopyText(isMedia: false, hasCaption: true), isTrue);
    });

    test('медиа без подписи — прячем (иначе копирует generic-заглушку)', () {
      expect(shouldOfferCopyText(isMedia: true, hasCaption: false), isFalse);
    });

    test('медиа с подписью — показываем (копирует подпись)', () {
      expect(shouldOfferCopyText(isMedia: true, hasCaption: true), isTrue);
    });
  });
}
