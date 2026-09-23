#
# Liza (форк Synapse): read-grace для HTTP-пушей — чистая логика.
#
# Запрос Саши Н. (2026-09-17): «в тг и максе пуши не приходят, если ты сообщение
# получаешь в активном чате и сразу его увидел». Synapse отправляет пуш в момент
# события, квитанция с другого устройства приходит позже — поэтому телефон
# получает пуш о том, что уже прочитано на Маке. Grace: пушер выжидает
# `push.read_grace_ms` от `origin_server_ts` события и перед отправкой
# перепроверяет квитанцию пользователя в комнате.
#
# Модуль намеренно без импортов ядра Synapse: он гоняется обычным pytest в
# `make test-push-monitoring` (trial-тесты ядра локально недоступны).
#


def read_grace_deadline_ms(origin_server_ts: int, grace_ms: int) -> int:
    """Момент, до которого пушер ждёт перед перепроверкой квитанции.

    Якорь — время СОБЫТИЯ, а не «сейчас» (та же логика, что у `jitter_delay`):
    при догоняющей обработке пачки старые события не суммируют задержку, а
    для уже «остывших» (deadline в прошлом) сна нет вовсе.
    """
    return origin_server_ts + grace_ms


def is_read_within_grace(
    receipt_event_stream_ordering: int | None,
    action_stream_ordering: int,
) -> bool:
    """Прочитано ли событие пуша: последняя unthreaded-квитанция пользователя
    (`m.read` или `m.read.private`) стоит на этом событии или новее.

    `None` (квитанции нет) — НЕ прочитано: пуш уходит. `m.fully_read` сюда не
    входит — это account data, не квитанция.
    """
    if receipt_event_stream_ordering is None:
        return False
    return receipt_event_stream_ordering >= action_stream_ordering
