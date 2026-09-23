import 'package:media_kit/media_kit.dart';

/// На Web бэкенда libmpv нет — тюнинг mpv-свойств не применяется.
Future<void> setMpvProperty(Player player, String name, String value) async {}

/// На Web getProperty всегда null.
Future<String?> getMpvProperty(Player player, String name) async => null;
