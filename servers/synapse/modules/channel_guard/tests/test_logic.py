import asyncio
import unittest

from synapse.api.errors import SynapseError

from synapse_modules.channel_guard._logic import (
    is_channel_creation,
    role_may_create_channel,
)


def _run(coro):
    return asyncio.run(coro)


def test_is_channel_creation_true():
    assert is_channel_creation(
        {"creation_content": {"com.liza.chat.type": "channel"}}
    )


def test_is_channel_creation_false_for_space():
    assert not is_channel_creation({"creation_content": {"type": "m.space"}})


def test_is_channel_creation_false_when_no_creation_content():
    assert not is_channel_creation({})


def test_role_may_create_channel_admin():
    assert role_may_create_channel("admin")


def test_role_may_create_channel_moderator():
    assert role_may_create_channel("moderator")


def test_role_may_create_channel_user_denied():
    assert not role_may_create_channel("user")


def test_role_may_create_channel_unknown_denied():
    assert not role_may_create_channel("developer")


class _FakeAccountData:
    def __init__(self, roles):
        self._roles = roles

    async def get_global(self, user_id, data_type):
        assert data_type == "com.liza.user_role"
        role = self._roles.get(user_id)
        return {"role": role} if role else None


class _FakeApi:
    """Fake ModuleApi: конструктор модуля вызывает register_third_party_rules_callbacks,
    поэтому fake обязан его иметь (иначе __init__ упадёт)."""

    def __init__(self, roles):
        self.account_data_manager = _FakeAccountData(roles)
        self.registered = {}

    def register_third_party_rules_callbacks(self, **callbacks):
        self.registered.update(callbacks)


class _FakeUser:
    def __init__(self, user_id):
        self._id = user_id

    def to_string(self):
        return self._id


class _FakeRequester:
    def __init__(self, user_id):
        self.user = _FakeUser(user_id)


def _channel_config():
    return {"creation_content": {"com.liza.chat.type": "channel"}}


class ChannelGuardModuleTestCase(unittest.TestCase):
    def test_moderator_may_create_channel(self):
        from synapse_modules.channel_guard import ChannelGuardModule

        module = ChannelGuardModule({}, _FakeApi({"@m:h": "moderator"}))
        # Не должно бросить исключение.
        _run(
            module._on_create_room(
                _FakeRequester("@m:h"), _channel_config(), False
            )
        )

    def test_user_may_not_create_channel(self):
        from synapse_modules.channel_guard import ChannelGuardModule

        module = ChannelGuardModule({}, _FakeApi({"@u:h": "user"}))
        with self.assertRaises(SynapseError):
            _run(
                module._on_create_room(
                    _FakeRequester("@u:h"), _channel_config(), False
                )
            )

    def test_non_channel_create_is_ignored(self):
        from synapse_modules.channel_guard import ChannelGuardModule

        module = ChannelGuardModule({}, _FakeApi({"@u:h": "user"}))
        # Обычная группа (не канал) — гейт не применяется даже к роли user.
        _run(
            module._on_create_room(
                _FakeRequester("@u:h"), {"creation_content": {}}, False
            )
        )

    def test_server_admin_bypasses_role_gate(self):
        from synapse_modules.channel_guard import ChannelGuardModule

        module = ChannelGuardModule({}, _FakeApi({"@a:h": "user"}))
        # is_requester_admin=True — серверный админ Synapse всегда может.
        _run(
            module._on_create_room(
                _FakeRequester("@a:h"), _channel_config(), True
            )
        )


def test_mark_channel_room_type_sets_type():
    from synapse_modules.channel_guard._logic import (
        LIZA_CHANNEL_ROOM_TYPE,
        mark_channel_room_type,
    )

    config = {"creation_content": {"com.liza.chat.type": "channel"}}
    assert mark_channel_room_type(config) is True
    assert config["creation_content"]["type"] == LIZA_CHANNEL_ROOM_TYPE


def test_mark_channel_room_type_ignores_non_channel():
    from synapse_modules.channel_guard._logic import mark_channel_room_type

    config = {"creation_content": {"com.liza.chat.type": "stories"}}
    assert mark_channel_room_type(config) is False
    assert "type" not in config["creation_content"]


def test_mark_channel_room_type_ignores_channel_discussion():
    """channel_discussion — отдельный тип, каналом в каталоге он не является."""
    from synapse_modules.channel_guard._logic import mark_channel_room_type

    config = {"creation_content": {"com.liza.chat.type": "channel_discussion"}}
    assert mark_channel_room_type(config) is False
    assert "type" not in config["creation_content"]


def test_mark_channel_room_type_does_not_overwrite_explicit_type():
    from synapse_modules.channel_guard._logic import mark_channel_room_type

    config = {
        "creation_content": {
            "com.liza.chat.type": "channel",
            "type": "m.space",
        }
    }
    assert mark_channel_room_type(config) is False
    assert config["creation_content"]["type"] == "m.space"


if __name__ == "__main__":
    unittest.main()
