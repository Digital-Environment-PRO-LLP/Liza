"""Мягкая деактивация и реактивация аккаунта.

Намеренно НЕ используем DeactivateAccountHandler.deactivate_account(): он
необратимо обнуляет пароль, удаляет устройства, стирает account data и
E2EE-ключи и выкидывает пользователя из всех комнат с forget(). Ничего из
этого activate_account() не возвращает.

Здесь — три точечных действия: флаг, отзыв токенов, уход из поиска. Данные
и членства остаются нетронутыми, поэтому реактивация действительно
возвращает человека на место.
"""

import logging

from synapse.types import UserID

logger = logging.getLogger(__name__)


class AccountManager:
    def __init__(self, store, auth_handler, user_directory) -> None:
        self._store = store
        self._auth_handler = auth_handler
        self._user_directory = user_directory

    async def is_deactivated(self, user_id: str) -> bool:
        return await self._store.get_user_deactivated_status(user_id)

    async def deactivate(self, user_id: str) -> dict:
        if await self.is_deactivated(user_id):
            return {"user_id": user_id, "deactivated": True}

        # Флаг пишем store-методом, а не своим SQL: он инвалидирует кэши
        # get_user_deactivated_status / get_user_by_id / is_guest, без чего
        # логин продолжит проходить.
        await self._store.set_user_deactivated_status(user_id, True)
        await self._auth_handler.delete_access_tokens_for_user(user_id)
        await self._user_directory.handle_local_user_deactivated(user_id)

        logger.info("access_admin: аккаунт %s деактивирован (мягко)", user_id)
        return {"user_id": user_id, "deactivated": True}

    async def reactivate(self, user_id: str) -> dict:
        if not await self.is_deactivated(user_id):
            return {"user_id": user_id, "deactivated": False}

        # Порядок важен: сначала снять флаг, потом вернуть в user directory —
        # directory отфильтровывает деактивированных.
        await self._store.set_user_deactivated_status(user_id, False)
        user = UserID.from_string(user_id)
        profile = await self._store.get_profileinfo(user)
        await self._user_directory.handle_local_profile_change(user_id, profile)

        logger.info("access_admin: аккаунт %s реактивирован", user_id)
        return {"user_id": user_id, "deactivated": False}
