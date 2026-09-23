import asyncio

from synapse_modules.chat_topology_sync_gate import ChatTopologySyncGateModule


class _FakeDbPool:
    def __init__(self):
        self.engine = type("E", (), {"is_postgres": False})()
        self._rows = {}

    async def runInteraction(self, desc, txn_func, *args):
        # Минимальная заглушка: тестируем только что parse_config/init не падают,
        # детальное поведение storage покрыто test_storage.py
        class _Cur:
            def execute(self, *a, **kw):
                pass

            def fetchone(self):
                return None

        return txn_func(_Cur(), *args)


class _FakeHomeServer:
    """Реальный ModuleApi не даёт публичного get_datastores() - только
    HomeServer его имеет, а ModuleApi хранит ссылку на него в приватном
    _hs (см. модуль __init__.py: hs = getattr(api, "_hs", None)). Этот фейк
    моделирует именно HomeServer, а не ModuleApi, чтобы тест ловил
    расхождения вроде api.get_datastores() вместо api._hs.get_datastores()."""

    def __init__(self, db_pool):
        self._db_pool = db_pool
        self.hostname = "test"

    def get_datastores(self):
        outer = self

        class _Stores:
            class main:
                db_pool = outer._db_pool

        return _Stores()

    def get_storage_controllers(self):
        class _Controllers:
            class state:
                pass

        return _Controllers()


class _FakeApi:
    def __init__(self):
        self.registered_servlets = []
        self._datastores_main_db_pool = _FakeDbPool()
        self._hs = _FakeHomeServer(self._datastores_main_db_pool)
        self._registered_callbacks = {}

    def register_web_resource(self, path, resource):
        self.registered_servlets.append((path, resource))

    def register_third_party_rules_callbacks(self, **kwargs):
        self._registered_callbacks.update(kwargs)

    def run_as_background_process(self, name, coro, *args):
        return asyncio.run(coro(*args))


def test_parse_config_defaults():
    config = ChatTopologySyncGateModule.parse_config({})
    assert config["enabled"] is False
    assert config["version_gate_base_url"] is None


def test_parse_config_explicit():
    config = ChatTopologySyncGateModule.parse_config(
        {"enabled": True, "version_gate_base_url": "https://version.test"}
    )
    assert config["enabled"] is True
    assert config["version_gate_base_url"] == "https://version.test"


def test_module_init_does_not_raise():
    api = _FakeApi()
    config = ChatTopologySyncGateModule.parse_config(
        {"enabled": False, "version_gate_base_url": "https://version.test"}
    )
    module = ChatTopologySyncGateModule(config, api)
    assert module.enabled is False


def test_module_registers_on_new_event_callback():
    api = _FakeApi()
    config = ChatTopologySyncGateModule.parse_config({})
    ChatTopologySyncGateModule(config, api)
    assert "on_new_event" in api._registered_callbacks


def test_on_new_event_invalidates_join_members_for_topology_event():
    from types import SimpleNamespace

    api = _FakeApi()
    config = ChatTopologySyncGateModule.parse_config({})
    module = ChatTopologySyncGateModule(config, api)

    invalidated = []
    module.hidden_rooms.invalidate_user = invalidated.append

    event = SimpleNamespace(type="com.liza.chat.topology")
    state_events = {
        ("m.room.member", "@alice:test"): SimpleNamespace(content={"membership": "join"}),
        ("m.room.member", "@bob:test"): SimpleNamespace(content={"membership": "leave"}),
        ("m.room.create", ""): SimpleNamespace(content={}),
    }
    asyncio.run(module._on_new_event(event, state_events))

    assert invalidated == ["@alice:test"]


def test_on_new_event_ignores_non_topology_events():
    from types import SimpleNamespace

    api = _FakeApi()
    config = ChatTopologySyncGateModule.parse_config({})
    module = ChatTopologySyncGateModule(config, api)

    invalidated = []
    module.hidden_rooms.invalidate_user = invalidated.append

    event = SimpleNamespace(type="m.room.message")
    state_events = {
        ("m.room.member", "@alice:test"): SimpleNamespace(content={"membership": "join"}),
    }
    asyncio.run(module._on_new_event(event, state_events))

    assert invalidated == []
