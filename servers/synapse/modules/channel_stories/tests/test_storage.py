"""Unit tests for ChannelStoriesStore (channel_stories._storage).

Async-стиль: pytest-asyncio в servers/synapse/src не установлен (урок из
плана 1) — используем unittest.TestCase + asyncio.run(...), как в
channel_sync/tests/test_storage.py, а не @pytest.mark.asyncio.
"""

import asyncio
import sqlite3
import unittest

from synapse_modules.channel_stories._storage import ChannelStoriesStore


class _FakeEngine:
    is_postgres = False


class _FakeDbPool:
    def __init__(self):
        self._conn = sqlite3.connect(":memory:")
        self.engine = _FakeEngine()

    async def runInteraction(self, desc, func, *args):
        cur = self._conn.cursor()
        try:
            r = func(cur, *args)
            self._conn.commit()
            return r
        finally:
            cur.close()


class StoreTest(unittest.TestCase):
    def test_put_get_idempotent(self):
        asyncio.run(self._run())

    async def _run(self):
        st = ChannelStoriesStore(_FakeDbPool())
        await st.ensure_schema()
        await st.put_stories_room("!chan:h", "!stories:h")
        assert await st.get_stories_room("!chan:h") == "!stories:h"
        await st.put_stories_room("!chan:h", "!other:h")  # ON CONFLICT
        assert await st.get_stories_room("!chan:h") == "!stories:h"
        assert await st.get_stories_room("!nope:h") is None


if __name__ == "__main__":
    unittest.main()
