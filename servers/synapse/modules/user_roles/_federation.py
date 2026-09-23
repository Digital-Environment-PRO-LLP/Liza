"""Federation-проксирование ролей: исходящий клиент.

``FederationRolesClient`` для списка remote user_ids делает
X-Matrix-подписанный запрос на чужой HS и возвращает
``{user_id: RoleView|None}``. Группирует юзеров по domain, кэширует ответы
на 5 минут, ошибки и таймауты глотает (роль чужого юзера возвращается как
``None``, чтобы клиент мог нарисовать пользователя без роли вместо падения
экрана).

Входящий сервлет (тот, кто отвечает на чужие запросы) живёт в
``_federation_servlet.py``: он регистрируется внутри TransportLayerServer
через monkey-patch ``register_servlets``, потому что
``/_matrix/federation/*`` обслуживается ``JsonResource`` с
``isLeaf = True`` - туда нельзя добавить путь через
``ModuleApi.register_web_resource``.

Cache-инвалидация: TTL 5 минут, без явного invalidation. Если админ
поменял роль на удалённом HS, наш кэш протухнет максимум через TTL.
Это компромисс между нагрузкой на federation и свежестью данных.
"""

from __future__ import annotations

import logging
import time
from collections import defaultdict
from collections.abc import Mapping
from typing import TYPE_CHECKING, Optional

from ._roles import ACCOUNT_DATA_TYPE, DEFAULT_ROLE  # noqa: F401

if TYPE_CHECKING:
    from synapse.server import HomeServer

    from ._catalog import RoleCatalog

logger = logging.getLogger(__name__)


FEDERATION_PATH = "/_matrix/federation/v1/com.liza/user_roles_batch"
_DEFAULT_TTL_SEC = 300
_FED_TIMEOUT_MS = 5000


class FederationRolesClient:
    """Достаёт роли чужих юзеров через federation API.

    Использовать только для не-локальных user_ids: для локальных
    UserRoleHandler сам читает account_data.
    """

    def __init__(
        self,
        hs: "HomeServer",
        catalog: "RoleCatalog",
        *,
        ttl_sec: int = _DEFAULT_TTL_SEC,
    ) -> None:
        self._hs = hs
        self._catalog = catalog
        self._fed_http = hs.get_federation_http_client()
        self._server_name = hs.hostname
        # (destination, user_id) -> (RoleView_dict or None, expires_at_ts)
        self._cache: dict[
            tuple[str, str], tuple[Optional[dict], float]
        ] = {}
        self._ttl_sec = ttl_sec

    def _is_cached(self, destination: str, user_id: str, now: float) -> bool:
        cached = self._cache.get((destination, user_id))
        if cached is None:
            return False
        _, expires_at = cached
        return expires_at > now

    async def fetch_roles(
        self, user_ids: list[str]
    ) -> dict[str, Optional[dict]]:
        """Для каждого не-локального user_id вернуть RoleView dict или None.

        Локальные user_ids игнорируются (caller обрабатывает их через
        account_data).
        """

        by_domain: dict[str, list[str]] = defaultdict(list)
        for uid in user_ids:
            if not isinstance(uid, str) or ":" not in uid:
                continue
            localpart, _, domain = uid.partition(":")
            # Без localpart (например, ":host") - мусор, не лезем в federation.
            if not localpart or not domain:
                continue
            if domain == self._server_name:
                continue
            by_domain[domain].append(uid)

        result: dict[str, Optional[dict]] = {}
        now = time.time()

        for domain, uids in by_domain.items():
            fresh = [u for u in uids if not self._is_cached(domain, u, now)]
            if fresh:
                logger.info(
                    "fed roles fetch destination=%s count=%d",
                    domain,
                    len(fresh),
                )
                try:
                    fetched = await self._fetch_remote(domain, fresh)
                except Exception:
                    logger.exception(
                        "fed roles fetch failed for %s", domain
                    )
                    fetched = {u: None for u in fresh}
                expires_at = time.time() + self._ttl_sec
                for u in fresh:
                    # Если remote вернул не все user_ids - кэшируем None,
                    # чтобы не бить federation повторно в течение TTL.
                    self._cache[(domain, u)] = (
                        fetched.get(u),
                        expires_at,
                    )

            for u in uids:
                cached = self._cache.get((domain, u))
                result[u] = cached[0] if cached is not None else None

        return result

    async def _fetch_remote(
        self, destination: str, user_ids: list[str]
    ) -> dict[str, Optional[dict]]:
        """Сходить на чужой HS за ролями.

        MatrixFederationHttpClient.get_json подписывает запрос X-Matrix
        авторизацией автоматически. Path передаётся без префикса
        ``/_matrix/federation/v1`` - get_json его добавит сам.
        """

        args = {"user_ids": ",".join(user_ids)}
        response = await self._fed_http.get_json(
            destination=destination,
            path="/_matrix/federation/v1/com.liza/user_roles_batch",
            args=args,
            timeout=_FED_TIMEOUT_MS,
        )
        raw = response.get("roles", {}) if isinstance(response, Mapping) else {}
        if not isinstance(raw, Mapping):
            return {}
        # Защита от malicious remote: HS отдаёт нам данные только про своих
        # юзеров. Любой uid, чей server_name != destination, дропаем -
        # иначе remote мог бы засорить наш кэш ролями @someone:our_host.
        suffix = ":" + destination
        out: dict[str, Optional[dict]] = {}
        for uid, view in raw.items():
            if not isinstance(uid, str) or not uid.endswith(suffix):
                continue
            if isinstance(view, Mapping):
                out[uid] = dict(view)
            else:
                out[uid] = None
        return out
