import 'dart:async';
import 'dart:typed_data';

import 'package:liza/utils/foreground_witness.dart';

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
/// Счётчик перезапускается на каждом чанке, поэтому размер
/// файла на порог не влияет: чтобы 64-КБ чанк не пришёл за минуту, канал должен
/// упасть ниже ~9 кбит/с — это «мертво», а не «медленно».
///
/// [onChunk] получает накопленное число байт (для индикатора прогресса).
///
/// [witness] (mobile) делает порог временем ОТКРЫТОГО приложения: истёкший
/// отсчёт, пока процесс заморожен ОС, не терминалит, а на возврате в
/// foreground отсчёт начинается заново. Иначе сон процесса (минуты в фоне)
/// выдавался за «мёртвый канал» — ложный `swap-failed` #2064. Честная тишина
/// ПОСЛЕ возврата по-прежнему даёт [TimeoutException].
Future<Uint8List> readBytesWithIdleTimeout(
  Stream<List<int>> stream, {
  required Duration idleTimeout,
  void Function(int received)? onChunk,
  ForegroundWitness? witness,
}) {
  // BytesBuilder(copy:false) хранит ССЫЛКИ на чанки и склеивает один раз —
  // на 161 МБ это срезает пиковую кучу вдвое против растущего List<int>.
  final builder = BytesBuilder(copy: false);
  final done = Completer<Uint8List>();
  var received = 0;
  Timer? idle;
  StreamSubscription<void>? resumeSub;
  late final StreamSubscription<List<int>> sub;

  void finish() {
    idle?.cancel();
    unawaited(resumeSub?.cancel());
  }

  void arm() {
    idle?.cancel();
    idle = Timer(idleTimeout, () {
      if (witness?.suspended ?? false) {
        arm(); // сон процесса — не простой канала; счёт заново на возврате
        return;
      }
      finish();
      unawaited(sub.cancel());
      if (!done.isCompleted) {
        done.completeError(
          TimeoutException(
            'media stream idle > ${idleTimeout.inSeconds}s '
            '(received $received bytes)',
          ),
        );
      }
    });
  }

  resumeSub = witness?.onResume.listen((_) {
    if (!done.isCompleted) arm();
  });
  sub = stream.listen(
    (chunk) {
      builder.add(chunk);
      received += chunk.length;
      onChunk?.call(received);
      arm();
    },
    onError: (Object e, StackTrace s) {
      finish(); // подписку снимает cancelOnError
      if (!done.isCompleted) done.completeError(e, s);
    },
    onDone: () {
      finish();
      if (!done.isCompleted) done.complete(builder.toBytes());
    },
    cancelOnError: true,
  );
  arm();
  return done.future;
}
