import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cross_file/cross_file.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/image_bubble.dart';
import 'package:liza/utils/animated_gif.dart';
import 'package:liza/utils/compress_image.dart';
import 'package:liza/widgets/mxc_image.dart';
import 'test_client.dart';

/// ledger:RL-gif-send-animated
///
/// Заявка №43: GIF уходил JPEG-ом (compressImageForSending) и в ленте
/// рисовался превью — анимация терялась. Стражи: GIF не сжимается и не
/// шринкается, превью — статичный первый кадр, лента грузит оригинал.

/// Настоящий многокадровый GIF: шум, чтобы LZW не ужал ниже порога 20 КБ
/// (иначе обход порога сжатия замаскировал бы баг).
Uint8List _animatedGif({int width = 160, int height = 120, int frames = 3}) {
  final rnd = Random(43);
  img.Image? anim;
  for (var f = 0; f < frames; f++) {
    final frame = img.Image(width: width, height: height, numChannels: 3);
    for (final p in frame) {
      p
        ..r = rnd.nextInt(256)
        ..g = rnd.nextInt(256)
        ..b = rnd.nextInt(256);
    }
    frame.frameDuration = 100;
    if (anim == null) {
      anim = frame;
    } else {
      anim.addFrame(frame);
    }
  }
  return img.encodeGif(anim!);
}

Future<int> _frameCount(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return codec.frameCount;
  } finally {
    codec.dispose();
  }
}

Event _imageEvent(
  Room room, {
  String body = 'anim.gif',
  String? mimetype = 'image/gif',
  int? size = 100000,
  int? w = 160,
  int? h = 120,
  String msgtype = MessageTypes.Image,
}) => Event(
  content: {
    'msgtype': msgtype,
    'body': body,
    'url': 'mxc://example.invalid/gif',
    'info': {
      if (mimetype != null) 'mimetype': mimetype,
      if (size != null) 'size': size,
      if (w != null) 'w': w,
      if (h != null) 'h': h,
    },
  },
  type: msgtype == MessageTypes.Sticker
      ? EventTypes.Sticker
      : EventTypes.Message,
  eventId: '\$gif',
  senderId: '@alice:example.invalid',
  originServerTs: DateTime(2026, 9, 25),
  room: room,
);

/// Снимает пузырь и докручивает таймаут/ретраи загрузки MxcImage (фейковый
/// сервер медиа не отдаёт) — иначе «Timer is still pending».
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 5));
}

void main() {
  late Uint8List gif;

  setUpAll(() {
    gif = _animatedGif();
  });

  test('фикстура честная: многокадровый GIF > 20 КБ', () async {
    expect(gif.length, greaterThan(20 * 1000));
    expect(String.fromCharCodes(gif.sublist(0, 6)), 'GIF89a');
  });

  group('отправка', () {
    test(
      'AC-1: GIF минует сжатие, прочие картинки идут в компрессор',
      () async {
        // AC:RL-gif-send-animated/1
        final compressed = <XFile>[];
        Future<XFile> spy(XFile f) async {
          compressed.add(f);
          return XFile.fromData(Uint8List(1), name: 'x.jpg');
        }

        final byMime = XFile.fromData(
          gif,
          name: 'pasted',
          mimeType: 'image/gif',
        );
        final byName = XFile.fromData(
          gif,
          path: '/Users/x/Desktop/CleanShot 09.42.17.gif',
        );
        final png = XFile.fromData(
          Uint8List(30000),
          name: 'photo.png',
          mimeType: 'image/png',
        );

        final out = await compressImagesForSending([
          byMime,
          byName,
          png,
        ], compress: spy);

        expect(identical(out[0], byMime), isTrue);
        expect(identical(out[1], byName), isTrue);
        expect(await out[1].readAsBytes(), gif);
        expect(compressed, hasLength(1));
        expect(identical(compressed.single, png), isTrue);
      },
    );

    test('AC-2: SDK-shrink для GIF выключен, для фото — как было', () {
      // AC:RL-gif-send-animated/2
      expect(shrinkImageMaxDimensionFor(isGif: true, batch: 1600), isNull);
      expect(shrinkImageMaxDimensionFor(isGif: false, batch: 1600), 1600);
      expect(shrinkImageMaxDimensionFor(isGif: false, batch: null), isNull);
    });

    testWidgets('AC-3: оригинал байт-в-байт + статичное превью ≤ 800 px', (
      tester,
    ) async {
      // AC:RL-gif-send-animated/3
      final big = _animatedGif(width: 1200, height: 300);
      final result = await tester.runAsync(
        () => prepareGifForSending(big, name: 'wide.gif'),
      );
      final file = result!.file;
      expect(file.bytes, big);
      expect(file.mimeType, 'image/gif');
      expect(file.info['w'], 1200);
      expect(file.info['h'], 300);

      final thumb = result.thumbnail!;
      expect(thumb.mimeType, isNot('image/gif'));
      expect(String.fromCharCodes(thumb.bytes.sublist(1, 4)), isNot('GIF'));
      expect(thumb.width, 800);
      expect(thumb.height, 200);
      expect(thumb.name, 'wide.png');
      expect(thumb.blurhash, isNotNull);
      expect(file.blurhash, thumb.blurhash);
      expect(await tester.runAsync(() => _frameCount(thumb.bytes)), 1);
      expect(await tester.runAsync(() => _frameCount(file.bytes)), 3);
    });

    testWidgets('битые байты → отправка без превью, а не отказ', (
      tester,
    ) async {
      final junk = Uint8List.fromList(List.filled(100, 7));
      final result = await tester.runAsync(
        () => prepareGifForSending(junk, name: 'bad.gif'),
      );
      expect(result!.thumbnail, isNull);
      expect(result.file.bytes, junk);
      expect(result.file.mimeType, 'image/gif');
    });
  });

  group('показ', () {
    late Room room;

    setUpAll(() async {
      room = Room(
        id: '!gif:example.invalid',
        client: await prepareTestClient(),
      );
    });

    test('AC-4: предикат «играть в ленте» — таблица кейсов', () {
      // AC:RL-gif-send-animated/4
      bool animate(Event e, {bool autoplay = true}) =>
          shouldAnimateGifInline(e, autoplay: autoplay);

      expect(animate(_imageEvent(room)), isTrue);
      expect(animate(_imageEvent(room, mimetype: null)), isTrue); // по имени
      expect(animate(_imageEvent(room, w: null, h: null)), isTrue);
      expect(animate(_imageEvent(room, size: kInlineGifMaxBytes)), isTrue);

      expect(animate(_imageEvent(room), autoplay: false), isFalse);
      expect(animate(_imageEvent(room, size: kInlineGifMaxBytes + 1)), isFalse);
      expect(animate(_imageEvent(room, w: 2001, h: 2000)), isFalse);
      expect(animate(_imageEvent(room, size: null)), isFalse);
      expect(
        animate(_imageEvent(room, body: 'p.png', mimetype: 'image/png')),
        isFalse,
      );
      expect(
        animate(_imageEvent(room, msgtype: MessageTypes.Sticker)),
        isFalse,
      );
    });

    Future<void> pumpBubble(WidgetTester tester, Event event) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: Scaffold(body: ImageBubble(event, width: 256, height: 192)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('AC-5: GIF в ленте грузит оригинал с декодом под пузырь', (
      tester,
    ) async {
      // AC:RL-gif-send-animated/5
      await pumpBubble(tester, _imageEvent(room));
      final mxc = tester.widget<MxcImage>(find.byType(MxcImage).first);
      expect(mxc.isThumbnail, isFalse);
      expect(mxc.cacheWidth, (256 * tester.view.devicePixelRatio).round());
      expect(find.byType(GifBadge), findsNothing);
      await _dispose(tester);
    });

    testWidgets('AC-5/6: GIF вне лимита — превью + бейдж «GIF»', (
      tester,
    ) async {
      // AC:RL-gif-send-animated/6
      await pumpBubble(tester, _imageEvent(room, size: kInlineGifMaxBytes + 1));
      final mxc = tester.widget<MxcImage>(find.byType(MxcImage).first);
      expect(mxc.isThumbnail, isTrue);
      expect(mxc.cacheWidth, isNull);
      expect(find.byType(GifBadge), findsOneWidget);
      expect(find.text('GIF'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('обычное фото — без изменений: превью, без бейджа', (
      tester,
    ) async {
      await pumpBubble(
        tester,
        _imageEvent(room, body: 'p.jpg', mimetype: 'image/jpeg'),
      );
      final mxc = tester.widget<MxcImage>(find.byType(MxcImage).first);
      expect(mxc.isThumbnail, isTrue);
      expect(find.byType(GifBadge), findsNothing);
      await _dispose(tester);
    });

    test('AC-7: self-heal не считает полноразмерный GIF из кэша битым', () {
      // AC:RL-gif-send-animated/7
      expect(
        MxcImage.isPoisonedImageCache(
          wasInLocalStore: true,
          isThumbnail: false,
          msgtype: MessageTypes.Image,
          mimeType: 'image/gif',
          bytes: gif,
        ),
        isFalse,
      );
    });
  });
}
