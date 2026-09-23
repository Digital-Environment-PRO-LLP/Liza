import 'package:flutter/foundation.dart';

import 'package:liza/utils/voip/voip_handle.dart';
import 'package:liza/widgets/matrix.dart';

import 'package:liza/utils/voip_plugin.dart' deferred as voip_impl;

/// Граница отложенной загрузки звонилки.
///
/// Всё, что за `voip_impl`, попадает в отдельный чанк: `flutter_webrtc`,
/// экран `pages/dialer` и `utils/voip/*`. Единственное место в приложении,
/// где `voip_plugin.dart` упоминается, — импорт выше; любой обычный `import`
/// того же файла в другом месте вернёт webrtc в основной чанк и обнулит
/// весь смысл разбиения.
Future<VoipHandle?> loadVoipPlugin(MatrixState matrix) async {
  try {
    await voip_impl.loadLibrary();
    return voip_impl.VoipPlugin(matrix);
  } catch (e, s) {
    // Чанк не доехал (офлайн, битый кеш, порезанная раздача). Звонки —
    // не критичный путь: приложение обязано работать без них, а UI-гейты
    // сами прячут кнопку звонка по `voipPlugin == null`.
    debugPrint('[VOIP] Не удалось загрузить чанк звонилки: $e\n$s');
    return null;
  }
}
