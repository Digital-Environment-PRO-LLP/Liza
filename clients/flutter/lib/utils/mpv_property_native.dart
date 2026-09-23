import 'package:matrix/matrix.dart';
import 'package:media_kit/media_kit.dart';

/// Применяет libmpv-свойство, если плеер использует нативный (libmpv)
/// бэкенд. На не-нативных бэкендах — no-op. Ошибки тюнинга логируются,
/// но не пробрасываются: настройка libmpv не должна ронять воспроизведение.
Future<void> setMpvProperty(Player player, String name, String value) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  try {
    await platform.setProperty(name, value);
  } catch (e) {
    Logs().w('mpv setProperty $name=$value failed: $e');
  }
}

/// Читает libmpv-свойство. Возвращает `null` если плеер не нативный
/// или чтение не удалось.
Future<String?> getMpvProperty(Player player, String name) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return null;
  try {
    return await platform.getProperty(name);
  } catch (e) {
    Logs().v('mpv getProperty $name failed: $e');
    return null;
  }
}
