#
# Liza (форк Synapse): когда слать counts-only пуш «почисти шторку» — чистая логика.
#
# Запрос (Надежда Р. за Сашу Н., 2026-09-24): прочитал на одном устройстве — на
# другом уведомление висит в шторке. Counts-only пуш на свою квитанцию Sygnal
# превращает в тихий background-пуш, по которому клиент снимает прочитанные
# чаты (howItWoks/pushes.md §21). Штатно Synapse шлёт его только при смене
# ЧИСЛА непрочитанных чатов: «X прочитан, в тот же момент пришло в Y» число не
# меняет — и баннер X висит. Флаг `push.clearing_on_room_read` добавляет
# триггер «из множества непрочитанных пропал чат».
#
# Модуль намеренно без импортов ядра Synapse: гоняется обычным pytest в
# `make test-push-monitoring` (trial-тесты ядра локально недоступны).
#
from collections.abc import Mapping, Set


def badge_from_unread(
    invites: Set[str], counts: Mapping[str, int], group_by_room: bool
) -> int:
    """Бейдж из уже собранных непрочитанных: приглашения + чаты с notify>0
    (по одному на чат либо суммой уведомлений)."""
    if group_by_room:
        return len(invites) + len(counts)
    return len(invites) + sum(counts.values())


def unread_room_ids(invites: Set[str], counts: Mapping[str, int]) -> frozenset[str]:
    return frozenset(invites) | frozenset(counts)


def should_send_badge(
    previous_badge: int | None,
    badge: int,
    previous_rooms: frozenset[str] | None,
    rooms: frozenset[str],
    clearing_on_room_read: bool,
) -> bool:
    """Слать ли counts-only пуш после квитанции.

    Число изменилось — как в апстриме. При флаге — ещё и когда хотя бы один
    чат перестал быть непрочитанным. Частичное прочтение (множество то же)
    пуша не даёт: баннеры сгруппированы по чату, недочитанный снимать нельзя.
    """
    if previous_badge is None or previous_badge != badge:
        return True
    if not clearing_on_room_read or previous_rooms is None:
        return False
    return not previous_rooms <= rooms
