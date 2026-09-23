import asyncio
import json
import sqlite3
import sys
import types

from synapse_modules.chat_topology_sync_gate.scripts.backfill_hidden import (
    _load_admin_token,
    _make_send_topology_state,
    find_legacy_stories_rooms,
    needs_backfill,
    run_backfill,
)


class _FakeRow:
    def __init__(self, room_id, has_topology_state):
        self.room_id = room_id
        self.has_topology_state = has_topology_state


def test_needs_backfill_true_when_no_topology_state():
    row = _FakeRow("!a:test", has_topology_state=False)
    assert needs_backfill(row) is True


def test_needs_backfill_false_when_topology_state_exists():
    row = _FakeRow("!a:test", has_topology_state=True)
    assert needs_backfill(row) is False


def test_run_backfill_dry_run_does_not_send_events():
    sent = []

    async def fake_send_state(room_id, sender):
        sent.append(room_id)

    rooms = [_FakeRow("!a:test", False), _FakeRow("!b:test", True)]
    asyncio.run(
        run_backfill(
            rooms=rooms,
            send_topology_state=fake_send_state,
            system_user_id="@system:test",
            dry_run=True,
        )
    )
    assert sent == []


def test_run_backfill_sends_only_for_rooms_needing_it():
    sent = []

    async def fake_send_state(room_id, sender):
        sent.append(room_id)

    rooms = [_FakeRow("!a:test", False), _FakeRow("!b:test", True)]
    asyncio.run(
        run_backfill(
            rooms=rooms,
            send_topology_state=fake_send_state,
            system_user_id="@system:test",
            dry_run=False,
        )
    )
    assert sent == ["!a:test"]


def test_run_backfill_idempotent_on_second_run():
    sent = []

    async def fake_send_state(room_id, sender):
        sent.append(room_id)

    rooms_first_run = [_FakeRow("!a:test", False)]
    asyncio.run(
        run_backfill(
            rooms=rooms_first_run,
            send_topology_state=fake_send_state,
            system_user_id="@system:test",
            dry_run=False,
        )
    )
    # На втором прогоне предполагается, что find_legacy_stories_rooms
    # для !a:test теперь вернёт has_topology_state=True (т.к. событие
    # отправлено) — здесь симулируем это явно
    rooms_second_run = [_FakeRow("!a:test", True)]
    asyncio.run(
        run_backfill(
            rooms=rooms_second_run,
            send_topology_state=fake_send_state,
            system_user_id="@system:test",
            dry_run=False,
        )
    )
    assert sent == ["!a:test"]  # не повторилось


class _FakeSqliteEngine:
    def __init__(self):
        self.conn = sqlite3.connect(":memory:")
        self.conn.row_factory = sqlite3.Row
        self.conn.executescript(
            """
            CREATE TABLE current_state_events (
                room_id TEXT,
                type TEXT,
                state_key TEXT,
                event_id TEXT
            );
            CREATE TABLE event_json (
                event_id TEXT,
                json TEXT
            );
            """
        )

    @property
    def is_postgres(self):
        return False


class _FakeDbPool:
    """Мини-реализация db_pool.runInteraction поверх in-memory sqlite,
    по образцу паттерна runInteraction из user_roles/_catalog.py
    (см. tests/test_storage.py этого же модуля)."""

    def __init__(self):
        self.engine = _FakeSqliteEngine()

    async def runInteraction(self, desc, txn_func, *args):
        cur = self.engine.conn.cursor()
        result = txn_func(cur, *args)
        self.engine.conn.commit()
        return result


def _insert_room_create(db_pool, room_id, event_id, creation_content_json):
    conn = db_pool.engine.conn
    conn.execute(
        "INSERT INTO current_state_events (room_id, type, state_key, event_id) "
        "VALUES (?, 'm.room.create', '', ?)",
        (room_id, event_id),
    )
    conn.execute(
        "INSERT INTO event_json (event_id, json) VALUES (?, ?)",
        (event_id, creation_content_json),
    )
    conn.commit()


def _insert_topology_state(db_pool, room_id, event_id):
    conn = db_pool.engine.conn
    conn.execute(
        "INSERT INTO current_state_events (room_id, type, state_key, event_id) "
        "VALUES (?, 'com.liza.chat.topology', '', ?)",
        (room_id, event_id),
    )
    conn.commit()


def _compact_json(content: dict) -> str:
    """Компактная сериализация полного тела события (с обёрткой content),
    без пробелов - как реальный Synapse (synapse/util/json.py:
    separators=(",", ":"), event_json.json хранит {"content": {...}, ...},
    см. events.py:_store_event_txn). Тест обязан бить по реальному формату
    данных, не по формату, подогнанному под запрос."""
    return json.dumps(
        {
            "type": "m.room.create",
            "content": {"creator": "@system:test", **content},
        },
        separators=(",", ":"),
    )


def test_find_legacy_stories_rooms_finds_stories_room_without_topology_state():
    db_pool = _FakeDbPool()
    _insert_room_create(
        db_pool,
        "!a:test",
        "$create_a",
        _compact_json({"com.liza.stories": True}),
    )

    rooms = asyncio.run(find_legacy_stories_rooms(db_pool))

    assert len(rooms) == 1
    assert rooms[0].room_id == "!a:test"
    assert rooms[0].has_topology_state is False


def test_find_legacy_stories_rooms_marks_existing_topology_state():
    db_pool = _FakeDbPool()
    _insert_room_create(
        db_pool,
        "!a:test",
        "$create_a",
        _compact_json({"com.liza.stories": True}),
    )
    _insert_topology_state(db_pool, "!a:test", "$topology_a")

    rooms = asyncio.run(find_legacy_stories_rooms(db_pool))

    assert len(rooms) == 1
    assert rooms[0].room_id == "!a:test"
    assert rooms[0].has_topology_state is True


def test_find_legacy_stories_rooms_ignores_non_stories_rooms():
    db_pool = _FakeDbPool()
    _insert_room_create(
        db_pool,
        "!a:test",
        "$create_a",
        _compact_json({}),
    )

    rooms = asyncio.run(find_legacy_stories_rooms(db_pool))

    assert rooms == []


def test_find_legacy_stories_rooms_finds_new_type_key_too():
    db_pool = _FakeDbPool()
    _insert_room_create(
        db_pool,
        "!a:test",
        "$create_a",
        _compact_json({"com.liza.chat.type": "stories"}),
    )

    rooms = asyncio.run(find_legacy_stories_rooms(db_pool))

    assert len(rooms) == 1
    assert rooms[0].room_id == "!a:test"


class _FakeResponse:
    def __init__(self, status_code=200, payload=None):
        self.status_code = status_code
        self._payload = payload or {}

    def json(self):
        return self._payload

    def raise_for_status(self):
        if self.status_code >= 400:
            raise AssertionError(f"HTTP {self.status_code}")


class _FakeRequests:
    """Фейк requests: пишет все вызовы, отдаёт заранее заданный PL на GET."""

    def __init__(self, pl_payload=None, pl_status=200):
        self.calls = []
        self._pl_payload = pl_payload if pl_payload is not None else {}
        self._pl_status = pl_status

    def post(self, url, headers=None, json=None, timeout=None):
        self.calls.append(("POST", url, json))
        return _FakeResponse(200)

    def get(self, url, headers=None, timeout=None):
        self.calls.append(("GET", url, None))
        return _FakeResponse(self._pl_status, self._pl_payload)

    def put(self, url, headers=None, json=None, timeout=None):
        self.calls.append(("PUT", url, json))
        return _FakeResponse(200)


def _with_fake_requests(fake):
    """Подменяет модуль requests в sys.modules (import — внутри фабрики)."""
    module = types.ModuleType("requests")
    module.post = fake.post
    module.get = fake.get
    module.put = fake.put
    sys.modules["requests"] = module


def test_send_topology_state_makes_admin_gate_and_hidden():
    fake = _FakeRequests(pl_payload={"users": {"@admin:test": 100}, "events": {}})
    _with_fake_requests(fake)

    send = _make_send_topology_state("http://localhost:8008", "syt_token")
    asyncio.run(send("!room:test", "@admin:test"))

    methods = [c[0] for c in fake.calls]
    # make_room_admin -> client join -> GET power_levels -> PUT power_levels -> PUT topology
    assert methods == ["POST", "POST", "GET", "PUT", "PUT"]

    make_admin_url, make_admin_body = fake.calls[0][1], fake.calls[0][2]
    assert make_admin_url.endswith("/make_room_admin")
    assert make_admin_body == {}  # PL наделяем владельцу токена, без user_id

    join_url = fake.calls[1][1]
    assert join_url.endswith("/join/%21room%3Atest")

    pl_put_body = fake.calls[3][2]
    assert pl_put_body["events"]["com.liza.chat.topology"] == 100
    # существующие users не затёрты
    assert pl_put_body["users"] == {"@admin:test": 100}

    topology_url, topology_body = fake.calls[4][1], fake.calls[4][2]
    assert topology_url.endswith("/state/com.liza.chat.topology/")
    assert topology_body == {"hidden": True}


def test_send_topology_state_skips_pl_put_when_already_gated():
    # PL-гейт уже стоит -> второй PUT (power_levels) не нужен.
    fake = _FakeRequests(
        pl_payload={"events": {"com.liza.chat.topology": 100}}
    )
    _with_fake_requests(fake)

    send = _make_send_topology_state("http://localhost:8008", "syt_token")
    asyncio.run(send("!room:test", "@admin:test"))

    methods = [c[0] for c in fake.calls]
    # make_room_admin -> client join -> GET power_levels -> (PUT пропущен) -> PUT topology
    assert methods == ["POST", "POST", "GET", "PUT"]
    assert fake.calls[3][1].endswith("/state/com.liza.chat.topology/")


def test_load_admin_token_explicit_wins(tmp_path):
    assert _load_admin_token("explicit_token") == "explicit_token"


def test_load_admin_token_from_file(tmp_path, monkeypatch):
    import synapse_modules.chat_topology_sync_gate.scripts.backfill_hidden as mod

    token_file = tmp_path / "admin.json"
    token_file.write_text(json.dumps({"access_token": "syt_from_file"}))

    orig_open = open

    def fake_open(path, *a, **kw):
        if path == "/data/admin.json":
            return orig_open(token_file, *a, **kw)
        return orig_open(path, *a, **kw)

    monkeypatch.setattr(mod, "open", fake_open, raising=False)
    assert _load_admin_token(None) == "syt_from_file"
