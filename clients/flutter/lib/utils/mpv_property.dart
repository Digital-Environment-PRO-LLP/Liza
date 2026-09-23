// Тонкая обёртка над тюнингом libmpv-свойств плеера media_kit.
//
// На нативных платформах применяет свойство к `NativePlayer`; на Web,
// где бэкенда libmpv нет, — no-op. Conditional import нужен, чтобы
// web-сборка не ссылалась статически на `NativePlayer.setProperty`,
// которого в web-варианте media_kit не существует (иначе падает
// компиляция Dart→JS).
export 'mpv_property_web.dart'
    if (dart.library.io) 'mpv_property_native.dart';
