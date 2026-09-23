import 'package:flutter/material.dart';

enum StoryRingState { none, seen, unseen }

/// Оборачивает аватарку градиентным кольцом сторисов.
/// none - кольца нет; seen - тусклое серое; unseen - яркий градиент.
///
/// Кольцо рисуется ВНУТРИ заданного [size] (аватарка ужимается на толщину
/// кольца + зазор), поэтому общий бокс остаётся ровно [size] и не вылезает
/// за пределы родительского контейнера (иначе кольцо обрезалось в списке
/// чатов, где аватарка лежит в SizedBox фиксированного размера).
class StoryAvatarRing extends StatelessWidget {
  const StoryAvatarRing({
    required this.state,
    required this.child,
    this.size = 56,
    super.key,
  });

  final StoryRingState state;
  final Widget child;
  final double size;

  // Тонкое кольцо: жирное визуально перегружало мелкие аватарки в списках.
  static const double ringWidth = 1.5;
  static const double gap = 1.5;

  @override
  Widget build(BuildContext context) {
    if (state == StoryRingState.none) {
      return SizedBox(width: size, height: size, child: child);
    }
    final theme = Theme.of(context);
    final gradient = state == StoryRingState.unseen
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFE0080), Color(0xFFFF8C00), Color(0xFFFFD600)],
          )
        : LinearGradient(
            colors: [
              theme.colorScheme.outlineVariant,
              theme.colorScheme.outlineVariant,
            ],
          );
    return SizedBox(
      width: size,
      height: size,
      child: Container(
        padding: const EdgeInsets.all(ringWidth),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gradient,
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.surface,
          ),
          padding: const EdgeInsets.all(gap),
          child: ClipOval(child: child),
        ),
      ),
    );
  }
}
