"""Интеграционные тесты ChannelStoriesModule (раздача историй по членству).

Async-стиль: pytest-asyncio в servers/synapse/src не установлен (урок из
плана 1) — используем unittest.TestCase + asyncio.run(...), как в
channel_sync/tests/test_module.py.

Модуль сконструирован через ChannelStoriesModule.__new__ + ручную подстановку
_api/_state/_store/_main_store, чтобы не собирать реальный api._hs (минуем
__init__, который трогает hs.get_storage_controllers()/get_datastores()).
"""

import asyncio
import unittest

from synapse_modules.channel_stories import ChannelStoriesModule


class _FakeEvent:
    def __init__(
        self,
        event_type="m.room.member",
        content=None,
        room_id="!chan:h",
        sender="@a:h",
        event_id="$ev",
        state_key=None,
    ):
        self.type = event_type
        self.content = content or {}
        self.room_id = room_id
        self.sender = sender
        self.event_id = event_id
        self.state_key = state_key


class _FakeState:
    """Фейковый StateStorageController: m.room.create с chat_type + sender
    настраиваются по room_id (канал и stories-комната - разные комнаты, у
    каждой свой creator)."""

    def __init__(self, room_chat_types=None, room_creators=None):
        self._room_chat_types = room_chat_types or {}
        self._room_creators = room_creators or {}

    async def get_current_state_event(self, room_id, ev_type, state_key):
        if ev_type != "m.room.create":
            return None
        if room_id not in self._room_chat_types and room_id not in self._room_creators:
            return None
        content = {"com.liza.chat.type": self._room_chat_types.get(room_id, "channel")}
        sender = self._room_creators.get(room_id, "@owner:h")
        return _FakeEvent(content=content, sender=sender)


class _FakeStore:
    """Фейковый ChannelStoriesStore в памяти: channel_id -> stories_room_id."""

    def __init__(self, mapping=None):
        self._m = dict(mapping or {})
        self.put_calls = []  # (channel_id, stories_room_id) - все вызовы put_stories_room

    async def get_stories_room(self, channel_id):
        return self._m.get(channel_id)

    async def put_stories_room(self, channel_id, stories_room_id):
        self.put_calls.append((channel_id, stories_room_id))
        self._m.setdefault(channel_id, stories_room_id)

    async def ensure_schema(self):
        pass


class _FakeDbPool:
    def __init__(self, store):
        self._store = store

    async def simple_select_one_onecol(
        self, table, keyvalues, retcol, allow_none=False, desc=""
    ):
        for row in self._store.push_rules_added:
            if row[0] == keyvalues["user_name"] and row[1] == keyvalues["rule_id"]:
                return "existing-id"
        if allow_none:
            return None
        raise LookupError(f"no row in {table} for {keyvalues}")


class _FakeMainStore:
    def __init__(self, room_members=None):
        self.push_rules_added = []  # (user_id, rule_id, priority_class, conditions, actions)
        self.db_pool = _FakeDbPool(self)
        # room_id -> [user_id, ...] джойн-члены комнаты (см. get_users_in_room
        # в synapse/storage/databases/main/roommember.py - реальный сервер
        # берёт их из current_state_events WHERE membership='join').
        self._room_members = room_members or {}
        self.get_users_in_room_calls = []

    async def add_push_rule(
        self, user_id, rule_id, priority_class, conditions, actions,
        before=None, after=None,
    ):
        self.push_rules_added.append(
            (user_id, rule_id, priority_class, conditions, actions)
        )

    async def get_users_in_room(self, room_id):
        self.get_users_in_room_calls.append(room_id)
        return list(self._room_members.get(room_id, []))


class _FakeApi:
    def __init__(self, server_name="h"):
        self.server_name = server_name
        self.pending_background = []
        self.memberships = []  # (owner, member, room_id, action, remote_room_hosts)
        self.fail_invite = False
        self.account_data = {}  # user_id -> {"role": ...}

    def register_third_party_rules_callbacks(self, **cb):
        self.registered = cb

    def run_as_background_process(self, name, fn, *args):
        loop = asyncio.get_event_loop()
        if loop.is_running():
            self.pending_background.append(fn(*args))
            return
        loop.run_until_complete(fn(*args))

    def is_mine(self, user_id):
        return user_id.endswith(":" + self.server_name)

    async def update_room_membership(
        self, sender, target, room_id, action, remote_room_hosts=None
    ):
        if self.fail_invite and action == "invite":
            raise RuntimeError("boom")
        self.memberships.append((sender, target, room_id, action, remote_room_hosts))

    class _AccountDataManager:
        def __init__(self, outer):
            self._outer = outer

        async def get_global(self, user_id, key):
            return self._outer.account_data.get(user_id)

    @property
    def account_data_manager(self):
        return self._AccountDataManager(self)


def _make_module(
    room_chat_types=None, room_creators=None, stories_mapping=None, api=None,
    room_members=None,
):
    m = ChannelStoriesModule.__new__(ChannelStoriesModule)  # минуем __init__ (трогает _hs)
    api = api or _FakeApi()
    m._api = api
    m._state = _FakeState(room_chat_types, room_creators)
    m._store = _FakeStore(stories_mapping)
    m._main_store = _FakeMainStore(room_members)
    return m


def _member_event(room_id, state_key, membership="join", sender=None):
    return _FakeEvent(
        event_type="m.room.member",
        content={"membership": membership},
        room_id=room_id,
        sender=sender or state_key,
        event_id="$member",
        state_key=state_key,
    )


def _create_event(room_id, content, sender="@owner:h"):
    return _FakeEvent(
        event_type="m.room.create",
        content=content,
        room_id=room_id,
        sender=sender,
        event_id="$create",
        state_key="",
    )


def _run_on_new_event(m, event, state_events):
    """Прогоняет _on_new_event и синхронно дожидается фоновых корутин,
    накопленных в api.pending_background (см. _FakeApi.run_as_background_process),
    - симметрично channel_sync/tests/test_module.py."""
    asyncio.run(m._on_new_event(event, state_events))
    pending = m._api.pending_background
    m._api.pending_background = []
    for coro in pending:
        asyncio.run(coro)


class ChannelStoriesJoinTest(unittest.TestCase):
    def test_join_into_channel_invites_to_stories_room_after_mute(self):
        m = _make_module(
            room_chat_types={"!chan:h": "channel", "!stories:h": "stories"},
            room_creators={"!stories:h": "@owner:h"},
            stories_mapping={"!chan:h": "!stories:h"},
        )
        event = _member_event(room_id="!chan:h", state_key="@sub:h")
        _run_on_new_event(m, event, {})

        # mute перед invite
        self.assertEqual(len(m._main_store.push_rules_added), 1)
        muted_user, rule_id, *_ = m._main_store.push_rules_added[0]
        self.assertEqual(muted_user, "@sub:h")
        self.assertEqual(rule_id, "global/room/!stories:h")

        self.assertEqual(len(m._api.memberships), 1)
        owner, target, room_id, action, remote_hosts = m._api.memberships[0]
        self.assertEqual(owner, "@owner:h")
        self.assertEqual(target, "@sub:h")
        self.assertEqual(room_id, "!stories:h")
        self.assertEqual(action, "invite")
        self.assertIsNone(remote_hosts)

    def test_mute_happens_before_invite(self):
        """Доказательство порядка: если invite сломать (исключение), mute
        всё равно должен был успеть произойти ДО падения."""
        api = _FakeApi()
        api.fail_invite = True
        m = _make_module(
            room_chat_types={"!chan:h": "channel", "!stories:h": "stories"},
            room_creators={"!stories:h": "@owner:h"},
            stories_mapping={"!chan:h": "!stories:h"},
            api=api,
        )
        event = _member_event(room_id="!chan:h", state_key="@sub:h")
        _run_on_new_event(m, event, {})

        self.assertEqual(len(m._main_store.push_rules_added), 1)
        self.assertEqual(m._api.memberships, [])  # invite упал, но mute уже случился

    def test_federated_member_gets_remote_room_hosts_and_no_mute(self):
        m = _make_module(
            room_chat_types={"!chan:h": "channel", "!stories:h": "stories"},
            room_creators={"!stories:h": "@owner:h"},
            stories_mapping={"!chan:h": "!stories:h"},
        )
        event = _member_event(room_id="!chan:h", state_key="@sub:other.example")
        _run_on_new_event(m, event, {})

        self.assertEqual(m._main_store.push_rules_added, [])  # не мьютим удалённого
        self.assertEqual(len(m._api.memberships), 1)
        owner, target, room_id, action, remote_hosts = m._api.memberships[0]
        self.assertEqual(target, "@sub:other.example")
        self.assertEqual(remote_hosts, ["other.example"])

    def test_ai_bot_not_invited(self):
        m = _make_module(
            room_chat_types={"!chan:h": "channel", "!stories:h": "stories"},
            room_creators={"!stories:h": "@owner:h"},
            stories_mapping={"!chan:h": "!stories:h"},
        )
        event = _member_event(room_id="!chan:h", state_key="@liza:h")
        _run_on_new_event(m, event, {})

        self.assertEqual(m._api.memberships, [])
        self.assertEqual(m._main_store.push_rules_added, [])

    def test_ai_role_in_account_data_not_invited(self):
        api = _FakeApi()
        api.account_data["@bot:h"] = {"role": "ai"}
        m = _make_module(
            room_chat_types={"!chan:h": "channel", "!stories:h": "stories"},
            room_creators={"!stories:h": "@owner:h"},
            stories_mapping={"!chan:h": "!stories:h"},
            api=api,
        )
        event = _member_event(room_id="!chan:h", state_key="@bot:h")
        _run_on_new_event(m, event, {})

        self.assertEqual(m._api.memberships, [])

    def test_join_into_non_channel_room_ignored(self):
        m = _make_module(
            room_chat_types={"!dm:h": "dm"},
            stories_mapping={},
        )
        event = _member_event(room_id="!dm:h", state_key="@sub:h")
        _run_on_new_event(m, event, {})

        self.assertEqual(m._api.memberships, [])
        self.assertEqual(m._main_store.push_rules_added, [])

    def test_join_into_channel_without_stories_room_is_noop(self):
        """Истории у канала ещё не заведены (client создаёт лениво,
        Task 6) - хук не должен ничего делать."""
        m = _make_module(
            room_chat_types={"!chan:h": "channel"},
            stories_mapping={},  # get_stories_room -> None
        )
        event = _member_event(room_id="!chan:h", state_key="@sub:h")
        _run_on_new_event(m, event, {})

        self.assertEqual(m._api.memberships, [])
        self.assertEqual(m._main_store.push_rules_added, [])


class ChannelStoriesLeaveTest(unittest.TestCase):
    def test_leave_from_channel_kicks_from_stories_room(self):
        m = _make_module(
            room_chat_types={"!chan:h": "channel", "!stories:h": "stories"},
            room_creators={"!stories:h": "@owner:h"},
            stories_mapping={"!chan:h": "!stories:h"},
        )
        event = _member_event(room_id="!chan:h", state_key="@sub:h", membership="leave")
        _run_on_new_event(m, event, {})

        self.assertEqual(len(m._api.memberships), 1)
        owner, target, room_id, action, remote_hosts = m._api.memberships[0]
        self.assertEqual(owner, "@owner:h")
        self.assertEqual(target, "@sub:h")
        self.assertEqual(room_id, "!stories:h")
        self.assertEqual(action, "leave")

    def test_ban_from_channel_kicks_from_stories_room(self):
        m = _make_module(
            room_chat_types={"!chan:h": "channel", "!stories:h": "stories"},
            room_creators={"!stories:h": "@owner:h"},
            stories_mapping={"!chan:h": "!stories:h"},
        )
        event = _member_event(room_id="!chan:h", state_key="@sub:h", membership="ban")
        _run_on_new_event(m, event, {})

        self.assertEqual(len(m._api.memberships), 1)
        self.assertEqual(m._api.memberships[0][3], "leave")

    def test_leave_without_stories_room_is_noop(self):
        m = _make_module(
            room_chat_types={"!chan:h": "channel"},
            stories_mapping={},
        )
        event = _member_event(room_id="!chan:h", state_key="@sub:h", membership="leave")
        _run_on_new_event(m, event, {})

        self.assertEqual(m._api.memberships, [])


class ChannelStoriesRoomCreateTest(unittest.TestCase):
    """Интеграционная дыра (CRITICAL, финальное ревью Task 3): клиент создаёт
    stories-комнату канала (Task 6), но сервер физически не мог узнать об этом
    маппинге, пока put_stories_room не вызывался ниоткуда. _on_new_event на
    m.room.create должен перехватывать создание такой комнаты и сам вызывать
    put_stories_room - иначе ChannelStoriesStore навсегда пуст и раздача
    членства (_add_member/_remove_member) - вечный no-op."""

    def test_stories_room_creation_writes_mapping(self):
        m = _make_module()
        content = {
            "com.liza.chat.type": "stories",
            "com.liza.stories": True,
            "com.liza.channel.stories_of": {"channel_id": "!chan:h"},
        }
        event = _create_event(room_id="!stories:h", content=content)
        _run_on_new_event(m, event, {})

        self.assertEqual(m._store.put_calls, [("!chan:h", "!stories:h")])

    def test_ordinary_room_creation_does_not_write_mapping(self):
        """Обычная комната (канал, DM, пространство - без маркера
        stories_of) не должна порождать запись в ChannelStoriesStore."""
        m = _make_module()
        content = {"com.liza.chat.type": "channel"}
        event = _create_event(room_id="!chan:h", content=content)
        _run_on_new_event(m, event, {})

        self.assertEqual(m._store.put_calls, [])

    def test_room_create_without_content_does_not_write_mapping(self):
        m = _make_module()
        event = _create_event(room_id="!plain:h", content={})
        _run_on_new_event(m, event, {})

        self.assertEqual(m._store.put_calls, [])

    def test_mapping_becomes_visible_to_membership_handling(self):
        """После обработки m.room.create последующий join в канал должен
        увидеть свежезаписанный маппинг через тот же _FakeStore (сквозной
        сценарий: создание stories-комнаты -> join подписчика -> invite)."""
        m = _make_module(
            room_chat_types={"!chan:h": "channel", "!stories:h": "stories"},
            room_creators={"!stories:h": "@owner:h"},
        )
        content = {
            "com.liza.chat.type": "stories",
            "com.liza.stories": True,
            "com.liza.channel.stories_of": {"channel_id": "!chan:h"},
        }
        _run_on_new_event(m, _create_event(room_id="!stories:h", content=content), {})

        join_event = _member_event(room_id="!chan:h", state_key="@sub:h")
        _run_on_new_event(m, join_event, {})

        self.assertEqual(len(m._api.memberships), 1)
        owner, target, room_id, action, _ = m._api.memberships[0]
        self.assertEqual((owner, target, room_id, action), ("@owner:h", "@sub:h", "!stories:h", "invite"))


class ChannelStoriesBackfillTest(unittest.TestCase):
    """Task 4: при создании stories-комнаты канала уже существующие
    join-члены канала должны быть заинвайчены в неё - иначе действующие
    подписчики не увидят историй, пока не перезайдут в канал (см. брифинг
    task-4-brief.md)."""

    def test_room_create_backfills_existing_channel_members(self):
        m = _make_module(
            room_chat_types={"!chan:h": "channel", "!stories:h": "stories"},
            room_creators={"!stories:h": "@owner:h"},
            room_members={"!chan:h": ["@a:h", "@b:h", "@liza:h"]},
        )
        content = {
            "com.liza.chat.type": "stories",
            "com.liza.stories": True,
            "com.liza.channel.stories_of": {"channel_id": "!chan:h"},
        }
        _run_on_new_event(m, _create_event(room_id="!stories:h", content=content), {})

        # маппинг записан (Task 3, регрессия)
        self.assertEqual(m._store.put_calls, [("!chan:h", "!stories:h")])

        # backfill: 2 обычных члена канала заинвайчены, AI - пропущен
        invited = {(o, t, r, a) for o, t, r, a, _ in m._api.memberships}
        self.assertEqual(
            invited,
            {
                ("@owner:h", "@a:h", "!stories:h", "invite"),
                ("@owner:h", "@b:h", "!stories:h", "invite"),
            },
        )
        self.assertEqual(len(m._api.memberships), 2)

    def test_backfill_reads_members_via_get_users_in_room(self):
        """Доказывает, какой именно API используется для чтения членов
        канала: get_users_in_room(channel_id) на main datastore (тот же
        метод, что synapse/storage/databases/main/roommember.py возвращает
        join-only список из current_state_events)."""
        m = _make_module(
            room_chat_types={"!chan:h": "channel", "!stories:h": "stories"},
            room_creators={"!stories:h": "@owner:h"},
            room_members={"!chan:h": ["@a:h"]},
        )
        content = {
            "com.liza.chat.type": "stories",
            "com.liza.stories": True,
            "com.liza.channel.stories_of": {"channel_id": "!chan:h"},
        }
        _run_on_new_event(m, _create_event(room_id="!stories:h", content=content), {})

        self.assertEqual(m._main_store.get_users_in_room_calls, ["!chan:h"])

    def test_backfill_noop_when_channel_has_no_members(self):
        m = _make_module(
            room_chat_types={"!chan:h": "channel", "!stories:h": "stories"},
            room_creators={"!stories:h": "@owner:h"},
            room_members={},
        )
        content = {
            "com.liza.chat.type": "stories",
            "com.liza.stories": True,
            "com.liza.channel.stories_of": {"channel_id": "!chan:h"},
        }
        _run_on_new_event(m, _create_event(room_id="!stories:h", content=content), {})

        self.assertEqual(m._api.memberships, [])


if __name__ == "__main__":
    unittest.main()
