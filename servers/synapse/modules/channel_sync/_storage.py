"""Хранилище маппинга пост↔зеркало для channel_sync.

Плейсхолдеры `?` — Synapse LoggingTransaction конвертирует их в `%s` на
Postgres, на sqlite они нативны. Схема — отдельный DDL для каждого движка.
"""
import json
from typing import Any, Optional

_SCHEMA_SQLITE = [
    """
    CREATE TABLE IF NOT EXISTS channel_post_mirror (
        post_event_id TEXT PRIMARY KEY,
        mirror_event_id TEXT NOT NULL,
        discussion_room_id TEXT NOT NULL
    )
    """,
]

_SCHEMA_POSTGRES = [
    """
    CREATE TABLE IF NOT EXISTS channel_post_mirror (
        post_event_id TEXT PRIMARY KEY,
        mirror_event_id TEXT NOT NULL,
        discussion_room_id TEXT NOT NULL
    )
    """,
]


class MirrorStore:
    def __init__(self, db_pool: Any) -> None:
        self._db = db_pool

    async def ensure_schema(self) -> None:
        is_postgres = getattr(self._db.engine, "is_postgres", False)
        statements = _SCHEMA_POSTGRES if is_postgres else _SCHEMA_SQLITE

        def _create(txn: Any) -> None:
            for stmt in statements:
                txn.execute(stmt)

        await self._db.runInteraction("channel_sync_schema", _create)

    async def put_mirror(
        self, post_event_id: str, mirror_event_id: str, discussion_room_id: str
    ) -> None:
        def _insert(txn: Any) -> None:
            txn.execute(
                "INSERT INTO channel_post_mirror "
                "(post_event_id, mirror_event_id, discussion_room_id) "
                "VALUES (?, ?, ?) "
                "ON CONFLICT (post_event_id) DO NOTHING",
                (post_event_id, mirror_event_id, discussion_room_id),
            )

        await self._db.runInteraction("channel_sync_put_mirror", _insert)

    async def get_mirror(self, post_event_id: str) -> Optional[tuple]:
        def _get(txn: Any) -> Optional[tuple]:
            txn.execute(
                "SELECT mirror_event_id, discussion_room_id "
                "FROM channel_post_mirror WHERE post_event_id = ?",
                (post_event_id,),
            )
            row = txn.fetchone()
            return (row[0], row[1]) if row else None

        return await self._db.runInteraction("channel_sync_get_mirror", _get)

    async def already_mirrored(self, post_event_id: str) -> bool:
        def _check(txn: Any) -> bool:
            txn.execute(
                "SELECT 1 FROM channel_post_mirror WHERE post_event_id = ?",
                (post_event_id,),
            )
            return txn.fetchone() is not None

        return await self._db.runInteraction("channel_sync_check", _check)

    async def delete_mirror(self, post_event_id: str) -> None:
        """Удаляет маппинг поста. Вызывается при redaction поста: без этого
        строки в channel_post_mirror копятся вечно (DELETE не было вовсе)."""

        def _delete(txn: Any) -> None:
            txn.execute(
                "DELETE FROM channel_post_mirror WHERE post_event_id = ?",
                (post_event_id,),
            )

        await self._db.runInteraction("channel_sync_delete_mirror", _delete)

    async def delete_by_discussion(self, discussion_room_id: str) -> int:
        """Удаляет все маппинги привязанного чата (канал удалён/отвязан).
        Возвращает число удалённых строк."""

        def _delete(txn: Any) -> int:
            txn.execute(
                "DELETE FROM channel_post_mirror WHERE discussion_room_id = ?",
                (discussion_room_id,),
            )
            return txn.rowcount

        return await self._db.runInteraction(
            "channel_sync_delete_by_discussion", _delete
        )

    async def find_channel_rooms(self) -> list[str]:
        """room_id всех комнат-каналов (m.room.create content
        com.liza.chat.type == 'channel').

        Нужен разовой миграции привязанных чатов: реактивные колбэки модуля
        видят только новые события, а существующие каналы надо обойти списком.

        Фильтр по content — на Python через json.loads, а не LIKE по
        event_json.json: форк сериализует событие компактно
        (separators=(",", ":")), поэтому LIKE-паттерн с пробелом после
        двоеточия не матчит реальные данные. Тот же приём, что в
        stories_membership._find_expired_stories_txn и
        chat_topology_sync_gate.scripts.backfill_hidden.
        """

        def _find(txn: Any) -> list[str]:
            txn.execute(
                """
                SELECT cse.room_id, ej.json
                FROM current_state_events AS cse
                JOIN event_json AS ej ON ej.event_id = cse.event_id
                WHERE cse.type = 'm.room.create' AND cse.state_key = ''
                """
            )
            rooms: list[str] = []
            for room_id, raw_json in txn.fetchall():
                try:
                    content = (json.loads(raw_json) or {}).get("content") or {}
                except (TypeError, ValueError):
                    continue
                if content.get("com.liza.chat.type") == "channel":
                    rooms.append(room_id)
            return rooms

        return await self._db.runInteraction("channel_sync_find_channels", _find)
