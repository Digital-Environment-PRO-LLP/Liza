import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:collection/collection.dart';

import 'package:liza/utils/platform_infos.dart';

/// Порог "планшета" по короткой стороне экрана в логических пикселях.
/// 700dp строже стандартного Material sw600dp: отсекает мелкие
/// планшеты/складники в разложенном виде, iPad mini (~744dp) остаётся
/// планшетом.
const double kTabletShortestSide = 700;

bool _isTablet(Size size) => size.shortestSide >= kTabletShortestSide;

/// Разрешённые ориентации для данного размера экрана: телефон — строго
/// `portraitUp`; планшет — все четыре (следует физическому повороту).
///
/// `shortestSide == 0` (экран ещё не измерен на раннем boot) трактуется как
/// телефон — это строгая, безопасная политика по умолчанию.
List<DeviceOrientation> allowedOrientationsForSize(Size size) => _isTablet(size)
    ? const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]
    : const [DeviceOrientation.portraitUp];

/// Политика ориентаций по текущему размеру главного `FlutterView` — для
/// вызова вне дерева виджетов (boot в `main`, media_kit-колбэки фуллскрина).
List<DeviceOrientation> allowedOrientationsForCurrentView() {
  final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  final size =
      view == null ? Size.zero : view.physicalSize / view.devicePixelRatio;
  return allowedOrientationsForSize(size);
}

/// Реактивно удерживает политику ориентаций по размеру экрана: телефон —
/// только портрет, планшет — поворот вслед за устройством. На desktop/web —
/// passthrough (ориентацией там управляет ОС/окно).
///
/// `shortestSide` орт-независим, поэтому при повороте классификация
/// "телефон/планшет" не меняется и не дёргает `setPreferredOrientations`.
/// Ловит и split-screen/трансформеры через изменение `MediaQuery`.
class AdaptiveOrientation extends StatefulWidget {
  final Widget child;

  const AdaptiveOrientation({super.key, required this.child});

  @override
  State<AdaptiveOrientation> createState() => _AdaptiveOrientationState();
}

class _AdaptiveOrientationState extends State<AdaptiveOrientation> {
  List<DeviceOrientation>? _applied;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!PlatformInfos.isMobile) return;
    final next = allowedOrientationsForSize(MediaQuery.sizeOf(context));
    if (listEquals(next, _applied)) return;
    _applied = next;
    SystemChrome.setPreferredOrientations(next);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
