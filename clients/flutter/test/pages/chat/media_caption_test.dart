// LABA-2207: подпись к медиа с разметкой (XL шлёт formatted_body с
// <strong>/<em>) должна рендериться как HTML, а не сырыми тегами. Юнит на
// чистое решение `captionFormattedHtml` (рендер MediaCaption — smoke на
// устройстве, как у GalleryBubble).

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat/events/media_caption.dart';

void main() {
  group('captionFormattedHtml', () {
    test('возвращает HTML при format=org.matrix.custom.html', () {
      final html = captionFormattedHtml({
        'msgtype': 'm.image',
        'body': 'жирная подпись',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<strong>жирная</strong> <em>подпись</em>',
      });
      expect(html, '<strong>жирная</strong> <em>подпись</em>');
    });

    test('null, если formatted_body есть, но format не выставлен', () {
      expect(
        captionFormattedHtml({
          'msgtype': 'm.image',
          'formatted_body': '<strong>x</strong>',
        }),
        isNull,
      );
    });

    test('null для обычной плейн-подписи (нет разметки)', () {
      expect(
        captionFormattedHtml({'msgtype': 'm.image', 'body': 'просто подпись'}),
        isNull,
      );
    });

    test('null, если formatted_body пустой', () {
      expect(
        captionFormattedHtml({
          'msgtype': 'm.image',
          'format': 'org.matrix.custom.html',
          'formatted_body': '',
        }),
        isNull,
      );
    });
  });
}
