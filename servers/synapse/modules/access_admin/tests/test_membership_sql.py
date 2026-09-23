"""Паритет нового источника членств со старым — на живом SQL.

local_current_membership покрывает только локальных пользователей: для
федеративного MXID она пуста, поэтому досье такого аккаунта всегда было
пустым. Новый источник — m.room.member из current_state_events.

Схема здесь минимальная: только колонки, которые читает запрос. Это
SQLite, а не Postgres — проверяем логику выборки (какие строки вернутся),
не диалект.
"""

import json
import sqlite3
import unittest

from synapse_modules.access_admin._dossier import membership_rows_sql

LOCAL = "@ivan:liza.example"
FOREIGN = "@petr:other.example"


def _member_event(user_id: str, membership: str) -> str:
    return json.dumps({"content": {"membership": membership}})


class MembershipSqlTestCase(unittest.TestCase):
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
                room_id TEXT, name TEXT, avatar TEXT, room_type TEXT
            );
            """
        )

    def tearDown(self):
        self.db.close()

    def _add_membership(self, room_id, user_id, membership, event_id):
        self.db.execute(
            "INSERT INTO current_state_events "
            "(event_id, room_id, type, state_key, membership) "
            "VALUES (?, ?, 'm.room.member', ?, ?)",
            (event_id, room_id, user_id, membership),
        )
        self.db.execute(
            "INSERT INTO event_json (event_id, json) VALUES (?, ?)",
            (event_id, _member_event(user_id, membership)),
        )

    def _add_room(self, room_id, name=None, room_type=None):
        self.db.execute(
            "INSERT INTO room_stats_state "
            "(room_id, name, avatar, room_type) VALUES (?, ?, NULL, ?)",
            (room_id, name, room_type),
        )

    def _rooms_for(self, user_id):
        cur = self.db.execute(membership_rows_sql(), (user_id,))
        return sorted(row[0] for row in cur.fetchall())

    def test_join_room_returned(self):
        self._add_room("!a:liza.example", "Чат")
        self._add_membership("!a:liza.example", LOCAL, "join", "$1")
        self.assertEqual(self._rooms_for(LOCAL), ["!a:liza.example"])

    def test_leave_room_excluded(self):
        self._add_room("!b:liza.example", "Покинутый")
        self._add_membership("!b:liza.example", LOCAL, "leave", "$2")
        self.assertEqual(self._rooms_for(LOCAL), [])

    def test_ban_and_invite_excluded(self):
        self._add_room("!c:liza.example")
        self._add_room("!d:liza.example")
        self._add_membership("!c:liza.example", LOCAL, "ban", "$3")
        self._add_membership("!d:liza.example", LOCAL, "invite", "$4")
        self.assertEqual(self._rooms_for(LOCAL), [])

    def test_federated_user_gets_rooms(self):
        # Главное требование задачи: раньше здесь всегда было пусто.
        self._add_room("!e:liza.example", "Общий чат")
        self._add_membership("!e:liza.example", FOREIGN, "join", "$5")
        self.assertEqual(self._rooms_for(FOREIGN), ["!e:liza.example"])

    def test_other_users_rooms_not_leaked(self):
        self._add_room("!f:liza.example")
        self._add_membership("!f:liza.example", FOREIGN, "join", "$6")
        self.assertEqual(self._rooms_for(LOCAL), [])

    def test_room_metadata_joined(self):
        self._add_room("!g:liza.example", "Разработка", "m.space")
        self._add_membership("!g:liza.example", LOCAL, "join", "$7")
        row = self.db.execute(membership_rows_sql(), (LOCAL,)).fetchone()
        self.assertEqual(row[1], "Разработка")
        self.assertEqual(row[3], "m.space")

    def test_row_has_eight_fields(self):
        # Потребители распаковывают строку в 8 переменных.
        self._add_room("!h:liza.example")
        self._add_membership("!h:liza.example", LOCAL, "join", "$8")
        row = self.db.execute(membership_rows_sql(), (LOCAL,)).fetchone()
        self.assertEqual(len(row), 8)


if __name__ == "__main__":
    unittest.main()
