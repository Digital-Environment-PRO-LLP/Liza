import 'package:flutter/widgets.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

/// Дескриптор идущей записи голосового: как узнать её длительность и как
/// её отменить. Владелец — `RecordingViewModelState`, он же регистрирует и
/// снимает дескриптор.
class ActiveVoiceRecording {
  final Duration Function() durationOf;
  final VoidCallback cancel;

  const ActiveVoiceRecording({required this.durationOf, required this.cancel});
}

/// Глобальный реестр активной записи голосового. Композер в приложении всегда
/// один, поэтому одновременно может идти только одна запись — держим её в
/// единственном слоте.
///
/// Зачем: состояние записи живёт в `RecordingViewModel`, вложенном в поле
/// ввода чата, и молча обрывается его `dispose()` при уходе с экрана. Точки
/// навигации (`PopScope` чата на mobile-back и тап по другому чату в списке в
/// двухпанельном режиме) не видят это состояние. Реестр даёт им общий способ
/// узнать про идущую запись и предупредить пользователя ПРЕЖДЕ, чем дерево
/// пересоберётся и запись пропадёт (паттерн Liza: «Прекратить запись и
/// сбросить сообщение?»).
class VoiceRecordingGuard {
  VoiceRecordingGuard._();

  static final ValueNotifier<ActiveVoiceRecording?> notifier =
      ValueNotifier(null);

  /// Короче этого порога запись сбрасывается молча, без диалога — как в
  /// Liza (случайное касание микрофона нечего подтверждать).
  static const Duration minPromptDuration = Duration(milliseconds: 700);

  static void register(ActiveVoiceRecording recording) {
    notifier.value = recording;
  }

  static void unregister(ActiveVoiceRecording recording) {
    if (identical(notifier.value, recording)) notifier.value = null;
  }

  /// Проверяет, можно ли уходить с текущего чата.
  ///
  /// Возвращает `true`, если записи нет либо она осознанно сброшена
  /// пользователем (в этом случае запись уже отменена) — можно навигировать.
  /// Возвращает `false`, если пользователь выбрал остаться.
  static Future<bool> confirmLeave(BuildContext context) async {
    final recording = notifier.value;
    if (recording == null) return true;
    if (recording.durationOf() < minPromptDuration) {
      recording.cancel();
      return true;
    }
    final result = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).discardRecordingTitle,
      message: L10n.of(context).discardRecordingQuestion,
      okLabel: L10n.of(context).discardRecordingConfirm,
      cancelLabel: L10n.of(context).no,
      isDestructive: true,
    );
    if (result == OkCancelResult.ok) {
      recording.cancel();
      return true;
    }
    return false;
  }
}
