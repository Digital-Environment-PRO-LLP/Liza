"""Интеграционные тесты BlockGuardModule (без реального Synapse).

ledger:RL-block-user-enforcement
Модуль конструируется через __new__ + подстановку полей — минуем __init__,
который регистрирует колбэки на реальном api (приём из knock_notify/tests).
state_events — dict (type, state_key)->_Ev, как в stories_membership/tests.
"""

import asyncio
import unittest

from synapse_modules.block_guard import BlockGuardModule
from synapse_modules.block_guard._logic import (
    BLOCKED_ERRCODE,
    DEFAULT_SERVICE_LOCALPARTS,
)

A = "@alice:local.test"          # блокирующий (держит B в чёрном списке)
B = "@bob:local.test"            # заблокированный
C = "@carol:local.test"
REMOTE = "@dave:remote.test"
LIZA = "@liza:bots.liza.ru"
ROOM = "!dm:local.test"


class _Ev:
    def __init__(self, type_, state_key=None, content=None, room_id=ROOM,
                 sender=None):
        self.type = type_
        self.state_key = state_key
        self.content = content or {}
        self.room_id = room_id
        self.sender = sender


class _AccountData:
    def __init__(self, data):
        self._data = data

    async def get_global(self, user_id, data_type):
        return self._data.get((user_id, data_type))


class _FakeApi:
    """Мини-ModuleApi: is_mine + account_data_manager."""

    def __init__(self, account_data=None, local_suffix=":local.test"):
        self._suffix = local_suffix
        self.account_data_manager = _AccountData(account_data or {})

    def is_mine(self, user_id):
        return bool(user_id) and user_id.endswith(self._suffix)


def _make_module(api, enabled=True):
    mod = BlockGuardModule.__new__(BlockGuardModule)
    mod._api = api
    mod._enabled = enabled
    mod._service_localparts = DEFAULT_SERVICE_LOCALPARTS
    return mod


def _api_with_block(direct_owner=A, ignorer=A, ignored=B, room_id=ROOM):
    """API, где `ignorer` держит `ignored` в чёрном списке, а комната — DM."""
    return _FakeApi(
        {
            (ignorer, "m.ignored_user_list"): {"ignored_users": {ignored: {}}},
            (direct_owner, "m.direct"): {ignored: [room_id]},
        }
    )


def _requester(user_id):
    class _U:
        def to_string(self):
            return user_id

    class _R:
        user = _U()

    return _R()


def _dm_state(members=((A, "join"), (B, "join")), create_content=None,
              topology=None):
    state = {
        ("m.room.create", ""): _Ev("m.room.create", "", create_content or {}),
    }
    for user_id, membership in members:
        state[("m.room.member", user_id)] = _Ev(
            "m.room.member", user_id, {"membership": membership}
        )
    if topology is not None:
        state[("com.liza.chat.topology", "")] = _Ev(
            "com.liza.chat.topology", "", topology
        )
    return state


def _msg(sender=B, type_="m.room.message"):
    return _Ev(type_, None, {"msgtype": "m.text", "body": "привет"}, sender=sender)


def _run(coro):
    return asyncio.run(coro)


def _expect_blocked(testcase, coro):
    """Колбэк обязан бросить 403 с нашим errcode (а не вернуть False)."""
    with testcase.assertRaises(Exception) as ctx:
        _run(coro)
    err = ctx.exception
    testcase.assertEqual(getattr(err, "code", None), 403)
    testcase.assertEqual(getattr(err, "errcode", None), BLOCKED_ERRCODE)
    # Текст русский и не пустой — именно он показывается на старых сборках.
    testcase.assertTrue(getattr(err, "msg", ""))
    return err


class TestOnCreateRoom(unittest.TestCase):
    """AC:RL-block-user-enforcement/1, AC:RL-block-user-enforcement/2,
    AC:RL-block-user-enforcement/11, AC:RL-block-user-enforcement/12."""

    def test_direct_chat_with_blocker_rejected(self):
        mod = _make_module(_api_with_block())
        _expect_blocked(
            self,
            mod._on_create_room(
                _requester(B), {"is_direct": True, "invite": [A]}, False
            ),
        )

    def test_admin_does_not_bypass(self):
        """Блокировка — решение пользователя, а не вопрос прав админа сервера."""
        mod = _make_module(_api_with_block())
        _expect_blocked(
            self,
            mod._on_create_room(
                _requester(B), {"is_direct": True, "invite": [A]}, True
            ),
        )

    def test_direct_chat_with_non_blocker_allowed(self):
        mod = _make_module(_api_with_block())
        self.assertIsNone(
            _run(
                mod._on_create_room(
                    _requester(B), {"is_direct": True, "invite": [C]}, False
                )
            )
        )

    def test_group_creation_allowed(self):
        """Red-proof AC-11: компания/группа с несколькими invitee не режется."""
        mod = _make_module(_api_with_block())
        self.assertIsNone(
            _run(mod._on_create_room(_requester(B), {"invite": [A, C]}, False))
        )

    def test_room_upgrade_config_allowed(self):
        """Red-proof AC-11: путь апгрейда шлёт config без ключа invite."""
        mod = _make_module(_api_with_block())
        self.assertIsNone(
            _run(mod._on_create_room(_requester(B), {"is_direct": True}, False))
        )

    def test_service_account_never_blocked(self):
        """Red-proof AC-12: @liza создаёт DM пользователю, который её игнорирует."""
        api = _FakeApi(
            {(A, "m.ignored_user_list"): {"ignored_users": {LIZA: {}}}}
        )
        mod = _make_module(api)
        self.assertIsNone(
            _run(
                mod._on_create_room(
                    _requester(LIZA), {"is_direct": True, "invite": [A]}, False
                )
            )
        )

    def test_disabled_module_allows_everything(self):
        mod = _make_module(_api_with_block(), enabled=False)
        self.assertIsNone(
            _run(
                mod._on_create_room(
                    _requester(B), {"is_direct": True, "invite": [A]}, False
                )
            )
        )


class TestCheckEventAllowedMessages(unittest.TestCase):
    """AC:RL-block-user-enforcement/4, AC:RL-block-user-enforcement/8,
    AC:RL-block-user-enforcement/9, AC:RL-block-user-enforcement/18."""

    def test_message_to_blocker_rejected(self):
        mod = _make_module(_api_with_block())
        _expect_blocked(self, mod._check_event_allowed(_msg(), _dm_state()))

    def test_encrypted_and_reaction_rejected(self):
        for type_ in ("m.room.encrypted", "m.reaction"):
            mod = _make_module(_api_with_block())
            _expect_blocked(
                self,
                mod._check_event_allowed(_msg(type_=type_), _dm_state()),
            )

    def test_block_is_one_directional(self):
        """Red-proof AC-8: блокирующий писать может."""
        mod = _make_module(_api_with_block())
        self.assertEqual(
            _run(mod._check_event_allowed(_msg(sender=A), _dm_state())),
            (True, None),
        )

    def test_group_message_allowed(self):
        """Red-proof AC-9: в группе один игнорирующий не затыкает отправителя."""
        mod = _make_module(_api_with_block())
        state = _dm_state(members=((A, "join"), (B, "join"), (C, "join")))
        self.assertEqual(
            _run(mod._check_event_allowed(_msg(), state)), (True, None)
        )

    def test_pair_room_not_in_m_direct_allowed(self):
        """AC-18 fail-open: парная комната, не числящаяся DM ни у одной стороны
        (схлопнувшаяся группа, комната заявки), не режется."""
        api = _FakeApi(
            {(A, "m.ignored_user_list"): {"ignored_users": {B: {}}}}
        )
        mod = _make_module(api)
        self.assertEqual(
            _run(mod._check_event_allowed(_msg(), _dm_state())), (True, None)
        )

    def test_m_direct_of_sender_is_enough(self):
        """AC-18/П-3: получатель мог не добавить комнату в свой m.direct."""
        api = _api_with_block(direct_owner=B)
        mod = _make_module(api)
        _expect_blocked(self, mod._check_event_allowed(_msg(), _dm_state()))

    def test_no_block_without_ignore(self):
        api = _FakeApi({(A, "m.direct"): {B: [ROOM]}})
        mod = _make_module(api)
        self.assertEqual(
            _run(mod._check_event_allowed(_msg(), _dm_state())), (True, None)
        )


class TestCheckEventAllowedExemptions(unittest.TestCase):
    """Негативные кейсы: AC:RL-block-user-enforcement/10,
    AC:RL-block-user-enforcement/12, AC:RL-block-user-enforcement/13,
    AC:RL-block-user-enforcement/14, AC:RL-block-user-enforcement/15,
    AC:RL-block-user-enforcement/16, AC:RL-block-user-enforcement/17.
    """

    def test_remote_sender_short_circuits(self):
        """Red-proof: событие от удалённого отправителя проходит без единого
        чтения account data (федерация нам неподконтрольна).

        AC:RL-block-user-enforcement/16
        """
        class _NoReadApi(_FakeApi):
            def __init__(self):
                super().__init__({})
                self.reads = 0

            class _AD:
                def __init__(self, outer):
                    self._outer = outer

                async def get_global(self, user_id, data_type):
                    self._outer.reads += 1
                    return None

            def bind(self):
                self.account_data_manager = _NoReadApi._AD(self)
                return self

        api = _NoReadApi().bind()
        mod = _make_module(api)
        self.assertEqual(
            _run(mod._check_event_allowed(_msg(sender=REMOTE), _dm_state())),
            (True, None),
        )
        self.assertEqual(api.reads, 0)

    def test_knock_allowed(self):
        """Red-proof: заявка на вступление не должна умирать молча.

        AC:RL-block-user-enforcement/14
        """
        mod = _make_module(_api_with_block())
        ev = _Ev("m.room.member", B, {"membership": "knock"}, sender=B)
        self.assertEqual(
            _run(mod._check_event_allowed(ev, _dm_state())), (True, None)
        )

    def test_allow_branches_never_mutate_event(self):
        """Колбэк во ВСЕХ allow-ветках возвращает ровно (True, None): подмена
        content сломала бы соседние third-party rules (channel_guard,
        single_space_guard живут в той же цепочке).

        AC:RL-block-user-enforcement/17
        """
        mod = _make_module(_api_with_block())
        cases = [
            (_msg(sender=A), _dm_state()),                       # обратное направление
            (_msg(), _dm_state(members=((A, "join"), (B, "join"), (C, "join")))),
            (_msg(sender=REMOTE), _dm_state()),                  # федеративный
            (_Ev("m.room.topic", "", {}, sender=B), _dm_state()),
            (_msg(), _dm_state(create_content={"type": "m.space"})),
            (_msg(), _dm_state(topology={"hidden": True})),
        ]
        for ev, state in cases:
            result = _run(mod._check_event_allowed(ev, state))
            self.assertEqual(result, (True, None), ev.type)
            self.assertIsNone(result[1])

    def test_non_target_state_events_allowed(self):
        """Red-proof AC-15: скрытие участников и прочий state проходят."""
        mod = _make_module(_api_with_block())
        for type_ in (
            "com.liza.chat.hidden_members",
            "m.room.topic",
            "m.room.power_levels",
        ):
            ev = _Ev(type_, "", {}, sender=B)
            self.assertEqual(
                _run(mod._check_event_allowed(ev, _dm_state())),
                (True, None),
                type_,
            )

    def test_stories_room_allowed(self):
        """Red-proof AC-13: сторис-трафик вне энфорса (ошибки там глотаются в
        logger.debug — регрессия была бы бесшумной)."""
        mod = _make_module(_api_with_block())
        state = _dm_state(create_content={"com.liza.chat.type": "stories"})
        self.assertEqual(
            _run(mod._check_event_allowed(_msg(), state)), (True, None)
        )
        hidden = _dm_state(topology={"hidden": True})
        self.assertEqual(
            _run(mod._check_event_allowed(_msg(), hidden)), (True, None)
        )

    def test_space_and_channel_allowed(self):
        """Red-proof AC-10: пространство и канал вне энфорса."""
        mod = _make_module(_api_with_block())
        for room_type in ("m.space", "com.liza.channel"):
            state = _dm_state(create_content={"type": room_type})
            self.assertEqual(
                _run(mod._check_event_allowed(_msg(), state)), (True, None),
                room_type,
            )

    def test_service_sender_allowed(self):
        """Red-proof AC-12: сообщение бота пользователю, который его игнорирует."""
        api = _FakeApi(
            {
                (A, "m.ignored_user_list"): {"ignored_users": {LIZA: {}}},
                (A, "m.direct"): {LIZA: [ROOM]},
            }
        )
        mod = _make_module(api)
        state = _dm_state(members=((A, "join"), (LIZA, "join")))
        self.assertEqual(
            _run(mod._check_event_allowed(_msg(sender=LIZA), state)),
            (True, None),
        )

    def test_ai_role_sender_allowed(self):
        """AC-12: локальный аккаунт с ролью ai, заведённый не под именем бота."""
        bot = "@helper:local.test"
        api = _FakeApi(
            {
                (A, "m.ignored_user_list"): {"ignored_users": {bot: {}}},
                (A, "m.direct"): {bot: [ROOM]},
                (bot, "com.liza.user_role"): {"role": "ai"},
            }
        )
        mod = _make_module(api)
        state = _dm_state(members=((A, "join"), (bot, "join")))
        self.assertEqual(
            _run(mod._check_event_allowed(_msg(sender=bot), state)), (True, None)
        )


class TestCheckEventAllowedInvite(unittest.TestCase):
    """AC:RL-block-user-enforcement/3."""

    def _invite(self, sender=B, target=A, is_direct=True):
        content = {"membership": "invite"}
        if is_direct:
            content["is_direct"] = True
        return _Ev("m.room.member", target, content, sender=sender)

    def test_direct_invite_to_blocker_rejected(self):
        mod = _make_module(_api_with_block())
        _expect_blocked(
            self, mod._check_event_allowed(self._invite(), _dm_state())
        )

    def test_group_invite_allowed(self):
        """Red-proof: инвайт без is_direct (группа/канал/сторис) не режется."""
        mod = _make_module(_api_with_block())
        self.assertEqual(
            _run(
                mod._check_event_allowed(
                    self._invite(is_direct=False), _dm_state()
                )
            ),
            (True, None),
        )

    def test_invite_to_non_blocker_allowed(self):
        mod = _make_module(_api_with_block())
        self.assertEqual(
            _run(mod._check_event_allowed(self._invite(target=C), _dm_state())),
            (True, None),
        )


class TestRegisteredCallbacks(unittest.TestCase):
    """AC:RL-block-user-enforcement/19 — набор колбэков зафиксирован.

    user_may_join_room регистрировать НЕЛЬЗЯ: сломает force-join публичного
    канала liza_news. spam-checker нельзя: check_event_for_spam на входящей
    федеративной PDU режет содержимое (prune_event + soft-fail).
    """

    def test_only_two_third_party_callbacks(self):
        captured = {}

        class _RecordingApi(_FakeApi):
            def register_third_party_rules_callbacks(self, **kwargs):
                captured["third_party"] = sorted(kwargs)

            def register_spam_checker_callbacks(self, **kwargs):  # pragma: no cover
                captured["spam"] = sorted(kwargs)

        BlockGuardModule({}, _RecordingApi())
        self.assertEqual(
            captured.get("third_party"), ["check_event_allowed", "on_create_room"]
        )
        self.assertNotIn("spam", captured)


if __name__ == "__main__":
    unittest.main()
