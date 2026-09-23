import asyncio
import sqlite3
from types import SimpleNamespace

import pytest

from synapse_modules.chat_topology_sync_gate._storage import (
    DeviceCapabilitiesStore,
    ForcedFullStateMarkers,
    HiddenRoomsLookup,
)


class _FakeSqliteEngine:
    def __init__(self):
        self.conn = sqlite3.connect(":memory:")
        self.conn.row_factory = sqlite3.Row

    @property
    def is_postgres(self):
        return False


class _FakeDbPool:
    """Мини-реализация db_pool.runInteraction поверх in-memory sqlite,
    по образцу паттерна runInteraction из user_roles/_catalog.py."""

    def __init__(self):
        self.engine = _FakeSqliteEngine()

    async def runInteraction(self, desc, txn_func, *args):
        cur = self.engine.conn.cursor()
        result = txn_func(cur, *args)
        self.engine.conn.commit()
        return result


def _make_store():
    return DeviceCapabilitiesStore(_FakeDbPool())


def test_ensure_schema_idempotent():
    store = _make_store()
    asyncio.run(store.ensure_schema())
    asyncio.run(store.ensure_schema())  # не должно падать при повторном вызове


def test_upsert_then_get():
    store = _make_store()
    asyncio.run(store.ensure_schema())
    asyncio.run(
        store.upsert_capability(
            device_id="DEVICE1", user_id="@alice:local.test", platform="android", build=3675
        )
    )
    result = asyncio.run(store.get_capability("DEVICE1"))
    assert result == {"platform": "android", "build": 3675}


def test_get_capability_missing_returns_none():
    store = _make_store()
    asyncio.run(store.ensure_schema())
    assert asyncio.run(store.get_capability("UNKNOWN")) is None


def test_upsert_overwrites_previous_build():
    store = _make_store()
    asyncio.run(store.ensure_schema())
    asyncio.run(
        store.upsert_capability(
            device_id="DEVICE1", user_id="@alice:local.test", platform="android", build=3674
        )
    )
    asyncio.run(
        store.upsert_capability(
            device_id="DEVICE1", user_id="@alice:local.test", platform="android", build=3675
        )
    )
    result = asyncio.run(store.get_capability("DEVICE1"))
    assert result["build"] == 3675


def test_upsert_returns_true_when_build_increased():
    store = _make_store()
    asyncio.run(store.ensure_schema())
    asyncio.run(
        store.upsert_capability(
            device_id="DEVICE1", user_id="@alice:local.test", platform="android", build=3674
        )
    )
    changed = asyncio.run(
        store.upsert_capability(
            device_id="DEVICE1", user_id="@alice:local.test", platform="android", build=3675
        )
    )
    assert changed is True


def test_upsert_returns_false_when_build_unchanged():
    store = _make_store()
    asyncio.run(store.ensure_schema())
    asyncio.run(
        store.upsert_capability(
            device_id="DEVICE1", user_id="@alice:local.test", platform="android", build=3675
        )
    )
    changed = asyncio.run(
        store.upsert_capability(
            device_id="DEVICE1", user_id="@alice:local.test", platform="android", build=3675
        )
    )
    assert changed is False


def _make_markers():
    return ForcedFullStateMarkers(_FakeDbPool())


def test_forced_full_state_consume_returns_false_when_not_marked():
    markers = _make_markers()
    asyncio.run(markers.ensure_schema())
    assert asyncio.run(markers.consume("DEVICE1")) is False


def test_forced_full_state_mark_then_consume_returns_true_once():
    markers = _make_markers()
    asyncio.run(markers.ensure_schema())
    asyncio.run(markers.mark("DEVICE1"))

    assert asyncio.run(markers.consume("DEVICE1")) is True
    # Маркер одноразовый: повторный consume должен вернуть False
    assert asyncio.run(markers.consume("DEVICE1")) is False


def test_forced_full_state_mark_idempotent():
    markers = _make_markers()
    asyncio.run(markers.ensure_schema())
    asyncio.run(markers.mark("DEVICE1"))
    asyncio.run(markers.mark("DEVICE1"))  # повторная отметка не должна падать

    assert asyncio.run(markers.consume("DEVICE1")) is True


def test_forced_full_state_ensure_schema_idempotent():
    markers = _make_markers()
    asyncio.run(markers.ensure_schema())
    asyncio.run(markers.ensure_schema())


class _FakeStateStorageController:
    """Имитирует synapse.storage.controllers.state.StateStorageController
    в части get_current_state_event(room_id, event_type, state_key)."""

    def __init__(self, state_by_room):
        self._state_by_room = state_by_room

    async def get_current_state_event(self, room_id, event_type, state_key):
        room_state = self._state_by_room.get(room_id, {})
        return room_state.get((event_type, state_key))


class _FakeMainStoreForRooms:
    def __init__(self, room_ids):
        self._room_ids = frozenset(room_ids)

    async def get_rooms_for_user(self, user_id):
        return self._room_ids


def _make_event(content):
    return SimpleNamespace(content=content)


def test_get_hidden_room_ids_for_user_filters_only_hidden():
    main_store = _FakeMainStoreForRooms(["!hidden:test", "!normal:test", "!no_topology:test"])
    state = _FakeStateStorageController(
        {
            "!hidden:test": {
                ("com.liza.chat.topology", ""): _make_event({"hidden": True})
            },
            "!normal:test": {
                ("com.liza.chat.topology", ""): _make_event({"hidden": False})
            },
            # "!no_topology:test" намеренно без состояния com.liza.chat.topology
        }
    )
    lookup = HiddenRoomsLookup(main_store, state)

    result = asyncio.run(lookup.get_hidden_room_ids_for_user("@alice:local.test"))

    assert result == frozenset({"!hidden:test"})


def test_get_hidden_room_ids_for_user_no_hidden_rooms_returns_empty():
    main_store = _FakeMainStoreForRooms(["!normal:test"])
    state = _FakeStateStorageController(
        {
            "!normal:test": {
                ("com.liza.chat.topology", ""): _make_event({"hidden": False})
            }
        }
    )
    lookup = HiddenRoomsLookup(main_store, state)

    result = asyncio.run(lookup.get_hidden_room_ids_for_user("@alice:local.test"))

    assert result == frozenset()


def test_get_hidden_room_ids_for_user_no_rooms_returns_empty():
    main_store = _FakeMainStoreForRooms([])
    state = _FakeStateStorageController({})
    lookup = HiddenRoomsLookup(main_store, state)

    result = asyncio.run(lookup.get_hidden_room_ids_for_user("@alice:local.test"))

    assert result == frozenset()


def test_get_hidden_room_ids_for_user_legacy_com_liza_stories_without_topology_state():
    """Комната от stories_membership (Task 15): creation_content содержит
    только легаси-ключ com.liza.stories=true, topology state вовсе нет.
    Должна попасть в hidden по умолчанию (зеркалит isHiddenChat на клиенте)."""
    main_store = _FakeMainStoreForRooms(["!legacy_stories:test"])
    state = _FakeStateStorageController(
        {
            "!legacy_stories:test": {
                ("m.room.create", ""): _make_event({"com.liza.stories": True}),
            }
        }
    )
    lookup = HiddenRoomsLookup(main_store, state)

    result = asyncio.run(lookup.get_hidden_room_ids_for_user("@alice:local.test"))

    assert result == frozenset({"!legacy_stories:test"})


def test_get_hidden_room_ids_for_user_legacy_com_liza_chat_type_stories_without_topology_state():
    """Тот же legacy-дефолт, но через новый ключ com.liza.chat.type='stories'
    без topology state (например, комната создана до бэкфилла Task 13)."""
    main_store = _FakeMainStoreForRooms(["!legacy_chat_type:test"])
    state = _FakeStateStorageController(
        {
            "!legacy_chat_type:test": {
                ("m.room.create", ""): _make_event({"com.liza.chat.type": "stories"}),
            }
        }
    )
    lookup = HiddenRoomsLookup(main_store, state)

    result = asyncio.run(lookup.get_hidden_room_ids_for_user("@alice:local.test"))

    assert result == frozenset({"!legacy_chat_type:test"})


def test_get_hidden_room_ids_for_user_ordinary_room_without_topology_state_stays_visible():
    """Обычная комната (не сторис) без topology state НЕ должна стать hidden
    только из-за отсутствия state - legacy-дефолт применяется исключительно
    к com.liza.stories/com.liza.chat.type='stories'."""
    main_store = _FakeMainStoreForRooms(["!ordinary:test"])
    state = _FakeStateStorageController(
        {
            "!ordinary:test": {
                ("m.room.create", ""): _make_event({}),
            }
        }
    )
    lookup = HiddenRoomsLookup(main_store, state)

    result = asyncio.run(lookup.get_hidden_room_ids_for_user("@alice:local.test"))

    assert result == frozenset()


def test_get_hidden_room_ids_for_user_no_create_event_stays_visible():
    """Пограничный случай: create event недоступен (не должно падать)."""
    main_store = _FakeMainStoreForRooms(["!no_create:test"])
    state = _FakeStateStorageController({})
    lookup = HiddenRoomsLookup(main_store, state)

    result = asyncio.run(lookup.get_hidden_room_ids_for_user("@alice:local.test"))

    assert result == frozenset()


class _CountingStateStorageController(_FakeStateStorageController):
    """Считает вызовы get_current_state_event - используется, чтобы доказать
    что второй вызов get_hidden_room_ids_for_user реально идёт из кэша, а
    не повторяет запросы к state storage (design doc секция 3: per-user
    кэш, обязателен на hot-path /sync)."""

    def __init__(self, state_by_room):
        super().__init__(state_by_room)
        self.call_count = 0

    async def get_current_state_event(self, room_id, event_type, state_key):
        self.call_count += 1
        return await super().get_current_state_event(room_id, event_type, state_key)


def test_get_hidden_room_ids_for_user_second_call_is_cached():
    main_store = _FakeMainStoreForRooms(["!hidden:test"])
    state = _CountingStateStorageController(
        {
            "!hidden:test": {
                ("com.liza.chat.topology", ""): _make_event({"hidden": True})
            }
        }
    )
    lookup = HiddenRoomsLookup(main_store, state)

    asyncio.run(lookup.get_hidden_room_ids_for_user("@alice:local.test"))
    calls_after_first = state.call_count
    asyncio.run(lookup.get_hidden_room_ids_for_user("@alice:local.test"))

    assert calls_after_first > 0
    assert state.call_count == calls_after_first  # второй вызов не тронул state storage


def test_get_hidden_room_ids_for_user_different_users_cached_independently():
    main_store = _FakeMainStoreForRooms(["!hidden:test"])
    state = _CountingStateStorageController(
        {
            "!hidden:test": {
                ("com.liza.chat.topology", ""): _make_event({"hidden": True})
            }
        }
    )
    lookup = HiddenRoomsLookup(main_store, state)

    asyncio.run(lookup.get_hidden_room_ids_for_user("@alice:local.test"))
    calls_after_alice = state.call_count
    asyncio.run(lookup.get_hidden_room_ids_for_user("@bob:local.test"))

    assert state.call_count > calls_after_alice  # bob не должен взять кэш alice


def test_invalidate_user_forces_recompute_on_next_call():
    main_store = _FakeMainStoreForRooms(["!hidden:test"])
    state = _CountingStateStorageController(
        {
            "!hidden:test": {
                ("com.liza.chat.topology", ""): _make_event({"hidden": True})
            }
        }
    )
    lookup = HiddenRoomsLookup(main_store, state)

    asyncio.run(lookup.get_hidden_room_ids_for_user("@alice:local.test"))
    calls_after_first = state.call_count

    lookup.invalidate_user("@alice:local.test")
    asyncio.run(lookup.get_hidden_room_ids_for_user("@alice:local.test"))

    assert state.call_count > calls_after_first  # инвалидация форсирует пересчёт


def test_invalidate_user_reflects_state_change():
    """После invalidate_user() кэш должен отдать НОВОЕ значение hidden, а не
    старое закэшированное - иначе backfill (Task 13) не смог бы реально
    показать/скрыть комнату до истечения несуществующего TTL."""
    room_state = {
        "!room:test": {("com.liza.chat.topology", ""): _make_event({"hidden": True})}
    }
    main_store = _FakeMainStoreForRooms(["!room:test"])
    state = _FakeStateStorageController(room_state)
    lookup = HiddenRoomsLookup(main_store, state)

    first = asyncio.run(lookup.get_hidden_room_ids_for_user("@alice:local.test"))
    assert first == frozenset({"!room:test"})

    room_state["!room:test"][("com.liza.chat.topology", "")] = _make_event(
        {"hidden": False}
    )
    lookup.invalidate_user("@alice:local.test")
    second = asyncio.run(lookup.get_hidden_room_ids_for_user("@alice:local.test"))

    assert second == frozenset()
