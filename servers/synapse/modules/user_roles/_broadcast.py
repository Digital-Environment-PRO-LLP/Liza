"""Push role-change events to clients via to-device messages.

NOTE: Uses Synapse's private ``_store.add_messages_to_device_inbox`` API. There
is no public ModuleApi method for module-originated to-device sending; we
verified the public surface on 2026-05-19. The private API has been stable
across Synapse 1.x and is used by production modules.
"""

import logging
from collections.abc import Mapping
from typing import TYPE_CHECKING, Iterable

from ._roles import ACCOUNT_DATA_TYPE

if TYPE_CHECKING:
    from ._catalog import RoleCatalog

logger = logging.getLogger(__name__)

EVENT_TYPE = "com.liza.user_role"


class RoleBroadcaster:
    """Sends role-change to-device events to user devices.

    Targets every device of every user who shares a room with the changed
    user (plus the changed user's own devices), using wildcard device_id="*"
    that Synapse expands to real device_ids server-side.
    """

    def __init__(self, hs, catalog: "RoleCatalog") -> None:
        self._hs = hs
        self._store = hs.get_datastores().main
        self._catalog = catalog

    async def broadcast_role_change(self, user_id: str) -> None:
        """Notify ``user_id`` and everyone who shares a room with them about
        the current role payload for ``user_id``. Reads role from account
        data, denormalizes through the catalog, then sends to-device events.
        """
        role_data = await self._store.get_global_account_data_by_type_for_user(
            user_id, ACCOUNT_DATA_TYPE
        )
        # Note: _store returns immutabledict for account_data (frozen via
        # synapse.util.frozenutils.freeze), not plain dict - check Mapping.
        role_code = role_data.get("role") if isinstance(role_data, Mapping) else None
        role_view = await self._catalog.enrich(role_code)
        content = {"user_id": user_id, "role": role_view}

        peers = await self._store.get_users_who_share_room_with_user(user_id)
        recipients = set(peers) | {user_id}
        await self._send_to_device(recipients, content)

    async def broadcast_catalog_patch(self, role_code: str) -> None:
        """When a catalog row changes (display_name or color), find every
        user who currently carries this role and re-broadcast their (now
        updated) view to everyone who can see them.
        """
        bearers = await self._catalog.users_with_role(role_code)
        for bearer in bearers:
            await self.broadcast_role_change(bearer)

    async def _send_to_device(
        self, user_ids: Iterable[str], content: dict
    ) -> None:
        user_ids = set(user_ids)
        if not user_ids:
            return
        message = {
            "type": EVENT_TYPE,
            "sender": self._sender(),
            "content": content,
        }
        local = {uid: {"*": message} for uid in user_ids}
        await self._store.add_messages_to_device_inbox(local, {})
        logger.info(
            "user_roles broadcast: recipients=%d type=%s",
            len(user_ids),
            EVENT_TYPE,
        )

    def _sender(self) -> str:
        """Pseudo user_id used as ``sender`` for the system-generated event."""
        server_name = getattr(self._hs, "hostname", None) or "user_roles_module"
        return f"@user_roles_module:{server_name}"
