import 'dart:async';
import 'dart:typed_data';

/// Вычитывает тело HTTP-ответа с **idle-таймаутом**: терминал наступает, только
/// если между двумя чанками прошло больше [idleTimeout].
///
/// Почему idle, а не общий дедлайн на всю загрузку: видео бывает 161 МБ, и на
/// мобильном канале честная докачка идёт минутами — wall-clock таймаут либо
/// зарубит живую загрузку, либо (если сделать его достаточно большим) окажется
/// бесполезен против «вечного спиннера». Проект уже обжигался на агрессивном
/// пороге: watchdog по `pos<500ms` без проверки буфера рубил медленный, но
/// живой стрим. Действующая формула медиа-терминалов — `StalledReconnectDetector`
/// и resume E2EE-прокси — считает ПРОГРЕСС, а не часы; здесь та же семантика.
///
/// `Stream.timeout` перезапускает счётчик на каждом событии, поэтому размер
/// файла на порог не влияет: чтобы 64-КБ чанк не пришёл за минуту, канал должен
/// упасть ниже ~9 кбит/с — это «мертво», а не «медленно».
///
/// [onChunk] получает накопленное число байт (для индикатора прогресса).
Future<Uint8List> readBytesWithIdleTimeout(
  Stream<List<int>> stream, {
  required Duration idleTimeout,
  void Function(int received)? onChunk,
}) async {
  // BytesBuilder(copy:false) хранит ССЫЛКИ на чанки и склеивает один раз —
  // на 161 МБ это срезает пиковую кучу вдвое против растущего List<int>.
  final builder = BytesBuilder(copy: false);
  var received = 0;
  await for (final chunk in stream.timeout(
    idleTimeout,
    onTimeout: (sink) => sink.addError(
      TimeoutException(
        'media stream idle > ${idleTimeout.inSeconds}s '
        '(received $received bytes)',
      ),
    ),
  )) {
    builder.add(chunk);
    received += chunk.length;
    onChunk?.call(received);
  }
  return builder.toBytes();
}
