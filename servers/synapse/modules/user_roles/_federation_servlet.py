"""Регистрация federation-эндпоинта ролей через TransportLayerServer.

Почему не register_web_resource: ``/_matrix/federation/*`` обслуживается
``TransportLayerServer``, который наследуется от ``JsonResource`` с
``isLeaf = True``. Это значит, что Twisted никогда не обходит детей этого
ресурса - вызывает render() сразу. Поэтому любой web-ресурс, повешенный
через ``ModuleApi.register_web_resource`` под путь, начинающийся с
``/_matrix/federation/``, недостижим: TransportLayerServer перехватывает
запрос и возвращает 404 Unrecognized request (так как пути у себя в
регистре не находит).

Решение: регистрируем наш federation-сервлет ВНУТРИ TransportLayerServer,
наследуясь от ``BaseFederationServlet`` (он автоматически получает
X-Matrix auth, federation_domain_whitelist, ratelimit). Регистрация
делается monkey-patch'ем module-level ``register_servlets`` -
TransportLayerServer.__init__ зовёт её сразу после создания, у нас нет
другого хука вмешаться. Patch ставится один раз при load модуля; после
первого вызова исходная функция восстановлена и patch снимается.

Альтернатива - hook на старт listeners и поиск TransportLayerServer в
resource tree - хрупкая (зависит от внутренней структуры дерева), и
никаких public API для этого Synapse не даёт.
"""

from __future__ import annotations

import logging
from collections.abc import Mapping
from typing import TYPE_CHECKING, Any, Optional

from synapse.federation.transport.server._base import (
    BaseFederationServlet,
)
from synapse.types import JsonDict

from ._roles import (
    ACCOUNT_DATA_TYPE,
    DEFAULT_ROLE,
    stored_extra_roles,
    with_extra_roles,
)

if TYPE_CHECKING:
    from synapse.federation.transport.server._base import Authenticator
    from synapse.http.server import HttpServer
    from synapse.module_api import ModuleApi
    from synapse.server import HomeServer
    from synapse.util.ratelimitutils import FederationRateLimiter

    from ._catalog import RoleCatalog

logger = logging.getLogger(__name__)


# Контейнер для зависимостей servlet'а. Заполняется при загрузке модуля,
# читается из class-level переменной в момент создания TransportLayerServer.
# Глобал нужен потому что Synapse конструирует BaseFederationServlet через
# свой register_servlets, не давая нам передать туда наши catalog/account_data.
_servlet_deps: dict[str, Any] = {}


_MAX_BATCH = 100


class UserRolesFederationServlet(BaseFederationServlet):
    """``GET /_matrix/federation/v1/com.liza/user_roles_batch?user_ids=...``

    Отвечает {code,label,color}|null для каждого ЛОКАЛЬНОГО user_id из
    запроса. Чужие user_ids молча игнорируются (анти-loop защита от
    ре-проксирования).

    X-Matrix-аутентификация, ratelimit и federation_domain_whitelist
    обеспечиваются базовым классом - до on_GET доходят только запросы с
    валидной подписью разрешённого homeserver-а.
    """

    PATH = "/com.liza/user_roles_batch"
    CATEGORY = "Liza user roles"

    async def on_GET(
        self,
        origin: str,
        content: Optional[bytes],
        query: dict[bytes, list[bytes]],
    ) -> tuple[int, JsonDict]:
        catalog: "RoleCatalog" = _servlet_deps["catalog"]
        account_data = _servlet_deps["account_data"]
        server_name: str = _servlet_deps["server_name"]

        raw = query.get(b"user_ids", [b""])[0]
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8", errors="replace")
        user_ids = [u.strip() for u in raw.split(",") if u.strip()]
        if not user_ids:
            return 400, {
                "errcode": "M_MISSING_PARAM",
                "error": "user_ids query parameter is required",
            }
        if len(user_ids) > _MAX_BATCH:
            return 400, {
                "errcode": "M_INVALID_PARAM",
                "error": f"Maximum {_MAX_BATCH} user_ids per request",
            }

        roles: dict[str, Optional[dict]] = {}
        for uid in user_ids:
            if ":" not in uid:
                continue
            domain = uid.split(":", 1)[1]
            if domain != server_name:
                continue
            try:
                data = await account_data.get_global(uid, ACCOUNT_DATA_TYPE)
            except Exception:
                data = None
            role_code = (
                data.get("role") if isinstance(data, Mapping) else None
            ) or DEFAULT_ROLE
            roles[uid] = with_extra_roles(
                await catalog.enrich(role_code), stored_extra_roles(data)
            )

        return 200, {"roles": roles}


def install_servlet(
    module_api: "ModuleApi",
    catalog: "RoleCatalog",
) -> None:
    """Регистрирует UserRolesFederationServlet в federation router.

    Monkey-patch'ит ``register_servlets`` в
    ``synapse.federation.transport.server.__init__``: после оригинальной
    регистрации Synapse'овых servlets зовём ``.register()`` нашего.
    Идемпотентно: повторный install не плодит дубли.
    """
    _servlet_deps["catalog"] = catalog
    _servlet_deps["account_data"] = module_api.account_data_manager
    _servlet_deps["server_name"] = module_api._hs.hostname

    # synapse.federation.transport.server - это пакет (__init__.py), а
    # register_servlets - в нём же. Импортируем модуль, чтобы patch'ить
    # атрибут на самом модуле (не на копии в нашем namespace).
    from synapse.federation.transport import server as fed_server_pkg

    if getattr(fed_server_pkg.register_servlets, "_user_roles_patched", False):
        logger.debug("UserRolesFederationServlet patch already installed")
        return

    original = fed_server_pkg.register_servlets

    def patched_register_servlets(
        hs: "HomeServer",
        resource: "HttpServer",
        authenticator: "Authenticator",
        ratelimiter: "FederationRateLimiter",
        servlet_groups: Any = None,
    ) -> None:
        original(
            hs,
            resource=resource,
            authenticator=authenticator,
            ratelimiter=ratelimiter,
            servlet_groups=servlet_groups,
        )
        # На federation listener Synapse вызывает register_servlets без
        # servlet_groups; на openid listener - с servlet_groups=["openid"].
        # Свой servlet регистрируем только в полном federation-роутере,
        # чтобы не светить ролями через openid resource.
        if servlet_groups is not None and "openid" in servlet_groups:
            return
        servlet = UserRolesFederationServlet(
            hs=hs,
            authenticator=authenticator,
            ratelimiter=ratelimiter,
            server_name=hs.hostname,
        )
        servlet.register(resource)
        logger.info(
            "UserRolesFederationServlet registered at %s%s",
            servlet.PREFIX,
            servlet.PATH,
        )

    patched_register_servlets._user_roles_patched = True  # type: ignore[attr-defined]
    fed_server_pkg.register_servlets = patched_register_servlets
    logger.info("UserRolesFederationServlet patch installed")
