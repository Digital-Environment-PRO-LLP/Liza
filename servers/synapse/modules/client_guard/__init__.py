"""Synapse module to restrict login to Liza clients only."""

import logging
from typing import Any, Collection, Dict, Optional, Tuple, Union

from synapse.module_api import ModuleApi
from synapse.api.errors import Codes

logger = logging.getLogger(__name__)

ALLOWED_PREFIX = "Liza"
NOT_SPAM = "NOT_SPAM"


class ClientGuardModule:
    """Blocks login attempts from non-Liza Matrix clients.

    Checks initial_device_display_name during login. The Liza client
    sends names like 'Liza Android', 'Liza iOS', 'Liza web', etc.

    Configuration in homeserver.yaml:

        modules:
          - module: synapse_modules.client_guard.ClientGuardModule
            config:
              allowed_prefix: "Liza"
    """

    def __init__(self, config: dict[str, Any], api: ModuleApi) -> None:
        self._api = api
        self._allowed_prefix = config.get("allowed_prefix", ALLOWED_PREFIX)

        api.register_spam_checker_callbacks(
            check_login_for_spam=self._check_login_for_spam,
        )

        logger.info(
            "ClientGuardModule loaded (allowed_prefix=%s)",
            self._allowed_prefix,
        )

    async def _check_login_for_spam(
        self,
        user_id: str,
        device_id: Optional[str],
        initial_device_display_name: Optional[str],
        request_info: Collection[Tuple[Optional[str], str]],
        auth_provider_id: Optional[str] = None,
    ) -> Union[str, Tuple[Codes, Dict[str, Any]]]:
        """Called on every login attempt.

        Returns NOT_SPAM to allow, or (Codes.FORBIDDEN, dict) to deny.
        """
        display_name = initial_device_display_name or ""

        if display_name.startswith(self._allowed_prefix):
            logger.debug(
                "ClientGuard: allowing login for %s (device_name=%s)",
                user_id,
                display_name,
            )
            return NOT_SPAM

        logger.warning(
            "ClientGuard: BLOCKED login for %s "
            "(device_name=%r, device_id=%s)",
            user_id,
            display_name,
            device_id,
        )
        return (
            Codes.FORBIDDEN,
            {"error": "This server only accepts the Liza client."},
        )
