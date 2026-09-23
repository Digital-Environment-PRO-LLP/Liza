"""Федеративный поиск пользователей по всем инстансам Liza.

Штатный /_matrix/client/v3/user_directory/search не федерируется: Synapse
ищет только по локальной таблице user_directory, а remote-профили попадают
в неё лишь при наличии общей комнаты. Поэтому пользователя со свежего
инстанса нельзя найти иначе как вводом полного MXID.

Модуль добавляет веер по federation_domain_whitelist: свои результаты
берём из штатного search_user_dir, чужие спрашиваем у соседей через
собственный federation-эндпоинт.
"""

import json
import logging
from typing import Any, Optional

from synapse.api.errors import AuthError, SynapseError
from synapse.logging.context import run_in_background
from synapse.module_api import ModuleApi
from twisted.web import resource, server

from ._federation import FederatedUserSearchClient
from ._federation_servlet import install_servlet
from ._search import (
    MIN_FEDERATED_QUERY_LEN,
    deduplicate_users,
    matches_prefix,
)

logger = logging.getLogger(__name__)

_MAX_RESULTS = 50


class UserSearchGuardModule:
    def __init__(self, config: dict[str, Any], api: ModuleApi) -> None:
        self._api = api
        # Корпоративный инстанс может не отдавать своих людей наружу,
        # продолжая при этом искать у других.
        self.share_users_over_federation = bool(
            config.get("share_users_over_federation", True)
        )
        self._fed_client = FederatedUserSearchClient(api._hs)

        install_servlet(api, self)
        api.register_web_resource(
            "/_synapse/client/user_search/v1/search",
            _UserSearchResource(api, self),
        )
        logger.info(
            "UserSearchGuardModule loaded (share_over_federation=%s)",
            self.share_users_over_federation,
        )

    def _federation_whitelist(self) -> list[str]:
        """Домены из federation_domain_whitelist.

        None означает «все домены разрешены» — в этом режиме веер не
        запускаем, чтобы не обходить весь интернет.
        """
        # _hs.config — internal API; публичного пути к конфигу через ModuleApi нет.
        wl = self._api._hs.config.federation.federation_domain_whitelist
        if not wl:
            return []
        return list(wl.keys())

    async def search_local_users(self, query: str, limit: int) -> list[dict]:
        """Локальные пользователи этого HS, совпадающие с query по префиксу."""
        server_name = self._api._hs.hostname
        # search_user_dir требует user_id запрашивающего; для федеративного
        # вызова подставляем служебный локальный id — фильтрация по общим
        # комнатам всё равно снята через search_all_users: true.
        result = await self._api._store.search_user_dir(
            f"@user_search_guard:{server_name}", query, limit,
        )

        out: list[dict] = []
        for item in result.get("results", []):
            user_id = item.get("user_id", "")
            if not user_id.endswith(":" + server_name):
                continue
            display_name = item.get("display_name")
            if not matches_prefix(display_name, user_id, query):
                continue
            out.append({
                "user_id": user_id,
                "display_name": display_name,
                "avatar_url": item.get("avatar_url"),
                "homeserver": server_name,
            })
        return out

    async def search(self, query: str, requester_id: str) -> list[dict]:
        """Свои + федеративные результаты, дедуп по user_id."""
        query = (query or "").strip()
        if not query:
            return []

        results = await self.search_local_users(query, _MAX_RESULTS)

        if len(query) >= MIN_FEDERATED_QUERY_LEN:
            domains = self._federation_whitelist()
            results.extend(await self._fed_client.search(query, domains))

        return deduplicate_users(results)[:_MAX_RESULTS]


class _UserSearchResource(resource.Resource):
    """GET /_synapse/client/user_search/v1/search?query= -> {results: [...]}."""

    isLeaf = True

    def __init__(self, api: ModuleApi, module: UserSearchGuardModule) -> None:
        super().__init__()
        self._api = api
        self._module = module

    def render_GET(self, request: server.Request) -> int:
        d = run_in_background(self._handle_get, request)
        d.addErrback(self._on_errback, request)
        return server.NOT_DONE_YET

    async def _handle_get(self, request: server.Request) -> None:
        requester = await self._api.get_user_by_req(request)  # требует валидный токен
        raw = request.args.get(b"query", [b""])[0]
        query = raw.decode("utf-8", "ignore").strip()
        results = await self._module.search(query, requester.user.to_string())
        self._json(request, {"results": results})

    def _json(self, request: server.Request, data: dict, status: int = 200) -> None:
        request.setResponseCode(status)
        request.setHeader(b"Content-Type", b"application/json")
        request.write(json.dumps(data).encode())
        request.finish()

    def _on_errback(self, failure, request: server.Request) -> None:
        if request.finished:
            return
        ex = failure.value
        if isinstance(ex, AuthError):
            self._json(request, {"error": "unauthorized"}, 401)
        elif isinstance(ex, SynapseError):
            self._json(request, {"error": ex.errcode}, ex.code)
        else:
            logger.error("user_search_guard endpoint error: %s", failure)
            self._json(request, {"error": "internal_error"}, 500)
