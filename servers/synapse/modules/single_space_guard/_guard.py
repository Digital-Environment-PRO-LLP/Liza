"""Pure predicates for single_space_guard. No synapse imports - testable standalone."""

SPACE_TYPE = "m.space"
SPACE_PARENT_EVENT = "m.space.parent"
MEMBER_EVENT = "m.room.member"
PROTECTED_MEMBERSHIPS = ("leave", "ban")


def is_root_space_creation(config: dict) -> bool:
    """True если createRoom-конфиг создаёт пространство 1-го уровня (root-space).

    root-space = space без указания родителя в initial_state.
    """
    creation_content = config.get("creation_content") or {}
    if creation_content.get("type") != SPACE_TYPE:
        return False
    initial_state = config.get("initial_state") or []
    has_parent = any(
        ev.get("type") == SPACE_PARENT_EVENT for ev in initial_state
    )
    return not has_parent


def is_dm_creation(config: dict) -> bool:
    """True если createRoom-конфиг создаёт direct-чат (DM).

    Клиент шлёт is_direct=True при создании DM (startDirectChat). Признак
    доступен в on_create_room ДО создания комнаты; m.direct/is_direct в
    state-событиях появляются позже.
    """
    return bool(config.get("is_direct"))


def is_protected_membership_change(
    *,
    event_type: str,
    membership,
    room_id: str,
    main_root_space_id,
) -> bool:
    """True если событие - выход/бан из главного пространства (надо запретить)."""
    if main_root_space_id is None:
        return False
    if event_type != MEMBER_EVENT:
        return False
    if membership not in PROTECTED_MEMBERSHIPS:
        return False
    return room_id == main_root_space_id


def is_space_chunk(chunk: dict) -> bool:
    """True если элемент publicRooms-выдачи — пространство (m.space)."""
    return chunk.get("room_type") == SPACE_TYPE


def is_auto_add_candidate(
    *,
    room_type: str | None,
    is_direct: bool,
    has_space_parent: bool,
    is_local: bool,
) -> bool:
    """True если комнату надо авто-добавить в компанию.

    Кандидат: локальная (на этом homeserver) группа — не space, не DM, и ещё
    не вложена ни в одно пространство (нет m.space.parent / не child).
    """
    if not is_local:
        return False
    if room_type == SPACE_TYPE:
        return False
    if is_direct:
        return False
    if has_space_parent:
        return False
    return True


def is_local_room(room_id: str, server_name: str) -> bool:
    """True если комната зарождена на этом homeserver.

    room_id имеет вид !localpart:origin_server, где origin_server - homeserver,
    на котором комната создана (неизменен). Ведущий ":" в суффиксе отсекает
    ложные совпадения по поддомену.
    """
    return bool(room_id) and room_id.endswith(":" + server_name)


# Все unicode-варианты дефиса/тире, которые надо считать одним символом:
# -(U+002D) ‑(U+2011) –(U+2013) —(U+2014) −(U+2212).
_DASHES = "-‑–—−"
_DASH_TABLE = {ord(d): "-" for d in _DASHES}


def _normalize(text: str) -> str:
    """casefold + унификация тире + схлопывание пробелов. Для сравнения имён."""
    text = text.translate(_DASH_TABLE)
    text = " ".join(text.split())
    return text.casefold()


def matches_query(name: str | None, query: str | None) -> bool:
    """True если имя компании содержит query.

    Сравнение регистро- и тире-независимое (casefold + унификация дефисов),
    пробелы схлопываются. Пустой/None query совпадает со всеми. None name
    совпадает только с пустым query.
    """
    if not query:
        return True
    if not name:
        return False
    return _normalize(query) in _normalize(name)


def deduplicate_companies(companies: list[dict]) -> list[dict]:
    """Дедупликация списка компаний по room_id, порядок сохраняется."""
    seen: set[str] = set()
    result: list[dict] = []
    for c in companies:
        rid = c.get("room_id")
        if rid is None or rid in seen:
            continue
        seen.add(rid)
        result.append(c)
    return result
