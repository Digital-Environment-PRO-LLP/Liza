# -*- coding: utf-8 -*-
# ledger:RL-liza-news-platform-audience
# Адресная рассылка Liza News по платформам: Sygnal не шлёт пуш устройству, чьей
# платформы нет в content["com.liza.news.audience"].platforms, и НЕ кладёт его в
# rejected (иначе Synapse удалит живой pusher).

from typing import Any, Dict, List, Optional

from twisted.trial import unittest

from sygnal._news_audience import device_platform, should_skip
from sygnal.notifications import Device, Notification, NotificationContext, Pushkin

from tests import testutils

NEWS_BOT = "@liza-news:bots.liza.ru"

# Реальные формы pusher'ов с прода (pushers.data, 2026-09-21) без pushkey/url.
DEVICES: Dict[str, Dict[str, Any]] = {
    "ios": {
        "app_id": "ru.prodamus.liza",
        "data": {
            "data_message": "ios",
            "default_payload": {"client_name": "Liza ios", "aps": {}},
        },
    },
    "macos": {
        "app_id": "ru.prodamus.liza",
        "data": {
            "data_message": "ios",
            "default_payload": {"client_name": "Liza macos", "aps": {}},
        },
    },
    "android": {
        "app_id": "com.prodamus.laba.liza.data_message",
        "data": {"data_message": "android"},
    },
    # Легаси-аккаунт: один APNs topic на iOS и macOS, client_name нет.
    "legacy-apple": {
        "app_id": "com.prodamus.laba.liza",
        "data": {"data_message": "ios", "default_payload": {"aps": {}}},
    },
    # Второй аккаунт на устройстве: clientName = «Liza-<ms>», платформы нет.
    "second-account": {
        "app_id": "ru.prodamus.liza",
        "data": {
            "data_message": "ios",
            "default_payload": {"client_name": "Liza-1726912345678"},
        },
    },
    "unknown": {"app_id": "ru.prodamus.liza", "data": {}},
}

# Ожидаемая доставка: audience → множество устройств, которым пуш УЙДЁТ.
ALL = set(DEVICES)
EXPECTED_DELIVERED = {
    None: ALL,
    ("ios",): ALL - {"macos", "android"},
    ("macos",): ALL - {"ios", "android"},
    ("ios", "macos"): ALL - {"android"},
    ("android",): {"android", "unknown"},
    ("ios", "android"): ALL - {"macos"},
}


def _device(kind: str) -> Device:
    return Device({"pushkey": f"key-{kind}", **DEVICES[kind]})


def _notif(
    platforms: Optional[List[str]], sender: str = NEWS_BOT, devices=()
) -> Notification:
    content: Dict[str, Any] = {"msgtype": "m.text", "body": "Новость"}
    if platforms is not None:
        content["com.liza.news.audience"] = {"platforms": list(platforms)}
    return Notification(
        {"sender": sender, "content": content, "devices": list(devices)}
    )


class ShouldSkipTestCase(unittest.TestCase):
    def test_matrix_platform_by_audience(self) -> None:
        # AC:RL-liza-news-platform-audience/1
        for audience, delivered in EXPECTED_DELIVERED.items():
            n = _notif(list(audience) if audience else None)
            for kind in DEVICES:
                skipped = should_skip(n, _device(kind)) is not None
                self.assertEqual(
                    skipped,
                    kind not in delivered,
                    f"audience={audience} device={kind}",
                )

    def test_audience_only_from_news_bot(self) -> None:
        # AC:RL-liza-news-platform-audience/3
        # Метка от обычного участника не глушит пуши собеседникам.
        n = _notif(["android"], sender="@someone:tech.liza.ru")
        self.assertIsNone(should_skip(n, _device("ios")))

    def test_malformed_audience_is_everyone(self) -> None:
        # AC:RL-liza-news-platform-audience/4
        for bad in ({"platforms": []}, {"platforms": ["windows"]}, "ios", {"x": 1}):
            n = Notification(
                {
                    "sender": NEWS_BOT,
                    "content": {"body": "x", "com.liza.news.audience": bad},
                    "devices": [],
                }
            )
            self.assertIsNone(should_skip(n, _device("android")), repr(bad))

    def test_platform_detection(self) -> None:
        self.assertEqual(device_platform(_device("ios")), "ios")
        self.assertEqual(device_platform(_device("macos")), "macos")
        self.assertEqual(device_platform(_device("android")), "android")
        self.assertEqual(device_platform(_device("legacy-apple")), "apple")
        self.assertEqual(device_platform(_device("second-account")), "apple")
        self.assertIsNone(device_platform(_device("unknown")))
        debug = Device(
            {
                "pushkey": "k",
                "app_id": "ru.prodamus.liza",
                "data": {"default_payload": {"client_name": "Liza iosDebug"}},
            }
        )
        self.assertEqual(device_platform(debug), "ios")
        # Явное поле platform (новые сборки) главнее разбора client_name.
        explicit = Device(
            {
                "pushkey": "k",
                "app_id": "ru.prodamus.liza",
                "data": {
                    "default_payload": {
                        "platform": "macos",
                        "client_name": "Liza-1726912345678",
                    }
                },
            }
        )
        self.assertEqual(device_platform(explicit), "macos")
        fallback_android = Device(
            {"pushkey": "k", "app_id": "ru.prodamus.liza.data_message", "data": {}}
        )
        self.assertEqual(device_platform(fallback_android), "android")


class RecordingPushkin(Pushkin):
    dispatched: List[str] = []

    async def dispatch_notification(
        self, n: Notification, device: Device, context: NotificationContext
    ) -> List[str]:
        RecordingPushkin.dispatched.append(device.pushkey)
        return []


class NotifyEndpointTestCase(testutils.TestCase):
    """Реальный /_matrix/push/v1/notify: пуш не уходит в pushkin и не в rejected."""

    def config_setup(self, config: Dict[str, Any]) -> None:
        super().config_setup(config)
        for app_id in {d["app_id"] for d in DEVICES.values()}:
            config["apps"][app_id] = {
                "type": "tests.test_news_audience.RecordingPushkin"
            }

    def _post(self, platforms: Optional[List[str]]) -> Dict[str, Any]:
        RecordingPushkin.dispatched = []
        payload = self._make_dummy_notification(
            [{"pushkey": f"key-{k}", "pushkey_ts": 1, **d} for k, d in DEVICES.items()]
        )
        payload["notification"]["sender"] = NEWS_BOT
        if platforms is not None:
            payload["notification"]["content"]["com.liza.news.audience"] = {
                "platforms": platforms
            }
        return self._request(payload)

    def test_skipped_devices_not_dispatched_and_not_rejected(self) -> None:
        # AC:RL-liza-news-platform-audience/2
        for audience, delivered in EXPECTED_DELIVERED.items():
            response = self._post(list(audience) if audience else None)
            self.assertEqual(response, {"rejected": []}, f"audience={audience}")
            self.assertEqual(
                set(RecordingPushkin.dispatched),
                {f"key-{k}" for k in delivered},
                f"audience={audience}",
            )
