"""Хранилище device_capabilities: per-device build number для sync-gate.

Не использует account_data/device_display_name — отдельная таблица,
не пересекается с локальным состоянием клиента (см. design doc,
секция "Носитель сигнала версии устройства").
"""

from typing import Any, Optional

_SCHEMA_SQL_POSTGRES = (
    """
    CREATE TABLE IF NOT EXISTS device_capabilities (
        device_id  TEXT PRIMARY KEY,
        user_id    TEXT NOT NULL,
        platform   TEXT NOT NULL,
        build      INTEGER NOT NULL,
        updated_ts BIGINT NOT NULL
    )
    """,
    """
    CREATE INDEX IF NOT EXISTS device_capabilities_user_id
        ON device_capabilities (user_id)
    """,
)

_SCHEMA_SQL_SQLITE = _SCHEMA_SQL_POSTGRES


class DeviceCapabilitiesStore:
    def __init__(self, db_pool: Any) -> None:
        self._db = db_pool

    async def ensure_schema(self) -> None:
        is_postgres = getattr(self._db.engine, "is_postgres", False)
        schema_statements = _SCHEMA_SQL_POSTGRES if is_postgres else _SCHEMA_SQL_SQLITE

        def _create(txn: Any) -> None:
            for stmt in schema_statements:
                txn.execute(stmt)

        await self._db.runInteraction("chat_topology_sync_gate_schema", _create)

    async def upsert_capability(
        self, device_id: str, user_id: str, platform: str, build: int
    ) -> bool:
        """Возвращает True, если build для этого device_id увеличился
        относительно сохранённого значения (или записи раньше не было)."""
        import time

        now = int(time.time() * 1000)

        def _upsert(txn: Any) -> bool:
            txn.execute(
                "SELECT build FROM device_capabilities WHERE device_id = ?",
                (device_id,),
            )
            row = txn.fetchone()
            previous_build = row[0] if row else None

            if row is None:
                txn.execute(
                    "INSERT INTO device_capabilities "
                    "(device_id, user_id, platform, build, updated_ts) "
                    "VALUES (?, ?, ?, ?, ?)",
                    (device_id, user_id, platform, build, now),
                )
            else:
                txn.execute(
                    "UPDATE device_capabilities "
                    "SET user_id = ?, platform = ?, build = ?, updated_ts = ? "
                    "WHERE device_id = ?",
                    (user_id, platform, build, now, device_id),
                )

            return previous_build is None or build > previous_build

        return await self._db.runInteraction(
            "chat_topology_sync_gate_upsert", _upsert
        )

    async def get_capability(self, device_id: str) -> Optional[dict]:
        def _get(txn: Any) -> Optional[dict]:
            txn.execute(
                "SELECT platform, build FROM device_capabilities WHERE device_id = ?",
                (device_id,),
            )
            row = txn.fetchone()
            if row is None:
                return None
            return {"platform": row[0], "build": row[1]}

        return await self._db.runInteraction("chat_topology_sync_gate_get", _get)


class HiddenRoomsLookup:
    """Список комнат пользователя с com.liza.chat.topology content.hidden=true.
    Источник — current_state_events Synapse (через StateStorageController),
    не своя таблица.

    Legacy-дефолт: комнаты без topology state вообще, но с creation_content
    com.liza.stories=true либо com.liza.chat.type='stories' (создаются
    модулем stories_membership, ещё не проставляющим новый ключ и не
    покрытые бэкфиллом) тоже считаются hidden. Это зеркалит логику
    isHiddenChat/lizaChatType в clients/flutter/lib/utils/chat_topology.dart —
    обе стороны должны совпадать, иначе старый клиент разойдётся с новым.
    """

    def __init__(self, main_store: Any, state_storage_controller: Any) -> None:
        self._main_store = main_store
        self._state_storage_controller = state_storage_controller
        # Per-user кэш результата, требуемый design doc секция 3 ("Список
        # hidden-комнат юзера кэшируется per-user с инвалидацией на персист
        # com.liza.chat.topology") — без него /sync делает 1-2 запроса на
        # комнату КАЖДЫЙ раз для КАЖДОГО негейченного устройства. Инвалидация
        # — явный invalidate_user() из хука on_new_event персиста топологии
        # (см. ChatTopologySyncGateModule._on_new_event), не TTL: TTL дал бы
        # окно, где комнату показали/скрыли, а клиент узнал об этом с
        # задержкой вместо немедленно на следующий персист.
        self._cache: dict[str, frozenset] = {}

    def invalidate_user(self, user_id: str) -> None:
        self._cache.pop(user_id, None)

    async def get_hidden_room_ids_for_user(self, user_id: str) -> frozenset:
        cached = self._cache.get(user_id)
        if cached is not None:
            return cached

        room_ids = await self._main_store.get_rooms_for_user(user_id)
        hidden = set()
        for room_id in room_ids:
            state = await self._state_storage_controller.get_current_state_event(
                room_id, "com.liza.chat.topology", ""
            )
            if state is not None:
                if state.content.get("hidden") is True:
                    hidden.add(room_id)
                continue

            # Нет topology state вообще — legacy-дефолт по creation_content.
            create_event = await self._state_storage_controller.get_current_state_event(
                room_id, "m.room.create", ""
            )
            if create_event is None:
                continue
            creation_content = create_event.content
            if (
                creation_content.get("com.liza.stories") is True
                or creation_content.get("com.liza.chat.type") == "stories"
            ):
                hidden.add(room_id)

        result = frozenset(hidden)
        self._cache[user_id] = result
        return result


class ForcedFullStateMarkers:
    """Per-device маркер: после первого sync с этим устройством после
    прохождения gate — следующий sync должен отдать hidden-комнаты с
    full_state=True (по аналогии с forced_newly_joined_room_ids для
    partial-state rooms, но это отдельный стрим — не путать с ним)."""

    _SCHEMA = (
        """
        CREATE TABLE IF NOT EXISTS chat_topology_forced_full_state (
            device_id TEXT PRIMARY KEY
        )
        """,
    )

    def __init__(self, db_pool: Any) -> None:
        self._db = db_pool

    async def ensure_schema(self) -> None:
        def _create(txn: Any) -> None:
            for stmt in self._SCHEMA:
                txn.execute(stmt)

        await self._db.runInteraction("chat_topology_forced_full_state_schema", _create)

    async def mark(self, device_id: str) -> None:
        def _mark(txn: Any) -> None:
            txn.execute(
                "INSERT INTO chat_topology_forced_full_state (device_id) "
                "VALUES (?) ON CONFLICT (device_id) DO NOTHING",
                (device_id,),
            )

        await self._db.runInteraction("chat_topology_forced_full_state_mark", _mark)

    async def consume(self, device_id: str) -> bool:
        """Возвращает True и удаляет маркер, если он был выставлен."""

        def _consume(txn: Any) -> bool:
            txn.execute(
                "SELECT 1 FROM chat_topology_forced_full_state WHERE device_id = ?",
                (device_id,),
            )
            found = txn.fetchone() is not None
            if found:
                txn.execute(
                    "DELETE FROM chat_topology_forced_full_state WHERE device_id = ?",
                    (device_id,),
                )
            return found

        return await self._db.runInteraction("chat_topology_forced_full_state_consume", _consume)
