"""Участники поддерева пространства.

Список участников компании — это не members корневой space-комнаты:
человек может состоять в дочернем чате, не вступая в саму компанию.
Собираем объединение по всему поддереву m.space.child.

Чистая логика (без Synapse-импортов) — как и _logic.py, чтобы тесты
не требовали установленного Synapse.
"""

import json
import logging

from ._logic import (
    CHAT_TYPE_KEY,
    LEGACY_STORIES_KEY,
    MODERATOR_POWER_LEVEL,
    classify_room,
    power_from_content,
)

logger = logging.getLogger(__name__)

MAX_SPACE_DEPTH = 10
# Верхний предел числа комнат в поддереве. Без него корректно
# дедуплицированное, но широкое пространство всё равно упирается в лимит
# bind-параметров Postgres (65535) при подстановке в IN(...) — обрезаем,
# а не роняем запрос 500-й (Critical, ревью Task 6 round 1).
MAX_SPACE_ROOMS = 1000


def _child_edges_sql(count: int) -> str:
    """SQL рёбер иерархии для count комнат.

    Плейсхолдеры генерируются под размер списка: `= ANY(?)` работает
    только в Postgres, а тесты гоняют запрос на SQLite (проверено —
    `no such function: ANY`). `IN (?, ?, ...)` портативен для обоих.

    ej.json джойним, чтобы отфильтровать ОТОЗВАННЫЕ рёбра: по спеке
    Matrix ребёнок space убирается из иерархии не удалением события, а
    очисткой content (нет ``via``) — событие остаётся в
    current_state_events. Без фильтра выведенный из компании чат
    навсегда тянет своих участников в список (Important, ревью round 1).
    """
    placeholders = ", ".join("?" * count)
    return f"""
    SELECT cse.room_id, cse.state_key, ej.json
    FROM current_state_events AS cse
    LEFT JOIN event_json AS ej ON ej.event_id = cse.event_id
    WHERE cse.type = 'm.space.child'
      AND cse.room_id IN ({placeholders})
"""


def _member_rows_sql(count: int) -> str:
    """Участники комнат. content не нужен — PL считаем отдельно по

    power_levels-событию комнаты (_power_levels_sql), не по m.room.member —
    поэтому джойн event_json здесь лишний (Minor, ревью round 1)."""
    placeholders = ", ".join("?" * count)
    return f"""
    SELECT cse.room_id, cse.state_key
    FROM current_state_events AS cse
    WHERE cse.type = 'm.room.member'
      AND cse.membership = 'join'
      AND cse.room_id IN ({placeholders})
"""


def _power_levels_sql(count: int) -> str:
    """power_levels-события каждой комнаты — по одному на комнату."""
    placeholders = ", ".join("?" * count)
    return f"""
    SELECT pl.room_id, ej.json
    FROM current_state_events AS pl
    LEFT JOIN event_json AS ej ON ej.event_id = pl.event_id
    WHERE pl.type = 'm.room.power_levels'
      AND pl.state_key = ''
      AND pl.room_id IN ({placeholders})
"""


def _room_meta_sql(count: int) -> str:
    """Имя и тип комнаты (для group/name в ответе) — room_stats_state."""
    placeholders = ", ".join("?" * count)
    return f"""
    SELECT rss.room_id, rss.name, rss.room_type
    FROM room_stats_state AS rss
    WHERE rss.room_id IN ({placeholders})
"""


def _room_create_sql(count: int) -> str:
    """content события m.room.create — источник com.liza.chat.type и

    com.liza.stories (легаси-ключ). Без этого classify_room всегда видит
    chat_type=None и служебные комнаты (сторисы, обсуждения каналов)
    попадают в поддерево как обычные chat — та же логика, что и в
    _dossier.py::build_dossier_groups (Important, ревью round 1)."""
    placeholders = ", ".join("?" * count)
    return f"""
    SELECT cr.room_id, ej.json
    FROM current_state_events AS cr
    LEFT JOIN event_json AS ej ON ej.event_id = cr.event_id
    WHERE cr.type = 'm.room.create'
      AND cr.state_key = ''
      AND cr.room_id IN ({placeholders})
"""


def _content_from_json(raw: str | None) -> dict | None:
    if not raw:
        return None
    try:
        parsed = json.loads(raw)
    except (ValueError, TypeError):
        return None
    content = parsed.get("content") if isinstance(parsed, dict) else None
    return content if isinstance(content, dict) else None


def collect_space_room_ids(
    child_edges: dict, root_id: str, max_depth: int = MAX_SPACE_DEPTH
) -> list[str]:
    """Комнаты поддерева, включая корень.

    child_edges: {room_id: [child_room_id, ...]}. Обход в ширину с
    множеством посещённых — иерархия пространств в Matrix может
    содержать циклы (A → B → A), и без защиты обход не завершится.
    """
    seen = {root_id}
    order = [root_id]
    frontier = [root_id]
    depth = 0

    while frontier and depth < max_depth:
        next_frontier = []
        for room_id in frontier:
            for child_id in child_edges.get(room_id, ()):
                if child_id in seen:
                    continue
                seen.add(child_id)
                order.append(child_id)
                next_frontier.append(child_id)
        frontier = next_frontier
        depth += 1

    return order


def build_space_members(
    member_rows, *, root_id: str, room_names: dict, room_groups: dict
) -> list[dict]:
    """Список участников поддерева.

    member_rows: (room_id, user_id, power_level).
    """
    by_user: dict[str, dict] = {}

    for room_id, user_id, power_level in member_rows:
        entry = by_user.setdefault(
            user_id,
            {
                "user_id": user_id,
                "membership_in_space": None,
                "max_power_level": 0,
                "elevated_rooms": [],
            },
        )
        if room_id == root_id:
            entry["membership_in_space"] = "join"
        if power_level > entry["max_power_level"]:
            entry["max_power_level"] = power_level
        if power_level >= MODERATOR_POWER_LEVEL:
            entry["elevated_rooms"].append(
                {
                    "room_id": room_id,
                    "name": room_names.get(room_id),
                    "power_level": power_level,
                    "group": room_groups.get(room_id, "chat"),
                }
            )

    for entry in by_user.values():
        entry["elevated_rooms"].sort(
            key=lambda r: (
                -r["power_level"],
                r["name"] is None,
                r["name"] or "",
            )
        )

    return sorted(
        by_user.values(),
        key=lambda m: (-m["max_power_level"], m["user_id"]),
    )


class SpaceMembersBuilder:
    """Загрузка поддерева пространства из БД и сборка ответа.

    Раскрытие иерархии — послойное (BFS): дети следующего уровня известны
    только после запроса по текущему фронту, поэтому collect() не может
    сделать один SQL — минимум по одному на уровень глубины, максимум
    MAX_SPACE_DEPTH запросов.
    """

    def __init__(self, db_pool) -> None:
        self._db = db_pool

    async def _child_edges(self, room_ids: list[str]) -> dict:
        if not room_ids:
            return {}

        def _txn(txn):
            txn.execute(_child_edges_sql(len(room_ids)), tuple(room_ids))
            return txn.fetchall()

        rows = await self._db.runInteraction("access_admin_space_children", _txn)
        edges: dict[str, list] = {}
        for parent_id, child_id, content_raw in rows:
            content = _content_from_json(content_raw)
            # Отозванное ребро — событие m.space.child с пустым content
            # (нет via), остающееся в current_state_events. Пропускаем.
            via = content.get("via") if isinstance(content, dict) else None
            if not via:
                continue
            edges.setdefault(parent_id, []).append(child_id)
        return edges

    async def _fetch_members(self, room_ids: list[str]):
        if not room_ids:
            return [], {}, {}

        def _members_txn(txn):
            txn.execute(_member_rows_sql(len(room_ids)), tuple(room_ids))
            return txn.fetchall()

        def _powers_txn(txn):
            txn.execute(_power_levels_sql(len(room_ids)), tuple(room_ids))
            return txn.fetchall()

        def _meta_txn(txn):
            txn.execute(_room_meta_sql(len(room_ids)), tuple(room_ids))
            return txn.fetchall()

        def _create_txn(txn):
            txn.execute(_room_create_sql(len(room_ids)), tuple(room_ids))
            return txn.fetchall()

        member_rows = await self._db.runInteraction(
            "access_admin_space_member_rows", _members_txn
        )
        power_rows = await self._db.runInteraction(
            "access_admin_space_power_levels", _powers_txn
        )
        meta_rows = await self._db.runInteraction(
            "access_admin_space_room_meta", _meta_txn
        )
        create_rows = await self._db.runInteraction(
            "access_admin_space_room_create", _create_txn
        )

        power_content_by_room = {
            room_id: _content_from_json(raw) for room_id, raw in power_rows
        }
        create_content_by_room = {
            room_id: _content_from_json(raw) or {} for room_id, raw in create_rows
        }
        names = {room_id: name for room_id, name, _room_type in meta_rows}

        # Служебные комнаты (сторисы, обсуждения каналов) не должны попасть
        # в поддерево вовсе — classify_room возвращает None специально
        # затем, чтобы такую комнату не показывать (см. _dossier.py). Без
        # ЭТОЙ проверки chat_type подставлялся как None безусловно, и
        # `or "chat"` превращал сигнал "скрыть" в валидную группу
        # (Important, ревью round 1).
        groups: dict[str, str] = {}
        for room_id, _name, room_type in meta_rows:
            create_content = create_content_by_room.get(room_id, {})
            chat_type = create_content.get(CHAT_TYPE_KEY)
            legacy_stories = create_content.get(LEGACY_STORIES_KEY) is True
            group = classify_room(room_type, chat_type, legacy_stories=legacy_stories)
            if group is not None:
                groups[room_id] = group

        rows = [
            (
                room_id,
                user_id,
                power_from_content(power_content_by_room.get(room_id), user_id),
            )
            for room_id, user_id in member_rows
            if room_id in groups
        ]
        names = {room_id: name for room_id, name in names.items() if room_id in groups}
        return rows, names, groups

    async def collect(self, root_id: str) -> list[dict]:
        # Иерархию раскрываем послойно: дети следующего уровня известны
        # только после запроса по текущему. known — множество: дедуп ВНУТРИ
        # построения фронта, а не после — иначе комната, достижимая двумя
        # путями в ОДНОМ слое (диамант R->A,R->B; A->C,B->C), остаётся в
        # фронте дважды и на каждом следующем слое число путей к общему
        # потомку удваивается (Critical, ревью Task 6 round 1).
        known = {root_id}
        edges: dict[str, list] = {}
        frontier = [root_id]
        for _ in range(MAX_SPACE_DEPTH):
            if not frontier or len(known) >= MAX_SPACE_ROOMS:
                break
            layer = await self._child_edges(frontier)
            edges.update(layer)
            next_frontier = []
            for parent in frontier:
                for child in layer.get(parent, ()):
                    if child in known:
                        continue
                    known.add(child)
                    next_frontier.append(child)
                    if len(known) >= MAX_SPACE_ROOMS:
                        break
                if len(known) >= MAX_SPACE_ROOMS:
                    break
            frontier = next_frontier

        if len(known) >= MAX_SPACE_ROOMS:
            logger.warning(
                "access_admin space_members: поддерево %s обрезано на %d "
                "комнатах (лимит MAX_SPACE_ROOMS)",
                root_id,
                MAX_SPACE_ROOMS,
            )

        room_ids = collect_space_room_ids(edges, root_id)[:MAX_SPACE_ROOMS]
        rows, names, groups = await self._fetch_members(room_ids)
        return build_space_members(
            rows, root_id=root_id, room_names=names, room_groups=groups
        )
