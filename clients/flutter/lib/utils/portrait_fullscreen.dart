import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:liza/utils/adaptive_orientation.dart';

bool get _isMobile {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// Fullscreen-колбэки для `Video`-виджета media_kit, которые держат **ту же
/// политику ориентаций, что и всё приложение** (см.
/// [allowedOrientationsForCurrentView]): телефон — строго portrait,
/// планшет — поворот вслед за устройством.
///
/// Дефолтный `defaultEnterNativeFullscreen` (media_kit_video
/// `video_texture.dart`) на Android/iOS принудительно ставит
/// `[landscapeLeft, landscapeRight]` — из-за этого интерфейс Liza уходил
/// в горизонталь при разворачивании видео даже на телефоне. Мы вместо этого
/// переиспользуем общую политику, чтобы фуллскрин не ломал инвариант
/// «телефон — только портрет».
///
/// На desktop проблемы с ориентацией нет — там делегируем дефолтному
/// поведению (нативный fullscreen окна через MethodChannel).
/// См. `plans/media-v-format.md` §8.3.
Future<void> enterPortraitFullscreen() async {
  if (kIsWeb) return;
  if (_isMobile) {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
      // Ключевое отличие от дефолта media_kit: НЕ форсим landscape, а держим
      // политику устройства (телефон — портрет, планшет — все ориентации).
      await SystemChrome.setPreferredOrientations(
        allowedOrientationsForCurrentView(),
      );
    } catch (e) {
      Logs().w('enterPortraitFullscreen failed: $e');
    }
    return;
  }
  // macOS / Windows / Linux — дефолтный нативный fullscreen окна.
  await defaultEnterNativeFullscreen();
}

/// Парный колбэк к [enterPortraitFullscreen]: возвращает системный UI и
/// удерживает portrait.
Future<void> exitPortraitFullscreen() async {
  if (kIsWeb) return;
  if (_isMobile) {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(
        allowedOrientationsForCurrentView(),
      );
    } catch (e) {
      Logs().w('exitPortraitFullscreen failed: $e');
    }
    return;
  }
  await defaultExitNativeFullscreen();
}
