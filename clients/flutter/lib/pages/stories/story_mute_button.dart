import 'package:flutter/material.dart';

/// Показывать ли кнопку-грамофон (mute) в шапке вьюера сторис.
///
/// Только для видео-сторисов (у фото звука нет) и только при неразвёрнутой
/// подписи (при `captionExpanded` шапку перекрывает caption-оверлей — иначе
/// иконка оказалась бы под ним, R4). Вынесено в чистый предикат, чтобы гейт
/// был тестируем без полного вьюера. [ledger:RL-story-video-mute-control]
bool shouldShowStoryMuteButton({
  required bool isVideo,
  required bool captionExpanded,
}) => isVideo && !captionExpanded;

/// Кнопка включения/выключения звука видео-сториса.
///
/// Состояние живёт во ВНЕШНЕМ [muted] ([StoryViewerController.storyMuted]),
/// общем на весь сеанс просмотра, — поэтому переключение «распространяется на
/// остальные истории» (③) и переживает пересоздание плеера по `ValueKey`.
/// Дефолт (значение notifier'а при открытии) — приглушено (②). Живёт в
/// структурной шапке рядом с крестиком закрытия → выравнивание даёт
/// layout-движок, без magic-offset из чужого поддерева (①).
class StoryMuteButton extends StatelessWidget {
  final ValueNotifier<bool> muted;

  const StoryMuteButton({required this.muted, super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: muted,
    builder: (context, isMuted, _) => IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: Icon(
        isMuted ? Icons.volume_off : Icons.volume_up,
        color: Colors.white,
      ),
      onPressed: () => muted.value = !muted.value,
    ),
  );
}
