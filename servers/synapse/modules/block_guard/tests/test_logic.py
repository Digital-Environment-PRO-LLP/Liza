"""Чистые предикаты block_guard — без Synapse.

ledger:RL-block-user-enforcement
Стиль — unittest, НЕ pytest-asyncio (в servers/synapse/src его нет; урок из
channel_sync/tests, зафиксирован в knock_notify/tests/test_logic.py).
"""

import unittest
from types import MappingProxyType

from synapse_modules.block_guard._logic import (
    blocked_invitees,
    dm_counterpart,
    ignores,
    is_blockable_event_type,
    is_exempt_room,
    is_service_localpart,
    room_is_direct_for,
    should_notify_invite,
)

A = "@alice:local.test"   # блокирующий
B = "@bob:local.test"     # заблокированный
C = "@carol:local.test"
ROOM = "!dm:local.test"


class TestBlockableEventType(unittest.TestCase):
    """AC:RL-block-user-enforcement/15 — фильтр по типу события ДО обращения к БД."""

    def test_messages_are_blockable(self):
        for t in ("m.room.message", "m.room.encrypted", "m.reaction"):
            self.assertTrue(is_blockable_event_type(t, {}), t)

    def test_direct_invite_is_blockable(self):
        self.assertTrue(
            is_blockable_event_type(
                "m.room.member", {"membership": "invite", "is_direct": True}
            )
        )

    def test_knock_is_not_blockable(self):
        """Red-proof: knock-заявка обязана проходить (RL-knock-push-to-inviters)."""
        self.assertFalse(
            is_blockable_event_type("m.room.member", {"membership": "knock"})
        )

    def test_group_invite_is_not_blockable(self):
        """Инвайт БЕЗ is_direct (группа/канал/компания, сторис-инвайт) — не наш случай."""
        self.assertFalse(
            is_blockable_event_type("m.room.member", {"membership": "invite"})
        )

    def test_other_state_events_are_not_blockable(self):
        """Red-proof: скрытие участников и прочий state не должны падать в энфорс."""
        for t in (
            "com.liza.chat.hidden_members",
            "m.room.topic",
            "m.room.power_levels",
            "m.room.redaction",
            "m.room.create",
        ):
            self.assertFalse(is_blockable_event_type(t, {}), t)

    def test_join_and_leave_are_not_blockable(self):
        for membership in ("join", "leave", "ban"):
            self.assertFalse(
                is_blockable_event_type("m.room.member", {"membership": membership}),
                membership,
            )


class TestExemptRoom(unittest.TestCase):
    """AC:RL-block-user-enforcement/10, AC:RL-block-user-enforcement/13."""

    def test_space_and_channel_exempt(self):
        self.assertTrue(is_exempt_room("m.space", None, None))
        self.assertTrue(is_exempt_room("com.liza.channel", None, None))

    def test_stories_room_exempt(self):
        """Red-proof: сторис-граф раздаётся инвайтами, а ошибки глотаются в
        logger.debug — регрессия была бы бесшумной."""
        self.assertTrue(is_exempt_room(None, "stories", None))
        self.assertTrue(is_exempt_room(None, None, None, legacy_stories=True))
        self.assertTrue(is_exempt_room(None, None, {"hidden": True}))

    def test_channel_discussion_exempt(self):
        self.assertTrue(is_exempt_room(None, "channel_discussion", None))

    def test_plain_dm_not_exempt(self):
        self.assertFalse(is_exempt_room(None, None, None))
        self.assertFalse(is_exempt_room(None, None, {"hidden": False}))


class TestDmCounterpart(unittest.TestCase):
    """AC:RL-block-user-enforcement/9, AC:RL-block-user-enforcement/18."""

    def test_pair_returns_other_side(self):
        members = [(A, "join"), (B, "join")]
        self.assertEqual(dm_counterpart(members, B), A)

    def test_invited_counts_as_participant(self):
        members = [(A, "invite"), (B, "join")]
        self.assertEqual(dm_counterpart(members, B), A)

    def test_group_returns_none(self):
        """Red-proof: в группе один игнорирующий не должен затыкать отправителя."""
        members = [(A, "join"), (B, "join"), (C, "join")]
        self.assertIsNone(dm_counterpart(members, B))

    def test_left_members_do_not_count(self):
        members = [(A, "join"), (B, "join"), (C, "leave")]
        self.assertEqual(dm_counterpart(members, B), A)

    def test_sender_not_in_room(self):
        self.assertIsNone(dm_counterpart([(A, "join"), (C, "join")], B))


class TestDirectAndIgnore(unittest.TestCase):
    """AC:RL-block-user-enforcement/18."""

    def test_room_is_direct(self):
        self.assertTrue(room_is_direct_for({B: [ROOM]}, ROOM))
        self.assertTrue(room_is_direct_for({C: ["!x:t"], B: ["!y:t", ROOM]}, ROOM))

    def test_room_not_direct(self):
        self.assertFalse(room_is_direct_for({B: ["!other:t"]}, ROOM))
        self.assertFalse(room_is_direct_for(None, ROOM))
        self.assertFalse(room_is_direct_for({}, ROOM))
        self.assertFalse(room_is_direct_for({B: ROOM}, ROOM))

    def test_ignores(self):
        self.assertTrue(ignores({"ignored_users": {B: {}}}, B))
        self.assertFalse(ignores({"ignored_users": {C: {}}}, B))
        self.assertFalse(ignores({"ignored_users": []}, B))
        self.assertFalse(ignores(None, B))


class TestFrozenAccountData(unittest.TestCase):
    """RED-PROOF: account data приходит ЗАМОРОЖЕННЫМ, а не простым dict.

    `ModuleApi.account_data_manager.get_global` пропускает содержимое через
    `synapse.util.frozenutils.freeze`: словари становятся `immutabledict` (НЕ
    подкласс dict), списки — кортежами. Проверки `isinstance(x, dict/list)` на
    таком содержимом молча давали False → «не заблокирован» → энфорс не работал
    ВООБЩЕ. Юнит-тесты на простых dict были зелёными; поймал живой прогон на
    инстансе hello 2026-09-04. Здесь immutabledict имитируется MappingProxyType
    (тоже Mapping, но не dict-подкласс — точнее любого фейка-словаря).

    AC:RL-block-user-enforcement/18
    """

    @staticmethod
    def _frozen(obj):
        """Аналог synapse.util.frozenutils.freeze: Mapping-не-dict + кортежи."""
        if isinstance(obj, dict):
            return MappingProxyType({k: TestFrozenAccountData._frozen(v)
                                     for k, v in obj.items()})
        if isinstance(obj, (list, tuple)):
            return tuple(TestFrozenAccountData._frozen(v) for v in obj)
        return obj

    def test_frozen_ignore_list_still_detected(self):
        frozen = self._frozen({"ignored_users": {B: {}}})
        self.assertNotIsInstance(frozen, dict)   # иначе тест не доказывает баг
        self.assertTrue(ignores(frozen, B))
        self.assertFalse(ignores(frozen, C))

    def test_frozen_m_direct_still_detected(self):
        frozen = self._frozen({B: [ROOM]})
        self.assertNotIsInstance(frozen, dict)
        self.assertIsInstance(frozen[B], tuple)  # список стал кортежем
        self.assertTrue(room_is_direct_for(frozen, ROOM))
        self.assertFalse(room_is_direct_for(frozen, "!other:t"))

    def test_frozen_create_room_config(self):
        cfg = self._frozen({"is_direct": True, "invite": [A]})
        self.assertEqual(blocked_invitees(cfg, {A: True}), [A])


class TestServiceLocalpart(unittest.TestCase):
    """AC:RL-block-user-enforcement/12 — служебные аккаунты неблокируемы."""

    def test_known_bots(self):
        for mxid in (
            "@liza:bots.liza.ru",
            "@support:local.test",
            "@bot_father:bots.liza.ru",
            "@bo_food:local.test",
        ):
            self.assertTrue(
                is_service_localpart(mxid, ("liza", "support", "bot_father", "bo_food")),
                mxid,
            )

    def test_human_is_not_service(self):
        self.assertFalse(is_service_localpart(B, ("liza", "support")))


class TestBlockedInvitees(unittest.TestCase):
    """AC:RL-block-user-enforcement/1, AC:RL-block-user-enforcement/11."""

    def test_direct_invite_to_blocker(self):
        cfg = {"is_direct": True, "invite": [A]}
        self.assertEqual(blocked_invitees(cfg, {A: True}), [A])

    def test_group_creation_not_blocked(self):
        """Red-proof: компания/группа с несколькими invitee создаётся всегда."""
        cfg = {"invite": [A, C]}
        self.assertEqual(blocked_invitees(cfg, {A: True, C: False}), [])

    def test_room_upgrade_config_without_invite(self):
        """Red-proof: путь апгрейда комнаты (handlers/room.py:700) шлёт урезанный
        dict БЕЗ ключа invite — матчить нечего, fast-path allow."""
        self.assertEqual(blocked_invitees({"is_direct": True}, {A: True}), [])
        self.assertEqual(blocked_invitees({}, {A: True}), [])
        self.assertEqual(blocked_invitees(None, {A: True}), [])

    def test_direct_invite_to_non_blocker(self):
        cfg = {"is_direct": True, "invite": [C]}
        self.assertEqual(blocked_invitees(cfg, {C: False}), [])


class TestShouldNotifyInvite(unittest.TestCase):
    """R1 — зеркало правки push/bulk_push_rule_evaluator.py.

    AC:RL-block-user-enforcement/5, AC:RL-block-user-enforcement/6
    """

    def test_no_push_when_sender_ignored(self):
        self.assertFalse(should_notify_invite(B, {B, C}))

    def test_push_when_not_ignored(self):
        self.assertTrue(should_notify_invite(B, {C}))
        self.assertTrue(should_notify_invite(B, frozenset()))

    def test_legacy_orphan_invite_also_silenced(self):
        """AC-6: унаследованный инвайт-сирота, созданный ДО фикса, тоже не пушит —
        решение принимается на КАЖДОЙ оценке правил, а не однократно при создании."""
        self.assertFalse(should_notify_invite(B, frozenset({B})))


if __name__ == "__main__":
    unittest.main()
