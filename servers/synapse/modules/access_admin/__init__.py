"""Synapse-модуль управления доступами пользователей.

Привилегированная прослойка: клиент не может дёргать /_synapse/admin/*
(там нужен флаг users.admin), поэтому модуль сам проверяет право
вызывающего и выполняет действие от имени сервера.

Подключение в homeserver.yaml:

    modules:
      - module: synapse_modules.access_admin.AccessAdminModule
        config: {}
"""

import logging

from synapse.module_api import ModuleApi

from ._accounts import AccountManager
from ._api import (
    AccessAdminHandler,
    AccountStateResource,
    DossierResource,
    SpaceMembersResource,
)
from ._dossier import DossierBuilder
from ._logic import DEFAULT_BOT_LOCALPARTS, DEFAULT_BOTS_HOMESERVER
from ._permissions import PermissionChecker
from ._space_members import SpaceMembersBuilder

logger = logging.getLogger(__name__)

_BASE = "/_synapse/client/access/v1"


class AccessAdminModule:
    def __init__(self, config: dict, api: ModuleApi) -> None:
        self._api = api

        # ModuleApi не даёт публичного доступа к db_pool и хендлерам —
        # реальный HomeServer достаём через приватный api._hs. getattr с
        # дефолтом нужен для тестов, где ModuleApi замокан.
        hs = getattr(api, "_hs", None)
        store = hs.get_datastores().main
        server_name = hs.hostname

        dossier = DossierBuilder(
            store.db_pool,
            api.account_data_manager,
            server_name,
            bot_localparts=frozenset(
                config.get("bot_localparts", DEFAULT_BOT_LOCALPARTS)
            ),
            bots_homeserver=config.get(
                "bots_homeserver", DEFAULT_BOTS_HOMESERVER
            ),
        )
        permissions = PermissionChecker(
            account_data=api.account_data_manager,
            spaces_lookup=dossier,
            server_name=server_name,
            is_server_admin=api.is_user_admin,
        )
        accounts = AccountManager(
            store, hs.get_auth_handler(), hs.get_user_directory_handler()
        )
        space_members = SpaceMembersBuilder(store.db_pool)
        handler = AccessAdminHandler(
            permissions,
            dossier,
            accounts,
            api,
            server_name,
            store,
            space_members=space_members,
        )

        api.register_web_resource(
            f"{_BASE}/dossier",
            DossierResource(api, handler, f"{_BASE}/dossier"),
        )
        api.register_web_resource(
            f"{_BASE}/space_members",
            SpaceMembersResource(api, handler, f"{_BASE}/space_members"),
        )
        api.register_web_resource(
            f"{_BASE}/deactivate",
            AccountStateResource(
                api, handler, f"{_BASE}/deactivate", activate=False
            ),
        )
        api.register_web_resource(
            f"{_BASE}/reactivate",
            AccountStateResource(
                api, handler, f"{_BASE}/reactivate", activate=True
            ),
        )

        logger.info("AccessAdminModule loaded")

    @staticmethod
    def parse_config(config: dict) -> dict:
        return config or {}
