"""SQL-слой space_members на живом SQLite.

Проверяем только логику выборки (какие строки вернутся), не диалект —
портативность IN(...) вместо Postgres-специфичного ANY(?) уже отдельно
задокументирована в _space_members.py.
"""

import asyncio
import json
import sqlite3
import unittest

from synapse_modules.access_admin._logic import power_from_content
from synapse_modules.access_admin._space_members import (
    SpaceMembersBuilder,
    _child_edges_sql,
    _content_from_json,
    _member_rows_sql,
)

ROOT = "!root:liza.example"


def _run(coro):
    return asyncio.run(coro)


class _FakeDbPool:
    """Синхронный sqlite3 под async-интерфейс runInteraction(name, fn)."""

    def __init__(self, conn: sqlite3.Connection):
        self._conn = conn

    async def runInteraction(self, _name: str, fn):
        cur = self._conn.cursor()
        return fn(cur)


def _member_event(user_id: str) -> str:
    return json.dumps({"content": {"membership": "join"}})


def _power_event(users: dict) -> str:
    return json.dumps({"content": {"users": users}})


def _child_event(via: list | None = ("liza.example",)) -> str:
    """content m.space.child. via=None/[] — отозванное ребро (спека Matrix:

    ребёнок убирается очисткой content, событие остаётся в
    current_state_events)."""
    content = {"via": list(via)} if via else {}
    return json.dumps({"content": content})


def _create_event(chat_type: str | None = None, legacy_stories: bool = False) -> str:
    content = {}
    if chat_type is not None:
        content["com.liza.chat.type"] = chat_type
    if legacy_stories:
        content["com.liza.stories"] = True
    return json.dumps({"content": content})


class SpaceMembersSqlTestCase(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.executescript(
            """
            CREATE TABLE current_state_events (
                event_id TEXT, room_id TEXT, type TEXT,
                state_key TEXT, membership TEXT
            );
            CREATE TABLE event_json (event_id TEXT, json TEXT);
            CREATE TABLE room_stats_state (
                room_id TEXT, name TEXT, room_type TEXT
            );
            """
        )

    def tearDown(self):
        self.db.close()

    def _add_room(self, room_id, name=None, room_type=None):
        self.db.execute(
            "INSERT INTO room_stats_state (room_id, name, room_type) "
            "VALUES (?, ?, ?)",
            (room_id, name, room_type),
        )

    def _add_power_levels(self, room_id, users, event_id):
        self.db.execute(
            "INSERT INTO current_state_events "
            "(event_id, room_id, type, state_key) "
            "VALUES (?, ?, 'm.room.power_levels', '')",
            (event_id, room_id),
        )
        self.db.execute(
            "INSERT INTO event_json (event_id, json) VALUES (?, ?)",
            (event_id, _power_event(users)),
        )

    def _add_child(self, parent_id, child_id, event_id, via=("liza.example",)):
        self.db.execute(
            "INSERT INTO current_state_events "
            "(event_id, room_id, type, state_key) "
            "VALUES (?, ?, 'm.space.child', ?)",
            (event_id, parent_id, child_id),
        )
        self.db.execute(
            "INSERT INTO event_json (event_id, json) VALUES (?, ?)",
            (event_id, _child_event(via)),
        )

    def _add_member(self, room_id, user_id, event_id):
        self.db.execute(
            "INSERT INTO current_state_events "
            "(event_id, room_id, type, state_key, membership) "
            "VALUES (?, ?, 'm.room.member', ?, 'join')",
            (event_id, room_id, user_id),
        )
        self.db.execute(
            "INSERT INTO event_json (event_id, json) VALUES (?, ?)",
            (event_id, _member_event(user_id)),
        )

    def test_child_edges_sql_returns_direct_children(self):
        self._add_child(ROOT, "!a:liza.example", "$1")
        self._add_child(ROOT, "!b:liza.example", "$2")
        cur = self.db.execute(_child_edges_sql(1), (ROOT,))
        rows = sorted((room_id, state_key) for room_id, state_key, _raw in cur.fetchall())
        self.assertEqual(
            rows, [(ROOT, "!a:liza.example"), (ROOT, "!b:liza.example")]
        )

    def test_child_edges_sql_ignores_rooms_outside_list(self):
        self._add_child(ROOT, "!a:liza.example", "$1")
        self._add_child("!other:liza.example", "!c:liza.example", "$2")
        cur = self.db.execute(_child_edges_sql(1), (ROOT,))
        rows = [(room_id, state_key) for room_id, state_key, _raw in cur.fetchall()]
        self.assertEqual(rows, [(ROOT, "!a:liza.example")])

    def test_child_edges_sql_multi_room_placeholders(self):
        self._add_child(ROOT, "!a:liza.example", "$1")
        self._add_child("!sub:liza.example", "!deep:liza.example", "$2")
        cur = self.db.execute(
            _child_edges_sql(2), (ROOT, "!sub:liza.example")
        )
        rows = sorted((room_id, state_key) for room_id, state_key, _raw in cur.fetchall())
        self.assertEqual(
            rows,
            [
                (ROOT, "!a:liza.example"),
                ("!sub:liza.example", "!deep:liza.example"),
            ],
        )

    def test_child_edges_sql_revoked_edge_row_present_but_content_empty(self):
        """SQL сам не фильтрует — отсеивание по via делает _child_edges()

        в SpaceMembersBuilder (см. SpaceMembersBuilderTestCase). Здесь
        фиксируем только то, что строка возвращается ВМЕСТЕ с JSON, чтобы
        Python-слой мог решить."""
        self._add_child(ROOT, "!a:liza.example", "$1", via=None)
        cur = self.db.execute(_child_edges_sql(1), (ROOT,))
        rows = cur.fetchall()
        self.assertEqual(len(rows), 1)
        content = _content_from_json(rows[0][2])
        self.assertEqual(content, {})

    def test_member_rows_sql_returns_join_only(self):
        self._add_member(ROOT, "@ivan:liza.example", "$m1")
        self.db.execute(
            "INSERT INTO current_state_events "
            "(event_id, room_id, type, state_key, membership) "
            "VALUES ('$m2', ?, 'm.room.member', '@petr:liza.example', 'leave')",
            (ROOT,),
        )
        cur = self.db.execute(_member_rows_sql(1), (ROOT,))
        rows = cur.fetchall()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][1], "@ivan:liza.example")

    def test_power_from_content_reads_member_room_power(self):
        # power_from_content разбирает JSON power_levels отдельным запросом
        # (см. DossierBuilder.power_in_room) — здесь только фиксируем
        # совместимость сериализации: content -> power_from_content.
        raw = _power_event({"@ivan:liza.example": 100})
        content = _content_from_json(raw)
        self.assertEqual(power_from_content(content, "@ivan:liza.example"), 100)
        self.assertEqual(power_from_content(content, "@petr:liza.example"), 0)


class SpaceMembersBuilderTestCase(unittest.TestCase):
    """collect() сквозь весь путь: BFS по слоям -> сбор членов -> ответ."""

    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.executescript(
            """
            CREATE TABLE current_state_events (
                event_id TEXT, room_id TEXT, type TEXT,
                state_key TEXT, membership TEXT
            );
            CREATE TABLE event_json (event_id TEXT, json TEXT);
            CREATE TABLE room_stats_state (
                room_id TEXT, name TEXT, room_type TEXT
            );
            """
        )
        self.builder = SpaceMembersBuilder(_FakeDbPool(self.db))

    def tearDown(self):
        self.db.close()

    def _add_room(self, room_id, name=None, room_type=None):
        self.db.execute(
            "INSERT INTO room_stats_state (room_id, name, room_type) "
            "VALUES (?, ?, ?)",
            (room_id, name, room_type),
        )

    def _add_child(self, parent_id, child_id, event_id, via=("liza.example",)):
        self.db.execute(
            "INSERT INTO current_state_events "
            "(event_id, room_id, type, state_key) "
            "VALUES (?, ?, 'm.space.child', ?)",
            (event_id, parent_id, child_id),
        )
        self.db.execute(
            "INSERT INTO event_json (event_id, json) VALUES (?, ?)",
            (event_id, _child_event(via)),
        )

    def _add_member(self, room_id, user_id, event_id):
        self.db.execute(
            "INSERT INTO current_state_events "
            "(event_id, room_id, type, state_key, membership) "
            "VALUES (?, ?, 'm.room.member', ?, 'join')",
            (event_id, room_id, user_id),
        )
        self.db.execute(
            "INSERT INTO event_json (event_id, json) VALUES (?, ?)",
            (event_id, _member_event(user_id)),
        )

    def _add_power_levels(self, room_id, users, event_id):
        self.db.execute(
            "INSERT INTO current_state_events "
            "(event_id, room_id, type, state_key) "
            "VALUES (?, ?, 'm.room.power_levels', '')",
            (event_id, room_id),
        )
        self.db.execute(
            "INSERT INTO event_json (event_id, json) VALUES (?, ?)",
            (event_id, _power_event(users)),
        )

    def _add_room_create(self, room_id, event_id, chat_type=None, legacy_stories=False):
        self.db.execute(
            "INSERT INTO current_state_events "
            "(event_id, room_id, type, state_key) "
            "VALUES (?, ?, 'm.room.create', '')",
            (event_id, room_id),
        )
        self.db.execute(
            "INSERT INTO event_json (event_id, json) VALUES (?, ?)",
            (event_id, _create_event(chat_type, legacy_stories)),
        )

    def test_root_only_no_children(self):
        self._add_room(ROOT, "Компания", "m.space")
        self._add_member(ROOT, "@ivan:liza.example", "$1")
        members = _run(self.builder.collect(ROOT))
        self.assertEqual(len(members), 1)
        self.assertEqual(members[0]["user_id"], "@ivan:liza.example")
        self.assertEqual(members[0]["membership_in_space"], "join")

    def test_child_only_member_included_with_null_membership(self):
        chat = "!chat:liza.example"
        self._add_room(ROOT, "Компания", "m.space")
        self._add_room(chat, "Разработка", None)
        self._add_child(ROOT, chat, "$edge1")
        self._add_member(chat, "@petr:liza.example", "$m1")

        members = _run(self.builder.collect(ROOT))

        self.assertEqual(len(members), 1)
        self.assertEqual(members[0]["user_id"], "@petr:liza.example")
        self.assertIsNone(members[0]["membership_in_space"])

    def test_revoked_child_edge_excluded_from_subtree(self):
        """Чат вывели из компании (via очищен) — участники не должны

        оставаться в списке (Important, ревью Task 6 round 1)."""
        chat = "!chat:liza.example"
        self._add_room(ROOT, "Компания", "m.space")
        self._add_room(chat, "Бывший чат компании", None)
        self._add_child(ROOT, chat, "$edge1", via=None)  # отозванное ребро
        self._add_member(chat, "@petr:liza.example", "$m1")

        members = _run(self.builder.collect(ROOT))

        self.assertEqual(members, [])

    def test_stories_room_excluded_from_subtree(self):
        """Служебная (сторис) комната в поддереве — её участники НЕ должны

        попасть в список участников компании (Important, ревью round 1:
        classify_room(room_type, None) безусловно скрывал chat_type)."""
        stories = "!stories:liza.example"
        self._add_room(ROOT, "Компания", "m.space")
        self._add_room(stories, None, None)
        self._add_room_create(stories, "$cr1", chat_type="stories")
        self._add_child(ROOT, stories, "$edge1")
        self._add_member(stories, "@petr:liza.example", "$m1")

        members = _run(self.builder.collect(ROOT))

        self.assertEqual(members, [])

    def test_plain_chat_without_create_content_still_included(self):
        """Обычный чат без com.liza.chat.type (массовый случай) — фикс

        Important 3 не должен ломать стандартный путь, где create_content
        пуст или отсутствует."""
        chat = "!chat:liza.example"
        self._add_room(ROOT, "Компания", "m.space")
        self._add_room(chat, "Обычный чат", None)
        self._add_child(ROOT, chat, "$edge1")
        self._add_member(chat, "@petr:liza.example", "$m1")

        members = _run(self.builder.collect(ROOT))

        self.assertEqual(
            [m["user_id"] for m in members], ["@petr:liza.example"]
        )

    def test_nested_subspace_members_included(self):
        sub = "!sub:liza.example"
        deep = "!deep:liza.example"
        self._add_room(ROOT, "Компания", "m.space")
        self._add_room(sub, "Подпространство", "m.space")
        self._add_room(deep, "Глубокий чат", None)
        self._add_child(ROOT, sub, "$e1")
        self._add_child(sub, deep, "$e2")
        self._add_member(deep, "@anna:liza.example", "$m1")

        members = _run(self.builder.collect(ROOT))

        self.assertIn(
            "@anna:liza.example", [m["user_id"] for m in members]
        )

    def test_diamond_shape_does_not_duplicate_child_edges_layer(self):
        """R->A, R->B; A->C, B->C — C достижим двумя путями В ОДНОМ слое.

        SpaceMembersBuilder.collect() строил `known` как список и
        дедуплицировал ПОСЛЕ построения фронта (Critical, ревью round 1):
        дубли внутри одного слоя не отсекались. Итоговый список членов
        уже был корректен (build_space_members агрегирует по user_id), но
        промежуточный фронт SQL-запроса раздувался — см. следующий тест
        на экспоненциальный рост при многослойной сетке.
        """
        a = "!a:liza.example"
        b = "!b:liza.example"
        c = "!c:liza.example"
        self._add_room(ROOT, "Компания", "m.space")
        self._add_room(a, "A", "m.space")
        self._add_room(b, "B", "m.space")
        self._add_room(c, "C", None)
        self._add_child(ROOT, a, "$e1")
        self._add_child(ROOT, b, "$e2")
        self._add_child(a, c, "$e3")
        self._add_child(b, c, "$e4")
        self._add_member(c, "@ivan:liza.example", "$m1")

        members = _run(self.builder.collect(ROOT))

        self.assertEqual(
            [m["user_id"] for m in members], ["@ivan:liza.example"]
        )

    def test_diamond_frontier_stays_linear_not_exponential(self):
        """Многослойная сетка диамантов: КАЖДЫЙ слой сходится в ОДНУ

        комнату следующего слоя. Без фикса каждый слой удваивает число
        путей к общему потомку, и фронт следующего слоя содержит N
        дублей узла — размер фронта растёт экспоненциально с числом
        слоёв. Проверяем напрямую: перехватываем аргументы, с которыми
        _child_edges() вызывает SQL, и требуем отсутствие дублей на
        каждом слое (иначе список bind-параметров в IN(...) взрывается).
        """
        layers = 6  # 2**6 путей к терминальной комнате без дедупа
        prev = [ROOT]
        self._add_room(ROOT, "Компания", "m.space")
        for level in range(layers):
            nxt = [f"!L{level}-{i}:liza.example" for i in range(2)]
            for room_id in nxt:
                self._add_room(room_id, room_id, "m.space")
            for parent in prev:
                for child in nxt:
                    self._add_child(parent, child, f"$e{level}-{parent}-{child}")
            prev = nxt
        # Terminal: сходим все последние узлы в одну общую комнату.
        terminal = "!terminal:liza.example"
        self._add_room(terminal, "Terminal", None)
        for parent in prev:
            self._add_child(parent, terminal, f"$eterm-{parent}")
        self._add_member(terminal, "@ivan:liza.example", "$m1")

        seen_frontier_sizes = []
        original_child_edges = self.builder._child_edges

        async def _tracking_child_edges(room_ids):
            seen_frontier_sizes.append(len(room_ids))
            return await original_child_edges(room_ids)

        self.builder._child_edges = _tracking_child_edges

        members = _run(self.builder.collect(ROOT))

        # Ширина сетки на каждом слое — не больше 2 узлов; фронт с дублями
        # рос бы как 2, 4, 8, 16... — здесь он обязан оставаться <= 2.
        self.assertTrue(
            all(size <= 2 for size in seen_frontier_sizes),
            f"фронт BFS растёт с дублями: {seen_frontier_sizes}",
        )
        self.assertEqual(
            [m["user_id"] for m in members], ["@ivan:liza.example"]
        )

    def test_cycle_in_hierarchy_does_not_hang(self):
        a = "!a:liza.example"
        self._add_room(ROOT, "Компания", "m.space")
        self._add_room(a, "A", "m.space")
        self._add_child(ROOT, a, "$e1")
        self._add_child(a, ROOT, "$e2")  # цикл A -> ROOT
        self._add_member(a, "@ivan:liza.example", "$m1")

        members = _run(self.builder.collect(ROOT))  # не должно зависнуть

        self.assertEqual(
            [m["user_id"] for m in members], ["@ivan:liza.example"]
        )

    def test_elevated_rooms_reflect_real_power_levels(self):
        chat = "!chat:liza.example"
        self._add_room(ROOT, "Компания", "m.space")
        self._add_room(chat, "Разработка", None)
        self._add_child(ROOT, chat, "$e1")
        self._add_member(chat, "@ivan:liza.example", "$m1")
        self._add_power_levels(chat, {"@ivan:liza.example": 100}, "$pl1")

        members = _run(self.builder.collect(ROOT))

        ivan = members[0]
        self.assertEqual(ivan["max_power_level"], 100)
        self.assertEqual(len(ivan["elevated_rooms"]), 1)
        self.assertEqual(ivan["elevated_rooms"][0]["room_id"], chat)
        self.assertEqual(ivan["elevated_rooms"][0]["name"], "Разработка")


if __name__ == "__main__":
    unittest.main()
