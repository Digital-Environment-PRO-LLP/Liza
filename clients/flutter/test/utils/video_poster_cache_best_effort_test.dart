// LABA-2625: запись постера в кэш на пути ОТПРАВКИ видео — best-effort.
// Безусловный `storeBytesForId` в `SendFileDialog._send` на Web звал
// `getTemporaryDirectory()` → MissingPluginException → общий снекбар
// «Ой, что-то пошло не так», видео не уходило. В host `flutter test`
// path_provider тоже не зарегистрирован — тот же сбой, что на Web, без
// эмуляции kIsWeb (константа). Web-ветку целиком закрывает manual AC-23.
//
// ledger:RL-media-send-instant-bubble

// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:liza/utils/video_poster_cache.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.tempPath);
  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));
  late Directory sandbox;

  setUpAll(() {
    sandbox = Directory.systemTemp.createTempSync('laba2625_');
  });
  tearDownAll(() => sandbox.deleteSync(recursive: true));

  // Порядок важен: синглтон кэширует каталог после ПЕРВОЙ удачной записи,
  // поэтому сначала оба сбоя, потом рабочий каталог.
  test(
    'AC:RL-media-send-instant-bubble/24 — нет path_provider (как на Web): '
    'голая запись бросает, best-effort отдаёт false без исключения',
    () async {
      // Red-proof: так вёл себя вызов в _send до фикса.
      await expectLater(
        VideoPosterCache.instance.storeBytesForId('txid-a', bytes),
        throwsA(isA<MissingPluginException>()),
      );
      expect(
        await VideoPosterCache.instance.storeBytesForIdBestEffort(
          'txid-a',
          bytes,
        ),
        isFalse,
      );
    },
  );

  test('AC:RL-media-send-instant-bubble/25 — сбой записи на диск (каталог '
      'не создаётся) не бросает; рабочий каталог — постер на диске', () async {
    // tempDir указывает на ФАЙЛ: create() каталога внутри него падает —
    // модель «нет прав / диск» на desktop.
    final notADir = File('${sandbox.path}/not_a_dir')..writeAsStringSync('x');
    PathProviderPlatform.instance = _FakePathProvider(notADir.path);
    expect(
      await VideoPosterCache.instance.storeBytesForIdBestEffort(
        'txid-b',
        bytes,
      ),
      isFalse,
    );

    final good = Directory('${sandbox.path}/tmp')..createSync();
    PathProviderPlatform.instance = _FakePathProvider(good.path);
    expect(
      await VideoPosterCache.instance.storeBytesForIdBestEffort(
        'txid-c',
        bytes,
      ),
      isTrue,
    );
    final stored = File('${good.path}/liza_video_posters/txid-c.jpg');
    expect(stored.existsSync(), isTrue);
    expect(stored.readAsBytesSync(), bytes);
  });
}
