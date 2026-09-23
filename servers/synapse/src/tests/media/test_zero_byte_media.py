# Страж RL-zero-byte-media-upload-reject (серверная половина).
# ledger:RL-zero-byte-media-upload-reject
#
# Инцидент 2026-09-01: веб-клиент залил крупное видео как 0 байт (OOM вкладки
# при readAsBytes) → origin сохранил media_length=0, событие рекламировало
# реальный размер → у всех зрителей HTTP 500 (MMR «locating media: EOF»), вечный
# спиннер. Спека …-federated-video-mmr-open-range-and-web-upload-zero-byte.
#
# Серверная защита (два слоя):
#   AC-3 upload_resource: Content-Length: 0 → 400 (запись не создаётся);
#   AC-4 get_local_media_info: media_length==0 → 404 (не 40-байт multipart-EOF).

from typing import Dict

from twisted.internet.testing import MemoryReactor
from twisted.web.resource import Resource

from synapse.server import HomeServer
from synapse.util import Clock

from tests import unittest


class ZeroByteMediaTestCase(unittest.HomeserverTestCase):
    def prepare(
        self, reactor: MemoryReactor, clock: Clock, hs: HomeServer
    ) -> None:
        self.store = hs.get_datastores().main
        self.user = self.register_user("uploader", "pass")
        self.tok = self.login("uploader", "pass")

    def create_resource_dict(self) -> Dict[str, Resource]:
        resources = super().create_resource_dict()
        resources["/_matrix/media"] = self.hs.get_media_repository_resource()
        return resources

    # AC:RL-zero-byte-media-upload-reject/3
    def test_reject_zero_length_upload(self) -> None:
        """Заливка с Content-Length: 0 отклоняется 400, запись не создаётся."""
        channel = self.make_request(
            "POST",
            "/_matrix/media/v3/upload?filename=empty.mov",
            content=b"",
            access_token=self.tok,
            shorthand=False,
        )
        self.assertEqual(channel.code, 400, channel.result)
        # content_uri не выдан → фантомной записи media_length=0 не создано.
        self.assertNotIn("content_uri", channel.json_body)

    # AC:RL-zero-byte-media-upload-reject/4
    def test_zero_length_media_returns_404(self) -> None:
        """Download медиа с media_length==0 → честный 404 (не 40-байт-EOF/200)."""
        media_id = "zerolen0000000000000000"
        # Пишем фантом напрямую в стор (обходя upload-реджект), как если бы он
        # уже существовал в БД от прежней сборки без гейта.
        self.get_success(
            self.store.store_local_media(
                media_id=media_id,
                media_type="video/quicktime",
                time_now_ms=self.clock.time_msec(),
                upload_name="phantom.mov",
                media_length=0,
                user_id=self.user,
            )
        )
        channel = self.make_request(
            "GET",
            f"/_matrix/media/v3/download/{self.hs.hostname}/{media_id}",
            access_token=self.tok,
            shorthand=False,
        )
        self.assertEqual(channel.code, 404, channel.result)
