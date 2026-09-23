"""Интеграционные тесты KnockNotifyModule._on_new_event (без реального Synapse).

ledger:RL-knock-push-to-inviters
Модуль конструируется через __new__ + подстановку _api (минуем __init__, который
регистрирует callback на реальном api). state_events — dict (type, state_key)->_Ev,
как в stories_membership/tests.
"""

import asyncio
import unittest

from synapse_modules.knock_notify import KnockNotifyModule


class _Ev:
    def __init__(self, type_, state_key=None, content=None, room_id=None,
                 event_id=None, sender=None):
        self.type = type_
        self.state_key = state_key
        self.content = content or {}
        self.room_id = room_id
        self.event_id = event_id
        self.sender = sender


class _FakeApi:
    """Мини-ModuleApi: is_mine + запись send_http_push_notification."""

    def __init__(self, local_suffix=":local.test"):
        self._suffix = local_suffix
        self.pushes: list[tuple[str, str | None, dict]] = []

    def is_mine(self, user_id: str) -> bool:
        return user_id.endswith(self._suffix)

    async def send_http_push_notification(self, user_id, device_id, content,
                                          tweaks=None, default_payload=None):
        self.pushes.append((user_id, device_id, content))
        return {}


def _make_module(api):
    mod = KnockNotifyModule.__new__(KnockNotifyModule)
    mod._api = api
    return mod


def _group_state(knocker="@knocker:local.test"):
    """Состояние группы: admin(100)+mod(50)+member(0) join, knocker knock, PL invite:50."""
    return {
        ("m.room.power_levels", ""): _Ev(
            "m.room.power_levels", "",
            {
                "users": {
                    "@admin:local.test": 100,
                    "@mod:local.test": 50,
                    "@member:local.test": 0,
                },
                "users_default": 0,
                "invite": 50,
            },
        ),
        ("m.room.name", ""): _Ev("m.room.name", "", {"name": "Закрытый клуб"}),
        ("m.room.member", "@admin:local.test"): _Ev(
            "m.room.member", "@admin:local.test", {"membership": "join"}
        ),
        ("m.room.member", "@mod:local.test"): _Ev(
            "m.room.member", "@mod:local.test", {"membership": "join"}
        ),
        ("m.room.member", "@member:local.test"): _Ev(
            "m.room.member", "@member:local.test", {"membership": "join"}
        ),
        ("m.room.member", knocker): _Ev(
            "m.room.member", knocker, {"membership": "knock"}
        ),
    }


def _knock_event(knocker="@knocker:local.test", display="Гость"):
    return _Ev(
        "m.room.member", knocker,
        {"membership": "knock", "displayname": display},
        room_id="!club:local.test", event_id="$knock1", sender=knocker,
    )


class KnockNotifyModuleTest(unittest.TestCase):
    def test_ac1_pushes_to_admin_and_moderator(self):
        """AC:RL-knock-push-to-inviters/1 — пуш обоим локальным PL>=50."""
        api = _FakeApi()
        mod = _make_module(api)
        asyncio.run(mod._on_new_event(_knock_event(), _group_state()))
        recipients = sorted(u for u, _d, _c in api.pushes)
        self.assertEqual(recipients, ["@admin:local.test", "@mod:local.test"])

    def test_ac2_regular_member_gets_no_push(self):
        """AC:RL-knock-push-to-inviters/2 — рядовой участник PL0 не в получателях."""
        api = _FakeApi()
        mod = _make_module(api)
        asyncio.run(mod._on_new_event(_knock_event(), _group_state()))
        recipients = [u for u, _d, _c in api.pushes]
        self.assertNotIn("@member:local.test", recipients)

    def test_ac3_knocker_gets_no_push(self):
        """AC:RL-knock-push-to-inviters/3 — сам стучащийся не получает пуш."""
        api = _FakeApi()
        mod = _make_module(api)
        asyncio.run(mod._on_new_event(_knock_event(), _group_state()))
        recipients = [u for u, _d, _c in api.pushes]
        self.assertNotIn("@knocker:local.test", recipients)

    def test_ac4_company_space_invite_zero_no_leak(self):
        """AC:RL-knock-push-to-inviters/4 — компания (space, invite:0): пуш только
        владельцу PL100, рядовому участнику НЕ течёт (knock_restricted-топология)."""
        api = _FakeApi()
        mod = _make_module(api)
        state = {
            ("m.room.power_levels", ""): _Ev(
                "m.room.power_levels", "",
                {
                    "users": {"@owner:local.test": 100, "@member:local.test": 0},
                    "users_default": 0,
                    "invite": 0,
                },
            ),
            ("m.room.member", "@owner:local.test"): _Ev(
                "m.room.member", "@owner:local.test", {"membership": "join"}
            ),
            ("m.room.member", "@member:local.test"): _Ev(
                "m.room.member", "@member:local.test", {"membership": "join"}
            ),
            ("m.room.member", "@knocker:local.test"): _Ev(
                "m.room.member", "@knocker:local.test", {"membership": "knock"}
            ),
        }
        asyncio.run(mod._on_new_event(_knock_event(), state))
        recipients = sorted(u for u, _d, _c in api.pushes)
        self.assertEqual(recipients, ["@owner:local.test"])

    def test_ac5_no_counts_no_badge_inflation(self):
        """AC:RL-knock-push-to-inviters/5 — payload без counts (мимо
        event_push_actions, бейдж админа не инфлируется)."""
        api = _FakeApi()
        mod = _make_module(api)
        asyncio.run(mod._on_new_event(_knock_event(), _group_state()))
        self.assertTrue(api.pushes)
        for _u, _d, content in api.pushes:
            self.assertNotIn("counts", content)
            self.assertEqual(content["membership"], "knock")
            self.assertEqual(content["event_id"], "$knock1")
            self.assertEqual(content["room_name"], "Закрытый клуб")
            self.assertEqual(content["sender_display_name"], "Гость")

    def test_ac6_non_knock_membership_ignored(self):
        """AC:RL-knock-push-to-inviters/6 — invite/join/leave не шлют пуш (анти-регресс)."""
        api = _FakeApi()
        mod = _make_module(api)
        for membership in ("invite", "join", "leave", "ban"):
            ev = _Ev(
                "m.room.member", "@x:local.test",
                {"membership": membership}, room_id="!club:local.test",
                event_id="$m", sender="@x:local.test",
            )
            asyncio.run(mod._on_new_event(ev, _group_state()))
        self.assertEqual(api.pushes, [])

    def test_constructor_registers_on_new_event(self):
        """Контракт с ModuleApi: __init__ регистрирует on_new_event (иначе
        переименование аргумента в Synapse API поймали бы только в runtime)."""
        captured = {}

        class _RegApi:
            def register_third_party_rules_callbacks(self, **kwargs):
                captured.update(kwargs)

            def is_mine(self, user_id):
                return True

        mod = KnockNotifyModule({}, _RegApi())
        self.assertIn("on_new_event", captured)
        self.assertEqual(captured["on_new_event"], mod._on_new_event)

    def test_broken_member_element_does_not_drop_others(self):
        """Битый элемент state (ключ не распаковывается) не обрезает остаток —
        ревьюеры после него всё равно попадают в получатели."""
        api = _FakeApi()
        mod = _make_module(api)
        state = _group_state()
        # Вставляем «отравленный» ключ, который не распакуется в (type, state_key):
        state[("m.room.member", "@mod:local.test", "extra")] = _Ev(
            "m.room.member", "@mod:local.test", {"membership": "join"}
        )
        asyncio.run(mod._on_new_event(_knock_event(), state))
        recipients = sorted(u for u, _d, _c in api.pushes)
        # admin (валиден) и mod (валиден по своему ключу) получены; битый ключ пропущен.
        self.assertIn("@admin:local.test", recipients)
        self.assertIn("@mod:local.test", recipients)

    def test_ac6_repeat_knock_after_kick_pushes_again(self):
        """AC:RL-knock-push-to-inviters/6 — повторный knock (новое событие) снова
        шлёт пуш (ожидаемо, не дедуп)."""
        api = _FakeApi()
        mod = _make_module(api)
        asyncio.run(mod._on_new_event(_knock_event(), _group_state()))
        first = len(api.pushes)
        asyncio.run(
            mod._on_new_event(
                _knock_event(display="Гость снова"), _group_state()
            )
        )
        self.assertEqual(len(api.pushes), first * 2)

    def test_remote_reviewer_not_served_by_this_instance(self):
        """Ревьюер на чужом инстансе не обслуживается (is_mine) — дублей нет."""
        api = _FakeApi()
        mod = _make_module(api)
        state = _group_state()
        state[("m.room.member", "@boss:remote.test")] = _Ev(
            "m.room.member", "@boss:remote.test", {"membership": "join"}
        )
        state[("m.room.power_levels", "")].content["users"][
            "@boss:remote.test"
        ] = 100
        asyncio.run(mod._on_new_event(_knock_event(), state))
        recipients = [u for u, _d, _c in api.pushes]
        self.assertNotIn("@boss:remote.test", recipients)

    def test_no_reviewers_no_push(self):
        """Комната без локальных PL>=50 (кроме knocker) — пуша нет, без падений."""
        api = _FakeApi()
        mod = _make_module(api)
        state = {
            ("m.room.power_levels", ""): _Ev(
                "m.room.power_levels", "",
                {"users": {"@member:local.test": 0}, "users_default": 0},
            ),
            ("m.room.member", "@member:local.test"): _Ev(
                "m.room.member", "@member:local.test", {"membership": "join"}
            ),
            ("m.room.member", "@knocker:local.test"): _Ev(
                "m.room.member", "@knocker:local.test", {"membership": "knock"}
            ),
        }
        asyncio.run(mod._on_new_event(_knock_event(), state))
        self.assertEqual(api.pushes, [])

    def test_push_failure_does_not_break_others(self):
        """Исключение на одном пушере не срывает доставку остальным."""
        api = _FakeApi()

        calls = {"n": 0}
        orig = api.send_http_push_notification

        async def flaky(user_id, device_id, content, tweaks=None, default_payload=None):
            calls["n"] += 1
            if user_id == "@admin:local.test":
                raise RuntimeError("pusher down")
            return await orig(user_id, device_id, content)

        api.send_http_push_notification = flaky
        mod = _make_module(api)
        asyncio.run(mod._on_new_event(_knock_event(), _group_state()))
        # admin упал, mod всё равно получил.
        recipients = [u for u, _d, _c in api.pushes]
        self.assertEqual(recipients, ["@mod:local.test"])
        self.assertEqual(calls["n"], 2)


if __name__ == "__main__":
    unittest.main()
