"""Смок-тесты ClientGuardModule — гейт логина «только клиент Liza».

ledger:RL-client-guard-login-gate

Модуль регистрирует spam-checker-колбэк check_login_for_spam и пропускает
логин ТОЛЬКО при initial_device_display_name, начинающемся с allowed_prefix
(по умолчанию "Liza"); иначе возвращает (Codes.FORBIDDEN, {...}) — ловушка №1
CLAUDE.md («client_guard блокирует логин без initial_device_display_name»).

Async-стиль: pytest-asyncio в окружении servers/synapse/src не установлен —
unittest.TestCase + asyncio.run(...), как в channel_guard/tests/test_logic.py.
"""

import asyncio
import unittest

from synapse.api.errors import Codes

from synapse_modules.client_guard import NOT_SPAM, ClientGuardModule


def _run(coro):
    return asyncio.run(coro)


class _FakeApi:
    """Fake ModuleApi: конструктор модуля вызывает
    register_spam_checker_callbacks, поэтому fake обязан его иметь
    (иначе __init__ упадёт)."""

    def __init__(self):
        self.registered = {}

    def register_spam_checker_callbacks(self, **callbacks):
        self.registered.update(callbacks)


def _make_module(config=None):
    return ClientGuardModule(config or {}, _FakeApi())


def _check(module, display_name, user_id="@u:h", device_id="DEV1"):
    return _run(
        module._check_login_for_spam(
            user_id=user_id,
            device_id=device_id,
            initial_device_display_name=display_name,
            request_info=[],
        )
    )


class ClientGuardModuleTestCase(unittest.TestCase):
    def test_registers_login_spam_checker_callback(self):
        api = _FakeApi()
        module = ClientGuardModule({}, api)
        # assertEqual, не assertIs: bound method — новый объект на каждом
        # обращении, но равен при том же func+instance.
        self.assertEqual(
            api.registered.get("check_login_for_spam"),
            module._check_login_for_spam,
        )

    def test_liza_client_allowed(self):
        module = _make_module()
        for name in ("Liza Android", "Liza iOS", "Liza web", "Liza macOS"):
            self.assertEqual(_check(module, name), NOT_SPAM)

    def test_missing_display_name_blocked(self):
        # Клиент, не приславший initial_device_display_name, — блок.
        module = _make_module()
        result = _check(module, None)
        self.assertEqual(
            result,
            (
                Codes.FORBIDDEN,
                {"error": "This server only accepts the Liza client."},
            ),
        )

    def test_foreign_client_blocked(self):
        module = _make_module()
        result = _check(module, "Element X")
        self.assertEqual(result[0], Codes.FORBIDDEN)

    def test_empty_display_name_blocked(self):
        module = _make_module()
        self.assertEqual(_check(module, "")[0], Codes.FORBIDDEN)

    def test_prefix_is_case_sensitive(self):
        # startswith чувствителен к регистру: "liza ios" — НЕ наш клиент.
        module = _make_module()
        self.assertEqual(_check(module, "liza iOS")[0], Codes.FORBIDDEN)

    def test_bare_prefix_allowed(self):
        # Префикс — "Liza" без пробела: голое "Liza" (и "LizaFoo") проходит.
        # Это реальная семантика модуля, фиксируем как есть.
        module = _make_module()
        self.assertEqual(_check(module, "Liza"), NOT_SPAM)

    def test_prefix_not_matched_mid_string(self):
        # startswith, не substring: "My Liza fork" — блок.
        module = _make_module()
        self.assertEqual(_check(module, "My Liza fork")[0], Codes.FORBIDDEN)

    def test_allowed_prefix_configurable(self):
        # allowed_prefix берётся из config; дефолт "Liza" — только фолбэк.
        module = _make_module({"allowed_prefix": "Element"})
        self.assertEqual(_check(module, "Element X"), NOT_SPAM)
        self.assertEqual(_check(module, "Liza iOS")[0], Codes.FORBIDDEN)


if __name__ == "__main__":
    unittest.main()
