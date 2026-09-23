from typing import Any, Optional

_SCHEMA = [
    """
    CREATE TABLE IF NOT EXISTS channel_stories (
        channel_id TEXT PRIMARY KEY,
        stories_room_id TEXT NOT NULL
    )
    """,
]


class ChannelStoriesStore:
    def __init__(self, db_pool: Any) -> None:
        self._db = db_pool

    async def ensure_schema(self) -> None:
        def _create(txn: Any) -> None:
            for stmt in _SCHEMA:
                txn.execute(stmt)

        await self._db.runInteraction("channel_stories_schema", _create)

    async def put_stories_room(self, channel_id: str, stories_room_id: str) -> None:
        def _insert(txn: Any) -> None:
            txn.execute(
                "INSERT INTO channel_stories (channel_id, stories_room_id) "
                "VALUES (?, ?) ON CONFLICT (channel_id) DO NOTHING",
                (channel_id, stories_room_id),
            )

        await self._db.runInteraction("channel_stories_put", _insert)

    async def get_stories_room(self, channel_id: str) -> Optional[str]:
        def _get(txn: Any) -> Optional[str]:
            txn.execute(
                "SELECT stories_room_id FROM channel_stories WHERE channel_id = ?",
                (channel_id,),
            )
            row = txn.fetchone()
            return row[0] if row else None

        return await self._db.runInteraction("channel_stories_get", _get)
