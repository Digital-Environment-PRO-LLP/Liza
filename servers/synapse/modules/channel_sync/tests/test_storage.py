"""Unit tests for MirrorStore (channel_sync._storage).

Async-стиль: pytest-asyncio в servers/synapse/src не установлен (урок из
плана 1) — используем unittest.TestCase + asyncio.run(...), как в
user_roles/tests/test_federation.py, а не @pytest.mark.asyncio.
"""

import asyncio
import json
import sqlite3
import unittest

from synapse_modules.channel_sync._storage import MirrorStore


def _run(coro):
    return asyncio.run(coro)


class _FakeEngine:
    is_postgres = False


class _FakeDbPool:
    """Минимальный контракт runInteraction поверх реального sqlite."""

    def __init__(self):
        self._conn = sqlite3.connect(":memory:")
        self.engine = _FakeEngine()

    async def runInteraction(self, desc, func, *args):
        cur = self._conn.cursor()
        try:
            result = func(cur, *args)
            self._conn.commit()
            return result
        finally:
            cur.close()


class MirrorStoreTestCase(unittest.TestCase):
    def test_ensure_schema_and_put_get(self):
        st = MirrorStore(_FakeDbPool())
        _run(st.ensure_schema())
        _run(st.put_mirror("$post", "$mirror", "!disc:h"))
        self.assertEqual(_run(st.get_mirror("$post")), ("$mirror", "!disc:h"))
        self.assertTrue(_run(st.already_mirrored("$post")))
        self.assertFalse(_run(st.already_mirrored("$nope")))

    def test_put_is_idempotent(self):
        st = MirrorStore(_FakeDbPool())
        _run(st.ensure_schema())
        _run(st.put_mirror("$post", "$mirror1", "!disc:h"))
        _run(st.put_mirror("$post", "$mirror2", "!disc:h"))  # ON CONFLICT DO NOTHING
        self.assertEqual(_run(st.get_mirror("$post")), ("$mirror1", "!disc:h"))  # не перезаписалось

    def test_get_mirror_returns_none_when_absent(self):
        st = MirrorStore(_FakeDbPool())
        _run(st.ensure_schema())
        self.assertIsNone(_run(st.get_mirror("$nope")))

    def test_delete_mirror_removes_row(self):
        st = MirrorStore(_FakeDbPool())
        _run(st.ensure_schema())
        _run(st.put_mirror("$post", "$mirror", "!disc:h"))
        _run(st.delete_mirror("$post"))
        self.assertIsNone(_run(st.get_mirror("$post")))
        self.assertFalse(_run(st.already_mirrored("$post")))

    def test_delete_mirror_missing_row_is_noop(self):
        st = MirrorStore(_FakeDbPool())
        _run(st.ensure_schema())
        _run(st.delete_mirror("$nope"))  # не должно бросить

    def test_delete_by_discussion_removes_all_rows_of_room(self):
        st = MirrorStore(_FakeDbPool())
        _run(st.ensure_schema())
        _run(st.put_mirror("$p1", "$m1", "!disc:h"))
        _run(st.put_mirror("$p2", "$m2", "!disc:h"))
        _run(st.put_mirror("$p3", "$m3", "!other:h"))

        removed = _run(st.delete_by_discussion("!disc:h"))

        self.assertEqual(removed, 2)
        self.assertIsNone(_run(st.get_mirror("$p1")))
        self.assertIsNone(_run(st.get_mirror("$p2")))
        self.assertEqual(_run(st.get_mirror("$p3")), ("$m3", "!other:h"))


class FindChannelRoomsTestCase(unittest.TestCase):
    """find_channel_rooms поверх реального sqlite со схемой Synapse."""

    def _pool_with_rooms(self, rooms):
        """rooms: list[(room_id, create_content_dict)]."""
        pool = _FakeDbPool()
        conn = pool._conn
        conn.execute(
            "CREATE TABLE current_state_events "
            "(room_id TEXT, event_id TEXT, type TEXT, state_key TEXT)"
        )
        conn.execute("CREATE TABLE event_json (event_id TEXT, json TEXT)")
        for idx, (room_id, content) in enumerate(rooms):
            event_id = f"$create{idx}"
            conn.execute(
                "INSERT INTO current_state_events VALUES (?, ?, 'm.room.create', '')",
                (room_id, event_id),
            )
            conn.execute(
                "INSERT INTO event_json VALUES (?, ?)",
                # Компактная сериализация — как в форке Synapse (отсюда запрет
                # на LIKE по JSON и разбор на Python).
                (event_id, json.dumps({"content": content}, separators=(",", ":"))),
            )
        conn.commit()
        return pool

    def test_returns_only_channel_rooms(self):
        st = MirrorStore(
            self._pool_with_rooms(
                [
                    ("!chan:h", {"com.liza.chat.type": "channel"}),
                    ("!disc:h", {"com.liza.chat.type": "channel_discussion"}),
                    ("!story:h", {"com.liza.chat.type": "stories"}),
                    ("!plain:h", {}),
                ]
            )
        )
        self.assertEqual(_run(st.find_channel_rooms()), ["!chan:h"])

    def test_empty_when_no_channels(self):
        st = MirrorStore(
            self._pool_with_rooms([("!plain:h", {"com.liza.chat.type": "dm"})])
        )
        self.assertEqual(_run(st.find_channel_rooms()), [])

    def test_broken_json_row_does_not_break_scan(self):
        """Битый event_json не должен ронять весь проход по комнатам."""
        pool = self._pool_with_rooms([("!chan:h", {"com.liza.chat.type": "channel"})])
        pool._conn.execute(
            "INSERT INTO current_state_events VALUES "
            "('!broken:h', '$broken', 'm.room.create', '')"
        )
        pool._conn.execute("INSERT INTO event_json VALUES ('$broken', 'not-json')")
        pool._conn.commit()
        self.assertEqual(_run(MirrorStore(pool).find_channel_rooms()), ["!chan:h"])


if __name__ == "__main__":
    unittest.main()
