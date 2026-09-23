import logging
from collections.abc import Mapping

from synapse.api.errors import SynapseError

from synapse_modules.channel_guard._logic import (
    is_channel_creation,
    mark_channel_room_type,
    role_may_create_channel,
)

logger = logging.getLogger(__name__)

_ROLE_ACCOUNT_DATA = "com.liza.user_role"
_DEFAULT_ROLE = "user"


class ChannelGuardModule:
    def __init__(self, config: dict, api) -> None:
        self._api = api
        api.register_third_party_rules_callbacks(
            on_create_room=self._on_create_room,
        )

    @staticmethod
    def parse_config(config: dict) -> dict:
        return config or {}

    async def _get_role(self, user_id: str) -> str:
        data = await self._api.account_data_manager.get_global(
            user_id, _ROLE_ACCOUNT_DATA
        )
        role = data.get("role") if isinstance(data, Mapping) else None
        return role or _DEFAULT_ROLE

    async def _on_create_room(
        self, requester, config: dict, is_requester_admin: bool
    ) -> None:
        if not is_channel_creation(config):
            return
        # Пометку типа ставим ДО проверки прав: если создание запретят, config
        # всё равно не используется, а порядок так не зависит от роли.
        if mark_channel_room_type(config):
            logger.info("channel_guard: каналу проставлен room_type для каталога")
        if is_requester_admin:
            return  # серверный админ Synapse всегда может
        user_id = requester.user.to_string()
        role = await self._get_role(user_id)
        if not role_may_create_channel(role):
            logger.warning(
                "channel_guard: blocked channel creation by %s (role=%s)",
                user_id,
                role,
            )
            raise SynapseError(
                403, "Создавать каналы могут только admin и moderator"
            )
