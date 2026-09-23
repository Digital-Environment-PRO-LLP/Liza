"""knock_notify: чистая логика выбора получателей пуша о заявке (knock).

Тестируется без реального Synapse (unittest + asyncio, как channel_sync).
"""

from typing import Any, Callable, Iterable

MEMBER_EVENT_TYPE = "m.room.member"
POWER_LEVELS_TYPE = "m.room.power_levels"
ROOM_NAME_TYPE = "m.room.name"

# Порог «может рассматривать заявки» = модератор (PL 50). Совпадает с клиентским
# гейтом бейджа (moderatorPowerLevel=50, chat_topology.dart) и семантикой
# canReviewKnockRequests. Через invite-порог гейтить НЕЛЬЗЯ: у компании (space)
# invite:0 по умолчанию → пуш о заявке утёк бы ВСЕМ участникам (находка
# flutter-critic). PL>=50 к тому же на практике означает право invite (invite-
# порог в группах/компаниях Liza ≤ 50), т.е. получатель реально может одобрить.
MODERATOR_POWER_LEVEL = 50


def is_knock_membership(event_type: Any, content: dict | None) -> bool:
    """True для m.room.member с membership=knock (заявка на вступление)."""
    return (
        event_type == MEMBER_EVENT_TYPE
        and (content or {}).get("membership") == "knock"
    )


def user_power_level(user_id: str, power_levels_content: dict | None) -> int:
    """PL пользователя из m.room.power_levels: users[user] или users_default."""
    pl = power_levels_content or {}
    users = pl.get("users")
    if isinstance(users, dict) and user_id in users:
        try:
            return int(users[user_id])
        except (TypeError, ValueError):
            pass
    try:
        return int(pl.get("users_default", 0))
    except (TypeError, ValueError):
        return 0


def knock_reviewers(
    members: Iterable[tuple[str, str]],
    power_levels_content: dict | None,
    knocker: str | None,
    is_local: Callable[[str], bool],
    min_level: int = MODERATOR_POWER_LEVEL,
) -> list[str]:
    """Локальные joined-участники с PL>=min_level, кроме самого стучащегося.

    members: iterable из (user_id, membership).
    is_local: callable(user_id)->bool — обслуживаем только своих; каждый инстанс
        достучится до СВОИХ локальных ревьюеров, дублей между инстансами нет.
    Сам knocker исключён: о своём действии пуш не шлём.
    """
    result: set[str] = set()
    for user_id, membership in members:
        if membership != "join":
            continue
        if knocker is not None and user_id == knocker:
            continue
        if not is_local(user_id):
            continue
        if user_power_level(user_id, power_levels_content) >= min_level:
            result.add(user_id)
    return sorted(result)


def build_push_content(
    event: Any,
    sender_display_name: str | None = None,
    room_name: str | None = None,
) -> dict:
    """notification-payload для send_http_push_notification.

    Текст «постучался» клиент рендерит по event_id (calcLocalizedBodyFallback →
    hasKnocked). Кладём event_id/room_id/type/sender/membership + читаемые имена,
    prio=high (membership не звенит по дефолту — поднимаем, чтобы iOS NSE/Android
    доставили). `counts` НАМЕРЕННО не трогаем: доставка идёт мимо
    event_push_actions, notification_count/бейдж не инфлируется.
    """
    content: dict = {
        "event_id": getattr(event, "event_id", None),
        "room_id": getattr(event, "room_id", None),
        "type": MEMBER_EVENT_TYPE,
        "sender": getattr(event, "sender", None),
        "membership": "knock",
        "prio": "high",
    }
    if sender_display_name:
        content["sender_display_name"] = sender_display_name
    if room_name:
        content["room_name"] = room_name
    return content
