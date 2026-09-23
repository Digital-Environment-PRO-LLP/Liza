"""Тесты AccessAdminHandler: досье, недостижимая ветка is_local, unquote пути."""

import asyncio
import unittest

from synapse_modules.access_admin._api import AccessAdminHandler, _JsonResource

SERVER = "liza.example"


def _run(coro):
    return asyncio.run(coro)


class _FakePermissions:
    def __init__(self, may_view: bool = True, may_view_space: bool = True):
        self._may_view = may_view
        self._may_view_space = may_view_space
        self.calls: list[tuple[str, str]] = []
        self.space_calls: list[tuple[str, str]] = []

    async def may_view(self, caller_id: str, target_id: str) -> bool:
        self.calls.append((caller_id, target_id))
        return self._may_view

    async def may_view_space(self, caller_id: str, space_id: str) -> bool:
        self.space_calls.append((caller_id, space_id))
        return self._may_view_space


class _FakeDossier:
    def __init__(self, result=None):
        self.calls: list[str] = []
        self._result = result or {"spaces": [], "channels": [], "chats": []}

    async def collect(self, target_id: str) -> dict:
        self.calls.append(target_id)
        return self._result


class _FakeAccountDataManager:
    async def get_global(self, user_id: str, type_: str):
        return None


class _FakeModuleApi:
    def __init__(self, userinfo=None):
        self._userinfo = userinfo
        self.account_data_manager = _FakeAccountDataManager()
        self.userinfo_calls: list[str] = []

    async def get_userinfo_by_id(self, user_id: str):
        self.userinfo_calls.append(user_id)
        return self._userinfo


class _FakeUserInfo:
    def __init__(self, is_deactivated: bool = False):
        self.is_deactivated = is_deactivated


class _FakeProfile:
    def __init__(self, display_name=None, avatar_url=None):
        self.display_name = display_name
        self.avatar_url = avatar_url


class _FakeStore:
    def __init__(self, profile=None):
        self._profile = profile
        self.profile_calls: list[str] = []

    async def get_profileinfo(self, user_id):
        # UserID, не строка — падает без .to_string(), если передали строку.
        self.profile_calls.append(user_id.to_string())
        return self._profile


def _handler(
    *,
    may_view: bool = True,
    userinfo=None,
    profile=None,
    module_api=None,
    store=None,
    dossier=None,
):
    return AccessAdminHandler(
        permissions=_FakePermissions(may_view),
        dossier=dossier or _FakeDossier(),
        accounts=None,
        module_api=module_api or _FakeModuleApi(userinfo),
        server_name=SERVER,
        store=store or _FakeStore(profile),
    )


class DossierForeignServerTestCase(unittest.TestCase):
    def test_foreign_domain_returns_populated_dossier(self):
        """Task 4 (спека §5.2): федеративный MXID больше не получает
        безусловно пустое досье — членства теперь берутся из
        current_state_events, который покрывает и чужие домены.

        get_userinfo_by_id по-прежнему НЕ трогаем для чужого домена: эта
        таблица содержит только локальные аккаунты и всегда вернёт None,
        поэтому deactivated принудительно False, а не результат 404.
        Профиль (display_name/avatar) для чужого домена запрашивается —
        get_profileinfo читает profiles по MXID, не ограничен локальным
        сервером.
        """
        module_api = _FakeModuleApi(userinfo=None)
        store = _FakeStore(profile=_FakeProfile("Пётр"))
        dossier_result = {
            "spaces": [],
            "channels": [],
            "chats": [{"room_id": "!f:liza.example", "name": "Общий", "avatar": None, "level": "user"}],
        }
        dossier = _FakeDossier(result=dossier_result)
        handler = _handler(module_api=module_api, store=store, dossier=dossier)

        status, payload = _run(
            handler.dossier("@boss:liza.example", "@ivan:other.example")
        )

        self.assertEqual(status, 200)
        self.assertEqual(payload["is_local"], False)
        self.assertEqual(payload["display_name"], "Пётр")
        self.assertFalse(payload["deactivated"])
        self.assertEqual(payload["chats"], dossier_result["chats"])
        self.assertIsNone(payload["server"]["role"])
        # userinfo локальных аккаунтов для чужого домена не запрашивается.
        self.assertEqual(module_api.userinfo_calls, [])
        self.assertEqual(dossier.calls, ["@ivan:other.example"])

    def test_permission_check_precedes_foreign_domain_shortcut(self):
        """Неавторизованный не должен узнать даже факт чужого домена."""
        permissions = _FakePermissions(may_view=False)
        handler = AccessAdminHandler(
            permissions=permissions,
            dossier=_FakeDossier(),
            accounts=None,
            module_api=_FakeModuleApi(),
            server_name=SERVER,
            store=_FakeStore(),
        )

        status, payload = _run(
            handler.dossier("@u:liza.example", "@ivan:other.example")
        )

        self.assertEqual(status, 403)
        self.assertEqual(payload["error"], "forbidden")
        self.assertEqual(permissions.calls, [("@u:liza.example", "@ivan:other.example")])


class DossierProfileLookupTestCase(unittest.TestCase):
    def test_local_profile_fetched_via_userid_not_local_hostname(self):
        """Находка 3: профиль берём через store.get_profileinfo(UserID),

        не через ModuleApi.get_profile_for_user(localpart), который
        пересобирает MXID с ЛОКАЛЬНЫМ hostname.
        """
        module_api = _FakeModuleApi(userinfo=_FakeUserInfo(is_deactivated=False))
        store = _FakeStore(profile=_FakeProfile("Иван", "mxc://avatar"))
        handler = _handler(module_api=module_api, store=store)

        status, payload = _run(
            handler.dossier("@boss:liza.example", "@ivan:liza.example")
        )

        self.assertEqual(status, 200)
        self.assertEqual(payload["is_local"], True)
        self.assertEqual(payload["display_name"], "Иван")
        self.assertEqual(payload["avatar_url"], "mxc://avatar")
        # get_profileinfo вызван с полным MXID через to_string(), не localpart.
        self.assertEqual(store.profile_calls, ["@ivan:liza.example"])

    def test_local_user_not_found_returns_404(self):
        handler = _handler(userinfo=None)
        status, payload = _run(
            handler.dossier("@boss:liza.example", "@ivan:liza.example")
        )
        self.assertEqual(status, 404)
        self.assertEqual(payload["error"], "not_found")


class _FakeSpaceMembers:
    def __init__(self, result=None):
        self.calls: list[str] = []
        self._result = result if result is not None else []

    async def collect(self, space_id: str) -> list:
        self.calls.append(space_id)
        return self._result


class SpaceMembersTestCase(unittest.TestCase):
    def _handler(self, *, may_view_space: bool = True, space_members=None):
        return AccessAdminHandler(
            permissions=_FakePermissions(may_view_space=may_view_space),
            dossier=_FakeDossier(),
            accounts=None,
            module_api=_FakeModuleApi(),
            server_name=SERVER,
            store=_FakeStore(),
            space_members=space_members or _FakeSpaceMembers(),
        )

    def test_forbidden_short_circuits_before_collect(self):
        """Право проверяется ДО обращения к данным — как в dossier."""
        space_members = _FakeSpaceMembers()
        handler = self._handler(may_view_space=False, space_members=space_members)

        status, payload = _run(
            handler.space_members("@u:liza.example", "!space:liza.example")
        )

        self.assertEqual(status, 403)
        self.assertEqual(payload["error"], "forbidden")
        self.assertEqual(space_members.calls, [])

    def test_allowed_returns_space_id_and_members(self):
        result = [{"user_id": "@ivan:liza.example", "membership_in_space": "join"}]
        space_members = _FakeSpaceMembers(result=result)
        handler = self._handler(space_members=space_members)

        status, payload = _run(
            handler.space_members("@boss:liza.example", "!space:liza.example")
        )

        self.assertEqual(status, 200)
        self.assertEqual(payload["space_id"], "!space:liza.example")
        self.assertEqual(payload["members"], result)
        self.assertEqual(space_members.calls, ["!space:liza.example"])


class ExtractUserIdTestCase(unittest.TestCase):
    """Находка 4: unquote + явный 400 на пустой user_id."""

    def _resource(self):
        res = _JsonResource()
        res._path_prefix = "/_synapse/client/access/v1/dossier/"
        return res

    def test_unquotes_percent_encoded_mxid(self):
        res = self._resource()

        class _Req:
            path = b"/_synapse/client/access/v1/dossier/%40ivan%3Asrv"

        self.assertEqual(res._extract_user_id(_Req()), "@ivan:srv")

    def test_plain_mxid_still_works(self):
        res = self._resource()

        class _Req:
            path = "/_synapse/client/access/v1/dossier/@ivan:srv"

        self.assertEqual(res._extract_user_id(_Req()), "@ivan:srv")

    def test_empty_user_id_raises(self):
        res = self._resource()

        class _Req:
            path = "/_synapse/client/access/v1/dossier/"

        with self.assertRaises(ValueError):
            res._extract_user_id(_Req())


if __name__ == "__main__":
    unittest.main()
