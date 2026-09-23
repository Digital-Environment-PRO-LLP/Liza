import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:liza/config/setting_keys.dart';
import 'package:liza/utils/platform_infos.dart';

/// Каталог для авто-сохранения вложений (Liza-стиль: без диалога «Сохранить
/// как»).
///
/// Возвращает `null`, если авто-сохранение недоступно — тогда вызывающий
/// откатывается на системный диалог (web — прямая загрузка браузером в
/// «Загрузки»; mobile — SAF-диалог). Каталог есть только на desktop: сначала
/// настроенная пользователем папка ([AppSettings.downloadDestinationPath]), при
/// пустой/несуществующей — системные «Загрузки».
Future<Directory?> resolveDownloadDirectory() async {
  if (!PlatformInfos.isDesktop) return null;

  final configured = AppSettings.downloadDestinationPath.value;
  if (configured.isNotEmpty) {
    final dir = Directory(configured);
    if (await dir.exists()) return dir;
  }

  try {
    return await getDownloadsDirectory();
  } catch (_) {
    return null;
  }
}

/// Путь внутри [directory], не затирающий уже существующий файл: при коллизии
/// имени добавляет « (1)», « (2)» перед расширением (как в браузерах/Liza).
String uniqueDownloadPath(Directory directory, String fileName) {
  final ext = p.extension(fileName);
  final base = p.basenameWithoutExtension(fileName);

  var candidate = p.join(directory.path, fileName);
  var counter = 1;
  while (File(candidate).existsSync()) {
    candidate = p.join(directory.path, '$base ($counter)$ext');
    counter++;
  }
  return candidate;
}

/// Пишет [bytes] в [directory] под именем [fileName] (коллизии разруливает
/// [uniqueDownloadPath]). Возвращает итоговый путь сохранённого файла.
Future<String> writeToDownloadDirectory(
  Directory directory,
  String fileName,
  Uint8List bytes,
) async {
  final file = File(uniqueDownloadPath(directory, fileName));
  await file.writeAsBytes(bytes);
  return file.path;
}
