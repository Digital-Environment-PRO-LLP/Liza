from synapse.rest import admin
from synapse.rest.client import chat_topology, login

from tests import unittest


class ChatTopologyCapabilitiesTestCase(unittest.HomeserverTestCase):
    servlets = [
        admin.register_servlets,
        login.register_servlets,
        chat_topology.register_servlets,
    ]

    def prepare(self, reactor, clock, hs):
        self.user_id = self.register_user("alice", "pass")
        self.token = self.login("alice", "pass")
        devices = self.get_success(
            hs.get_datastores().main.get_devices_by_user(self.user_id)
        )
        self.device_id = list(devices.keys())[0]

    def test_put_capability_returns_200(self):
        channel = self.make_request(
            "PUT",
            f"/_matrix/client/unstable/com.liza/devices/{self.device_id}/capabilities",
            content={"platform": "android", "build": 3675},
            access_token=self.token,
        )
        self.assertEqual(channel.code, 200, channel.result)

    def test_put_capability_unknown_platform_returns_400(self):
        channel = self.make_request(
            "PUT",
            f"/_matrix/client/unstable/com.liza/devices/{self.device_id}/capabilities",
            content={"platform": "blackberry", "build": 1},
            access_token=self.token,
        )
        self.assertEqual(channel.code, 400, channel.result)

    def test_put_capability_foreign_device_returns_403(self):
        channel = self.make_request(
            "PUT",
            "/_matrix/client/unstable/com.liza/devices/SOME_OTHER_DEVICE/capabilities",
            content={"platform": "android", "build": 3675},
            access_token=self.token,
        )
        self.assertEqual(channel.code, 403, channel.result)
