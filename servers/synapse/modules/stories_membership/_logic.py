"""Чистые предикаты модуля stories_membership (без зависимости от HomeServer)."""

STORIES_TAG = "com.liza.stories"
STORY_CONTENT_KEY = "com.liza.story"
# Легаси-имя, которое получали все сторис-комнаты до уникализации (2026-07-04).
# Используется для идемпотентного поиска ещё не переименованных комнат.
LEGACY_STORIES_ROOM_NAME = "Stories"
STORIES_ROOM_NAME_PREFIX = "Stories - "

# LABA-1970: override-правило пуша на публикацию сторис. Живёт РЯДОМ с
# room-level dont_notify (см. _mute_room_for_local_user): override (класс 5)
# перекрывает room-level dont_notify (класс 3), поэтому стори-событие
# уведомляет, а служебные события скрытой комнаты остаются заглушёнными.
# Матч по type+room_id (не по com.liza.story): rust-эвалюатор форка матчит
# event_match только по строковым листьям, а com.liza.story — объект. В скрытую
# сторис-комнату публикуется только сторис как m.room.message (реакции/чистка/
# членство — другого типа, реплай уходит в DM) → ложных срабатываний нет.
#
# ФОРМАТ rule_id: full = "global/override/" + NAME, где NAME — ОДИН path-сегмент
# (без "/"), т.к. клиентский setPushRuleEnabled шлёт PUT
# pushrules/global/override/{NAME}/enabled (NAME — единственный сегмент). Тот же
# инвариант у room-mute ("global/room/{room_id}"). room_id содержит ':'/'!'/'.'
# — всё это допустимо в одном сегменте, слэшей в room_id нет. Разделитель — ТОЧКА
# (не слэш!), иначе URL распадётся на лишние сегменты и клиент не найдёт правило.
STORY_NOTIFY_RULE_NAME_PREFIX = "com.liza.story_notify."


def story_notify_rule_name(room_id: str) -> str:
    """Имя (единственный path-сегмент) override-правила — то, что клиент шлёт в
    setPushRuleEnabled(PushRuleKind.override, <name>). Клиент строит его сам по
    тому же формату — обе стороны обязаны совпадать."""
    return f"{STORY_NOTIFY_RULE_NAME_PREFIX}{room_id}"


def story_notify_rule_id(room_id: str) -> str:
    """Полный rule_id для add_push_rule / проверки существования на сервере."""
    return f"global/override/{story_notify_rule_name(room_id)}"


def is_local_room(room_id: str, server_name: str) -> bool:
    """True, если комната зарождена на данном homeserver.

    Проверяет суффикс room_id: '!xxx:server_name'. Литеральное сравнение
    через split безопаснее SQL LIKE (LIKE '%' ломается на Postgres через Synapse).
    """
    try:
        _, host = room_id.split(":", 1)
    except ValueError:
        return False
    return host == server_name


def dm_pairs_from_direct(
    owner: str, direct_content: dict
) -> list[tuple[str, str]]:
    """Извлечь нормализованные пары (a, b) из m.direct account_data.

    direct_content вида {other_user_id: [room_id, ...]}. Для каждого
    other_user_id возвращает ровно одну пару (отсортированную, чтобы
    (alice, bob) и (bob, alice) совпадали). Дублей нет.

    Аргументы:
        owner: Matrix ID владельца account_data.
        direct_content: распарсенный JSON контент ключа m.direct.
    """
    seen: set[tuple[str, str]] = set()
    for other in direct_content:
        if not isinstance(other, str):
            continue
        pair = tuple(sorted((owner, other)))
        seen.add(pair)  # type: ignore[arg-type]
    return list(seen)


def is_direct_membership_join(
    event_type: str, content: dict, is_direct_room: bool
) -> bool:
    """True, если событие - join в личную (DM) комнату."""
    if event_type != "m.room.member":
        return False
    if not is_direct_room:
        return False
    return content.get("membership") == "join"


def is_direct_membership_leave(
    event_type: str, content: dict, is_direct_room: bool
) -> bool:
    """True, если событие - выход/удаление из личной (DM) комнаты.

    LABA-1970, AC-7: при удалении DM зритель должен перестать получать пуши и
    видеть сторисы контакта. leave (сам вышел / удалил чат) и ban (кикнули)
    трактуем одинаково — оба снимают подписку на сторисы встречной стороны.
    Архив (клиентский тег m.direct/топология) сюда НЕ попадает — его не видно
    в membership, его гасит клиент.
    """
    if event_type != "m.room.member":
        return False
    if not is_direct_room:
        return False
    return content.get("membership") in ("leave", "ban")


def server_name_of(user_id: str) -> str:
    """Имя сервера из Matrix ID: '@bob:host' -> 'host'."""
    return user_id.split(":", 1)[1]


def is_local_user(user_id: str, server_name: str) -> bool:
    """True, если юзер зарегистрирован на данном homeserver.

    Сравнивает домен из Matrix ID с server_name. Используется в backfill вместо
    is_local_room: для кросс-федеративного DM комната лежит на ОДНОМ из серверов,
    но подписать на сторисы надо ЛОКАЛЬНОГО участника независимо от того, чей
    сервер владеет комнатой.
    """
    parts = user_id.split(":", 1)
    return len(parts) == 2 and parts[1] == server_name


def localpart_of(user_id: str) -> str:
    """Localpart из Matrix ID: '@bob:host' -> 'bob'."""
    return user_id.split(":", 1)[0].lstrip("@")


def is_reachable_server(
    user_id: str, server_name: str, whitelist: dict | None
) -> bool:
    """True, если к серверу юзера вообще имеет смысл ходить по федерации.

    Свой сервер — всегда True. Для чужих: если federation_domain_whitelist
    задан, сервер обязан быть в нём. Иначе (whitelist не настроен) считаем
    достижимыми всех — поведение Synapse по умолчанию.

    Зачем: погашенный инстанс, убранный из whitelist, остаётся в старом
    account_data (m.direct) и в membership-событиях. Без этой проверки
    backfill дёргает его профили при каждом старте и ловит таймауты
    (инцидент 2026-07-24: dev.liza.laba.prodamus.tech).
    """
    try:
        host = server_name_of(user_id)
    except IndexError:
        return False
    if host == server_name:
        return True
    if whitelist is None:
        return True
    return host in whitelist


def stories_room_name(owner_user_id: str) -> str:
    """Имя сторис-комнаты владельца: уникально по localpart, не по чистому

    'Stories' (было до 2026-07-04) - иначе все сторис-комнаты неразличимы
    в админке/логах. UI не читает room.name (см. storyOwnerOf), поэтому
    формат ориентирован на диагностику, не на конечного пользователя.
    """
    return f"{STORIES_ROOM_NAME_PREFIX}{localpart_of(owner_user_id)}"


def story_is_expired(event_content: dict, now_ms: int) -> bool:
    """True, если сторис протух (expires_ts < now). Не сторис -> False."""
    story = event_content.get(STORY_CONTENT_KEY)
    if not isinstance(story, dict):
        return False
    expires = story.get("expires_ts")
    if not isinstance(expires, int):
        return False
    return expires < now_ms


def is_hidden_room(
    create_content: dict | None, topology_content: dict | None
) -> bool:
    """True, если комната скрыта по топологии чатов (com.liza.chat.topology) -
    универсальный предикат, НЕ завязанный на конкретный тип "stories".

    Зеркалит HiddenRoomsLookup.get_hidden_room_ids_for_user
    (chat_topology_sync_gate/_storage.py) - обе стороны должны совпадать,
    иначе push-мьют и sync-gate разойдутся в том, что считают скрытым.

    Приоритет: явный com.liza.chat.topology.hidden, если state event есть.
    При его отсутствии - legacy-дефолт по типу комнаты (com.liza.stories
    или com.liza.chat.type == 'stories' считаются hidden по умолчанию, пока
    бэкфилл topology-состояния не дошёл до комнаты).
    """
    if topology_content is not None:
        return topology_content.get("hidden") is True

    if create_content is None:
        return False
    return bool(
        create_content.get(STORIES_TAG) is True
        or create_content.get("com.liza.chat.type") == "stories"
    )
