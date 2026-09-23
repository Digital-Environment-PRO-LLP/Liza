"""Проверка прав вызывающего для операций управления доступами.

Право даёт: серверный admin-флаг Synapse (``users.admin``), либо роль admin
в каталоге user_roles, либо PL>=100 в пространстве, где состоит целевой
пользователь. Проверка живёт на сервере: клиент прячет UI для удобства, но
скрытая кнопка — не защита.
"""

from collections.abc import Awaitable, Callable, Mapping

from ._logic import ADMIN_POWER_LEVEL, MODERATOR_POWER_LEVEL

ROLE_ACCOUNT_DATA = "com.liza.user_role"
ROLE_ADMIN = "admin"

IsServerAdmin = Callable[[str], Awaitable[bool]]


class PermissionChecker:
    def __init__(
        self,
        account_data,
        spaces_lookup,
        server_name: str,
        is_server_admin: IsServerAdmin,
    ) -> None:
        self._account_data = account_data
        self._spaces = spaces_lookup
        self._server_name = server_name
        self._is_server_admin = is_server_admin

    async def _has_admin_role(self, user_id: str) -> bool:
        data = await self._account_data.get_global(user_id, ROLE_ACCOUNT_DATA)
        # get_global возвращает immutabledict, не dict — проверяем Mapping.
        role = data.get("role") if isinstance(data, Mapping) else None
        return role == ROLE_ADMIN

    async def _is_space_admin_over(self, caller_id: str, target_id: str) -> bool:
        powers = await self._spaces.shared_space_powers(caller_id, target_id)
        return any(power >= ADMIN_POWER_LEVEL for power in powers)

    async def may_view(self, caller_id: str, target_id: str) -> bool:
        if await self._is_server_admin(caller_id):
            return True
        if await self._has_admin_role(caller_id):
            return True
        return await self._is_space_admin_over(caller_id, target_id)

    async def may_view_space(self, caller_id: str, space_id: str) -> bool:
        """Право на список участников ПРОСТРАНСТВА (не пользователя).

        Порог — модератор (PL>=50), не админ: список участников space
        клиент показывает уже модератору (chat_topology.dart
        canSeeMembersAt), а не только тому, кто может им управлять.
        """
        if await self._is_server_admin(caller_id):
            return True
        if await self._has_admin_role(caller_id):
            return True
        power = await self._spaces.power_in_room(caller_id, space_id)
        return power >= MODERATOR_POWER_LEVEL

    async def may_deactivate(
        self, caller_id: str, target_id: str
    ) -> tuple[bool, str | None]:
        if caller_id == target_id:
            return False, "self"
        if not target_id.endswith(":" + self._server_name):
            return False, "foreign_server"
        if await self.may_view(caller_id, target_id):
            return True, None
        return False, "forbidden"
