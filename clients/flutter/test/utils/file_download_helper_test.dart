import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:liza/utils/file_download_helper.dart';

void main() {
  // ledger:RL-multi-download-collision-safe
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('liza_download_test_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('uniqueDownloadPath', () {
    test('свободное имя оставляет как есть', () {
      expect(
        uniqueDownloadPath(dir, 'report.pdf'),
        p.join(dir.path, 'report.pdf'),
      );
    });

    test('коллизия → « (1)» перед расширением', () {
      File(p.join(dir.path, 'report.pdf')).writeAsBytesSync([1]);
      expect(
        uniqueDownloadPath(dir, 'report.pdf'),
        p.join(dir.path, 'report (1).pdf'),
      );
    });

    test('несколько коллизий инкрементят счётчик', () {
      File(p.join(dir.path, 'a.txt')).writeAsBytesSync([1]);
      File(p.join(dir.path, 'a (1).txt')).writeAsBytesSync([1]);
      expect(
        uniqueDownloadPath(dir, 'a.txt'),
        p.join(dir.path, 'a (2).txt'),
      );
    });

    test('имя без расширения тоже разруливается', () {
      File(p.join(dir.path, 'LICENSE')).writeAsBytesSync([1]);
      expect(
        uniqueDownloadPath(dir, 'LICENSE'),
        p.join(dir.path, 'LICENSE (1)'),
      );
    });
  });

  group('writeToDownloadDirectory', () {
    test('пишет байты и возвращает фактический путь', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final path = await writeToDownloadDirectory(dir, 'data.bin', bytes);

      expect(path, p.join(dir.path, 'data.bin'));
      expect(await File(path).readAsBytes(), bytes);
    });

    test('не затирает существующий файл, а создаёт новый', () async {
      final first = await writeToDownloadDirectory(
        dir,
        'x.bin',
        Uint8List.fromList([1]),
      );
      final second = await writeToDownloadDirectory(
        dir,
        'x.bin',
        Uint8List.fromList([2]),
      );

      expect(first, isNot(second));
      expect(await File(first).readAsBytes(), Uint8List.fromList([1]));
      expect(await File(second).readAsBytes(), Uint8List.fromList([2]));
    });
  });
}
