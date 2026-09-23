import 'package:matrix/matrix.dart';

import 'package:liza/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';

/// LABA-1898: догрузка истории, когда видимая лента чата пуста, но комната
/// содержит сообщение(я).
///
/// Симптом: пользователь A создаёт чат, приглашает B и СРАЗУ пишет сообщение
/// `m1`. B принимает приглашение (join). Инвайт→join приходит limited-sync'ом →
/// SDK вычищает локальную ленту (`deleteTimelineForRoom`) и восстанавливает
/// ТОЛЬКО превью `room.lastEvent` отдельным серверным `/messages`-запросом
/// (`refreshLastEvent`). Само `m1` остаётся за `prev_batch`-гэпом и в локальный
/// таймлайн не попадает: в списке чатов превью есть, а в открытом чате — пусто.
///
/// Решение: при открытии чата с пустой видимой лентой, но реальным (не
/// заглушкой) `lastEvent`, разово (с потолком батчей [maxBatches]) дотягиваем
/// историю через `timeline.requestHistory()` — симметрично серверной докачке
/// превью. Сервер отдаёт `m1` по `history_visibility=shared`.
///
/// Возвращает число сделанных батчей догрузки (0 — если догрузка не требовалась
/// или невозможна). Логику гейтов держим здесь (не в виджете), чтобы покрыть
/// стражем на РЕАЛЬНОМ `Timeline`. Дизайн:
/// docs/superpowers/specs/2026-08-18-post-join-empty-timeline-backfill-design.md
///
/// [threadId] — активный тред (фильтр видимости, как в остальном коде чата).
/// [isMounted] — жив ли виджет-владелец; проверяется после каждого сетевого
/// `await`, чтобы не продолжать работу на размонтированном экране.
/// [maxBatches] — жёсткая граница против цикла и защита от «в батче только
/// state-события». [historyCount] — размер батча пагинации.
Future<int> backfillEmptyTimelineAfterJoin(
  Timeline timeline, {
  String? threadId,
  required bool Function() isMounted,
  int maxBatches = 3,
  int historyCount = 100,
  Duration timeout = const Duration(seconds: 30),
}) async {
  bool visibleEmpty() =>
      timeline.events.filterByVisibleInGui(threadId: threadId).isEmpty;

  bool hasRealLastEvent() {
    final last = timeline.room.lastEvent;
    // Пока асинхронный refreshLastEvent крутится, lastEvent — фейк-заглушка типа
    // com.famedly.refreshing_last_event: без этой проверки гейт «lastEvent!=null»
    // ложно прошёл бы, а реального сообщения ещё нет.
    return last != null && last.type != EventTypes.refreshingLastEvent;
  }

  if (!visibleEmpty() || !hasRealLastEvent()) return 0;

  if (!timeline.canRequestHistory) {
    // KL-3: лента пуста, до-join сообщение видно в превью, но пагинировать нечем
    // (prev_batch==null / только RoomCreate) — редкий edge, не подтянуть.
    Logs().v(
      'LABA-1898: empty timeline, cannot backfill (canRequestHistory=false)',
      timeline.room.id,
    );
    return 0;
  }

  var batches = 0;
  while (visibleEmpty() &&
      hasRealLastEvent() &&
      timeline.canRequestHistory &&
      batches < maxBatches) {
    batches++;
    try {
      await timeline
          .requestHistory(historyCount: historyCount)
          .timeout(timeout);
    } catch (e, s) {
      // Сетевой сбой догрузки не должен рушить открытие чата — логируем и
      // выходим, не пробрасывая исключение наверх.
      Logs().w('LABA-1898: post-join timeline backfill failed', e, s);
      break;
    }
    if (!isMounted()) return batches;
  }

  // E2EE best-effort: догруженная история могла принести зашифрованные события,
  // ключи для которых ещё не запрашивались. Не блокер — для дефолтных
  // нешифрованных чатов Liza это no-op.
  if (batches > 0) timeline.requestKeys(onlineKeyBackupOnly: false);

  return batches;
}
