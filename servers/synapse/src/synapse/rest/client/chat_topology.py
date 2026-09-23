import logging
from typing import TYPE_CHECKING

from pydantic import StrictInt, StrictStr

from synapse.api.errors import Codes, SynapseError
from synapse.http.server import HttpServer
from synapse.http.servlet import RestServlet, parse_and_validate_json_object_from_request
from synapse.http.site import SynapseRequest
from synapse.rest.client._base import client_patterns
from synapse.types import JsonDict
from synapse.types.rest import RequestBodyModel

if TYPE_CHECKING:
    from synapse.server import HomeServer

logger = logging.getLogger(__name__)

KNOWN_PLATFORMS = ("ios", "macos", "android", "windows", "web")


class DeviceCapabilitiesRestServlet(RestServlet):
    PATTERNS = client_patterns(
        "/com.liza/devices/(?P<device_id>[^/]*)/capabilities$", unstable=True
    )
    CATEGORY = "Client API requests"

    def __init__(self, hs: "HomeServer"):
        super().__init__()
        self.hs = hs
        self.auth = hs.get_auth()

    class PutBody(RequestBodyModel):
        platform: StrictStr
        build: StrictInt

    async def on_PUT(
        self, request: SynapseRequest, device_id: str
    ) -> tuple[int, JsonDict]:
        requester = await self.auth.get_user_by_req(request)

        if requester.device_id != device_id:
            raise SynapseError(403, "Can only set capabilities for own device", Codes.FORBIDDEN)

        body = parse_and_validate_json_object_from_request(request, self.PutBody)

        if body.platform not in KNOWN_PLATFORMS:
            raise SynapseError(400, "Unknown platform", Codes.INVALID_PARAM)

        # Атрибут читаем лениво на каждый запрос, а не кешируем в __init__:
        # в проде _base.py грузит модули раньше, чем строится ClientRestResource,
        # так что на момент __init__ атрибут уже был бы доступен. Но тестовый
        # харнесс (tests/unittest.py HomeserverTestCase) строит сервлеты через
        # create_resource_dict и никогда не прогоняет цикл загрузки модулей из
        # конфига — там self.hs.liza_chat_topology_sync_gate_module не появится
        # вообще, ни в __init__, ни позже. getattr с default=None делает оба
        # случая (модуль не загружен / модуль ещё не успел проставить атрибут)
        # безопасными без падения.
        module = getattr(self.hs, "liza_chat_topology_sync_gate_module", None)
        if module is not None:
            build_increased = await module.capabilities_store.upsert_capability(
                device_id=device_id,
                user_id=requester.user.to_string(),
                platform=body.platform,
                build=body.build,
            )
            if build_increased and await module.device_passed_gate(device_id):
                await module.forced_full_state.mark(device_id)

        return 200, {}


def register_servlets(hs: "HomeServer", http_server: HttpServer) -> None:
    DeviceCapabilitiesRestServlet(hs).register(http_server)
