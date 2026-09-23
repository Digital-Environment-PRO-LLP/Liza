import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Переводит вертикальное колесо обычной мыши в горизонтальную прокрутку
/// вложенного ряда (LABA-2240). Горизонтальный `Scrollable` во Flutter берёт
/// дельту только из `scrollDelta.dx`, а обычная мышь шлёт лишь `dy` → ряд стоит,
/// а событие достаётся родительскому вертикальному списку.
///
/// Обёртка регистрируется в [PointerSignalResolver], а НЕ двигает контроллер
/// напрямую: иначе родительский вертикальный скролл перехватил бы то же событие
/// и список поехал бы вниз одновременно с горизонтальным сдвигом (двойное
/// движение). Как самый глубокий претендент, зарегистрировавшийся первым, обёртка
/// выигрывает резолвер и гасит родителя. На краю ряда (двигаться некуда) она
/// намеренно не регистрируется — тогда родитель докручивает список.
///
/// [child] обязан использовать тот же [controller], что передан сюда.
class HorizontalMouseWheel extends StatelessWidget {
  const HorizontalMouseWheel({
    required this.controller,
    required this.child,
    super.key,
  });

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        // Трекпад/тач ходят другими путями (PanZoom / drag), у них обе оси уже
        // работают нативно — вмешиваемся только в колесо мыши.
        if (event.kind != PointerDeviceKind.mouse) return;
        if (!controller.hasClients) return;
        final position = controller.position;
        final target = (position.pixels + event.scrollDelta.dy).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        // Ряд у края в этом направлении — отдаём событие родителю (докрутит
        // вертикальный список), не занимая резолвер.
        if (target == position.pixels) return;
        GestureBinding.instance.pointerSignalResolver.register(
          event,
          (_) => position.pointerScroll(event.scrollDelta.dy),
        );
      },
      child: child,
    );
  }
}
