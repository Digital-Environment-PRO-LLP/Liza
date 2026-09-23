"""Twisted-ресурсы access_admin.

Структура скопирована с user_roles/_api.py: чистые классы-обработчики
отдельно, тонкие ресурсы поверх.
"""

import json
import logging
from urllib.parse import unquote

from twisted.web import resource, server

from synapse.api.errors import AuthError, SynapseError
from synapse.logging.context import run_in_background
from synapse.types import UserID

logger = logging.getLogger(__name__)

_DENY_MESSAGES = {
    "self": "Нельзя деактивировать собственный аккаунт",
    "foreign_server": "Аккаунт принадлежит другому серверу",
    "forbidden": "Недостаточно прав",
}


class _JsonResource(resource.Resource):
    """Базовый ресурс с JSON-хелперами."""

    def _json_response(
        self, request: server.Request, data: dict, status: int = 200
    ) -> None:
        request.setResponseCode(status)
        request.setHeader(b"Content-Type", b"application/json")
        request.write(json.dumps(data).encode())
        request.finish()

    def _error(
        self, request: server.Request, error: str, message: str, status: int
    ) -> None:
        self._json_response(request, {"error": error, "message": message}, status)

    def _on_errback(self, failure, request: server.Request) -> None:
        logger.error("access_admin API error: %s", failure)
        if not request.finished:
            ex = failure.value
            if isinstance(ex, AuthError):
                self._error(
                    request, "unauthorized", "Missing or invalid access token", 401
                )
            elif isinstance(ex, SynapseError):
                self._error(request, ex.errcode, str(ex), ex.code)
            else:
                self._error(request, "internal_error", "Internal server error", 500)

    async def _authenticate(self, request: server.Request) -> str:
        requester = await self._module_api.get_user_by_req(request)
        return requester.user.to_string()

    def _extract_user_id(self, request: server.Request) -> str:
        path = (
            request.path.decode()
            if isinstance(request.path, bytes)
            else request.path
        )
        if path.startswith(self._path_prefix) and len(path) > len(self._path_prefix):
            user_id = unquote(path[len(self._path_prefix):]).lstrip("/")
            if not user_id:
                raise ValueError("Missing user_id in path")
            return user_id
        raise ValueError("Missing user_id in path")


class DossierResource(_JsonResource):
    """GET /_synapse/client/access/v1/dossier/<user_id>"""

    isLeaf = True

    def __init__(self, module_api, handler, path_prefix: str) -> None:
        super().__init__()
        self._module_api = module_api
        self._handler = handler
        self._path_prefix = path_prefix

    def render_GET(self, request: server.Request) -> int:
        d = run_in_background(self._handle_get, request)
        d.addErrback(self._on_errback, request)
        return server.NOT_DONE_YET

    async def _handle_get(self, request: server.Request) -> None:
        caller_id = await self._authenticate(request)
        try:
            target_id = self._extract_user_id(request)
        except ValueError:
            self._error(request, "bad_request", "Missing user_id in path", 400)
            return

        status, payload = await self._handler.dossier(caller_id, target_id)
        self._json_response(request, payload, status)


class SpaceMembersResource(_JsonResource):
    """GET /_synapse/client/access/v1/space_members/<space_id>"""

    isLeaf = True

    def __init__(self, module_api, handler, path_prefix: str) -> None:
        super().__init__()
        self._module_api = module_api
        self._handler = handler
        self._path_prefix = path_prefix

    def render_GET(self, request: server.Request) -> int:
        d = run_in_background(self._handle_get, request)
        d.addErrback(self._on_errback, request)
        return server.NOT_DONE_YET

    async def _handle_get(self, request: server.Request) -> None:
        caller_id = await self._authenticate(request)
        try:
            space_id = self._extract_user_id(request)
        except ValueError:
            self._error(request, "bad_request", "Missing space_id in path", 400)
            return

        status, payload = await self._handler.space_members(caller_id, space_id)
        self._json_response(request, payload, status)


class AccountStateResource(_JsonResource):
    """POST .../deactivate/<user_id> и .../reactivate/<user_id>"""

    isLeaf = True

    def __init__(self, module_api, handler, path_prefix: str, activate: bool) -> None:
        super().__init__()
        self._module_api = module_api
        self._handler = handler
        self._path_prefix = path_prefix
        self._activate = activate

    def render_POST(self, request: server.Request) -> int:
        d = run_in_background(self._handle_post, request)
        d.addErrback(self._on_errback, request)
        return server.NOT_DONE_YET

    async def _handle_post(self, request: server.Request) -> None:
        caller_id = await self._authenticate(request)
        try:
            target_id = self._extract_user_id(request)
        except ValueError:
            self._error(request, "bad_request", "Missing user_id in path", 400)
            return

        status, payload = await self._handler.set_state(
            caller_id, target_id, activate=self._activate
        )
        self._json_response(request, payload, status)


class AccessAdminHandler:
    """Бизнес-логика поверх проверки прав. Без знания о Twisted."""

    def __init__(
        self,
        permissions,
        dossier,
        accounts,
        module_api,
        server_name,
        store,
        space_members=None,
    ):
        self._permissions = permissions
        self._dossier = dossier
        self._accounts = accounts
        self._module_api = module_api
        self._server_name = server_name
        self._store = store
        self._space_members = space_members

    async def dossier(self, caller_id: str, target_id: str) -> tuple[int, dict]:
        # Права — ПЕРЕД любым обращением к данным цели: неавторизованный не
        # должен узнать даже принадлежность аккаунта к чужому серверу.
        if not await self._permissions.may_view(caller_id, target_id):
            return 403, {"error": "forbidden", "message": "Недостаточно прав"}

        is_local = target_id.endswith(":" + self._server_name)

        # get_userinfo_by_id читает таблицу users — только ЛОКАЛЬНЫЕ
        # аккаунты, для федеративного MXID она всегда None. Досье и роль
        # запрашиваем только для локальных; членства (groups) теперь
        # доступны для любого домена, известного нашему серверу.
        userinfo = None
        if is_local:
            userinfo = await self._module_api.get_userinfo_by_id(target_id)
            if userinfo is None:
                return 404, {"error": "not_found", "message": "Пользователь не найден"}

        # get_profileinfo принимает объект UserID и берёт хостнейм из него, а
        # не из ModuleApi.get_profile_for_user, который пересобирает MXID с
        # ЛОКАЛЬНЫМ hostname — так профиль не подменится хостнеймом сервера.
        profile = await self._store.get_profileinfo(UserID.from_string(target_id))
        groups = await self._dossier.collect(target_id)
        role = await self._role_view(target_id) if is_local else None

        return 200, {
            "user_id": target_id,
            "display_name": profile.display_name if profile else None,
            "avatar_url": profile.avatar_url if profile else None,
            "deactivated": bool(userinfo.is_deactivated) if userinfo else False,
            "is_local": is_local,
            "server": {"name": self._server_name, "role": role},
            **groups,
        }

    async def space_members(
        self, caller_id: str, space_id: str
    ) -> tuple[int, dict]:
        # Право проверяем ПЕРЕД данными — как в dossier. Здесь право на
        # ПРОСТРАНСТВО (space_id из URL), а не на пользователя.
        if not await self._permissions.may_view_space(caller_id, space_id):
            return 403, {"error": "forbidden", "message": "Недостаточно прав"}

        members = await self._space_members.collect(space_id)
        return 200, {"space_id": space_id, "members": members}

    async def _role_view(self, user_id: str) -> dict | None:
        from collections.abc import Mapping

        data = await self._module_api.account_data_manager.get_global(
            user_id, "com.liza.user_role"
        )
        if not isinstance(data, Mapping):
            return None
        role_v2 = data.get("role_v2")
        if isinstance(role_v2, Mapping):
            return dict(role_v2)
        code = data.get("role")
        return {"code": code, "label": code, "color": None} if code else None

    async def set_state(
        self, caller_id: str, target_id: str, *, activate: bool
    ) -> tuple[int, dict]:
        allowed, reason = await self._permissions.may_deactivate(
            caller_id, target_id
        )
        if not allowed:
            return 403, {
                "error": "forbidden",
                "message": _DENY_MESSAGES.get(reason, "Недостаточно прав"),
            }

        userinfo = await self._module_api.get_userinfo_by_id(target_id)
        if userinfo is None:
            return 404, {"error": "not_found", "message": "Пользователь не найден"}

        if activate:
            return 200, await self._accounts.reactivate(target_id)
        return 200, await self._accounts.deactivate(target_id)
