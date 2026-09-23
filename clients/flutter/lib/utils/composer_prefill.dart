import 'package:flutter/foundation.dart';

/// Мост «карточка → поле ввода»: интерактивная карточка (напр. «Изменить» в
/// службе поддержки) кладёт сюда, какой текст предзаполнить в композере какой
/// комнаты. Активный [ChatController] слушает и, если совпала его комната,
/// подставляет текст в `sendController` и сбрасывает значение.
///
/// Событие-виджеты таймлайна не имеют прямого доступа к `ChatController`
/// (он — State, не InheritedWidget), поэтому связываемся через этот notifier.
typedef ComposerPrefillRequest = ({String roomId, String text});

final ValueNotifier<ComposerPrefillRequest?> composerPrefill =
    ValueNotifier<ComposerPrefillRequest?>(null);
