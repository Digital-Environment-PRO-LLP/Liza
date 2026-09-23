# -*- coding: utf-8 -*-
# Copyright 2025 New Vector Ltd.
# Copyright 2019 The Matrix.org Foundation C.I.C.
#
# SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
# Please see LICENSE files in the repository root for full details.
#
# Originally licensed under the Apache License, Version 2.0:
# <http://www.apache.org/licenses/LICENSE-2.0>.
from typing import Any, Dict
from unittest.mock import MagicMock, patch

from aioapns.common import NotificationResult, PushType

from sygnal import apnstruncate
from sygnal.apnspushkin import ApnsPushkin

from tests import testutils

PUSHKIN_ID = "com.example.apns"
PUSHKIN_ID_WITH_PUSH_TYPE = "com.example.apns.push_type"

TEST_CERTFILE_PATH = "/path/to/my/certfile.pem"

DEVICE_EXAMPLE = {"app_id": "com.example.apns", "pushkey": "spqr", "pushkey_ts": 42}
DEVICE_EXAMPLE_WITH_DEFAULT_PAYLOAD = {
    "app_id": "com.example.apns",
    "pushkey": "spqr",
    "pushkey_ts": 42,
    "data": {
        "default_payload": {
            "aps": {
                "mutable-content": 1,
                "alert": {"loc-key": "SINGLE_UNREAD", "loc-args": []},
            }
        }
    },
}

DEVICE_EXAMPLE_WITH_BAD_DEFAULT_PAYLOAD = {
    "app_id": "com.example.apns",
    "pushkey": "badpayload",
    "pushkey_ts": 42,
    "data": {"default_payload": None},
}

DEVICE_EXAMPLE_FOR_PUSH_TYPE_PUSHKIN = {
    "app_id": "com.example.apns.push_type",
    "pushkey": "spqr",
    "pushkey_ts": 42,
}

# Зеркалит боевой default_payload клиента (background_push.dart): mutable-content
# для NSE + звук, но БЕЗ aps.alert. На таком payload баннер рисует NSE, а prio=10
# всё равно легален по критерию Apple (есть aps.sound). Нужен для RL-apns-alert-
# priority AC-3: event_id_only-пуш с этим default_payload → priority == 10.
DEVICE_EXAMPLE_WITH_SOUND_DEFAULT_PAYLOAD = {
    "app_id": "com.example.apns",
    "pushkey": "spqr",
    "pushkey_ts": 42,
    "data": {
        "default_payload": {
            "aps": {
                "mutable-content": 1,
                "sound": "liza_ding.aiff",
            }
        }
    },
}


class ApnsTestCase(testutils.TestCase):
    def setUp(self) -> None:
        self.apns_mock_class = patch("sygnal.apnspushkin.APNs").start()
        self.apns_mock = MagicMock()
        self.apns_mock_class.return_value = self.apns_mock

        # pretend our certificate exists
        patch("os.path.exists", lambda x: x == TEST_CERTFILE_PATH).start()
        # Since no certificate exists, don't try to read it.
        patch("sygnal.apnspushkin.ApnsPushkin._report_certificate_expiration").start()
        self.addCleanup(patch.stopall)

        super().setUp()

        self.apns_pushkin_snotif = MagicMock()
        test_pushkin = self.get_test_pushkin(PUSHKIN_ID)
        test_pushkin_push_type = self.get_test_pushkin(PUSHKIN_ID_WITH_PUSH_TYPE)
        # type safety: using ignore here due to mypy not handling monkeypatching,
        # see https://github.com/python/mypy/issues/2427
        test_pushkin._send_notification = self.apns_pushkin_snotif  # type: ignore[assignment] # noqa: E501
        test_pushkin_push_type._send_notification = self.apns_pushkin_snotif  # type: ignore[assignment] # noqa: E501

    def get_test_pushkin(self, name: str) -> ApnsPushkin:
        test_pushkin = self.sygnal.pushkins[name]
        assert isinstance(test_pushkin, ApnsPushkin)
        return test_pushkin

    def config_setup(self, config: Dict[str, Any]) -> None:
        super().config_setup(config)
        config["apps"][PUSHKIN_ID] = {"type": "apns", "certfile": TEST_CERTFILE_PATH}
        config["apps"][PUSHKIN_ID_WITH_PUSH_TYPE] = {
            "type": "apns",
            "certfile": TEST_CERTFILE_PATH,
            "push_type": "alert",
        }

    def test_payload_truncation(self) -> None:
        """
        Tests that APNS message bodies will be truncated to fit the limits of
        APNS.
        """
        # Arrange
        method = self.apns_pushkin_snotif
        method.side_effect = testutils.make_async_magic_mock(
            NotificationResult("notID", "200")
        )
        test_pushkin = self.get_test_pushkin(PUSHKIN_ID)
        test_pushkin.MAX_JSON_BODY_SIZE = 240

        # Act
        self._request(self._make_dummy_notification([DEVICE_EXAMPLE]))

        # Assert
        self.assertEqual(1, method.call_count)
        ((notification_req,), _kwargs) = method.call_args
        payload = notification_req.message

        self.assertLessEqual(len(apnstruncate.json_encode(payload)), 240)

    def test_payload_truncation_test_validity(self) -> None:
        """
        This tests that L{test_payload_truncation_success} is a valid test
        by showing that not limiting the truncation size would result in a
        longer message.
        """
        # Arrange
        method = self.apns_pushkin_snotif
        method.side_effect = testutils.make_async_magic_mock(
            NotificationResult("notID", "200")
        )
        test_pushkin = self.get_test_pushkin(PUSHKIN_ID)
        test_pushkin.MAX_JSON_BODY_SIZE = 4096

        # Act
        self._request(self._make_dummy_notification([DEVICE_EXAMPLE]))

        # Assert
        self.assertEqual(1, method.call_count)
        ((notification_req,), _kwargs) = method.call_args
        payload = notification_req.message

        self.assertGreater(len(apnstruncate.json_encode(payload)), 200)

    def test_expected(self) -> None:
        """AC:RL-apns-alert-priority/7 — приоритетный фикс НЕ меняет payload:
        ассерт сверяет ВЕСЬ notification_req.message целиком, поэтому любая
        подмена содержимого (а не только заголовков) красит тест.

        Tests the expected case: a good response from APNS means we pass on
        a good response to the homeserver.
        """
        # Arrange
        method = self.apns_pushkin_snotif
        method.side_effect = testutils.make_async_magic_mock(
            NotificationResult("notID", "200")
        )

        # Act
        resp = self._request(self._make_dummy_notification([DEVICE_EXAMPLE]))

        # Assert
        self.assertEqual(1, method.call_count)
        ((notification_req,), _kwargs) = method.call_args

        self.assertEqual(
            {
                "room_id": "!slw48wfj34rtnrf:example.com",
                "event_id": "$qTOWWTEL48yPm3uT-gdNhFcoHxfKbZuqRVnnWWSkGBs",
                "aps": {
                    "alert": {
                        "loc-key": "MSG_FROM_USER_IN_ROOM_WITH_CONTENT",
                        "loc-args": [
                            "Major Tom",
                            "Mission Control",
                            "I'm floating in a most peculiar way.",
                        ],
                    },
                    "badge": 3,
                },
                "content": {
                    "msgtype": "m.text",
                    "body": "I'm floating in a most peculiar way.",
                },
                "counts": '{"unread": 2, "missed_calls": 1}',
                "room_name": "Mission Control",
                "sender": "@exampleuser:matrix.org",
                "sender_display_name": "Major Tom",
                "type": "m.room.message",
            },
            notification_req.message,
        )

        self.assertEqual({"rejected": []}, resp)

    def test_expected_event_id_only_with_default_payload(self) -> None:
        """
        Tests the expected fallback case: a good response from APNS means we pass on
        a good response to the homeserver.
        """
        # Arrange
        method = self.apns_pushkin_snotif
        method.side_effect = testutils.make_async_magic_mock(
            NotificationResult("notID", "200")
        )

        # Act
        resp = self._request(
            self._make_dummy_notification_event_id_only(
                [DEVICE_EXAMPLE_WITH_DEFAULT_PAYLOAD]
            )
        )

        # Assert
        self.assertEqual(1, method.call_count)
        ((notification_req,), _kwargs) = method.call_args

        self.assertEqual(
            {
                "room_id": "!slw48wfj34rtnrf:example.com",
                "event_id": "$qTOWWTEL48yPm3uT-gdNhFcoHxfKbZuqRVnnWWSkGBs",
                "unread_count": 2,
                "aps": {
                    "alert": {"loc-key": "SINGLE_UNREAD", "loc-args": []},
                    "mutable-content": 1,
                },
            },
            notification_req.message,
        )

        self.assertEqual({"rejected": []}, resp)

    def test_expected_badge_only_with_default_payload(self) -> None:
        """
        Tests the expected fallback case: a good response from APNS means we pass on
        a good response to the homeserver.
        """
        # Arrange
        method = self.apns_pushkin_snotif
        method.side_effect = testutils.make_async_magic_mock(
            NotificationResult("notID", "200")
        )

        # Act
        resp = self._request(
            self._make_dummy_notification_badge_only(
                [DEVICE_EXAMPLE_WITH_DEFAULT_PAYLOAD]
            )
        )

        # Assert
        self.assertEqual(1, method.call_count)
        ((notification_req,), _kwargs) = method.call_args

        self.assertEqual(
            {"aps": {"badge": 2}, "counts": '{"unread": 2}'},
            notification_req.message,
        )

        self.assertEqual({"rejected": []}, resp)

    def test_expected_full_with_default_payload(self) -> None:
        """
        Tests the expected fallback case: a good response from APNS means we pass on
        a good response to the homeserver.
        """
        # Arrange
        method = self.apns_pushkin_snotif
        method.side_effect = testutils.make_async_magic_mock(
            NotificationResult("notID", "200")
        )

        # Act
        resp = self._request(
            self._make_dummy_notification([DEVICE_EXAMPLE_WITH_DEFAULT_PAYLOAD])
        )

        # Assert
        self.assertEqual(1, method.call_count)
        ((notification_req,), _kwargs) = method.call_args

        self.assertEqual(
            {
                "room_id": "!slw48wfj34rtnrf:example.com",
                "event_id": "$qTOWWTEL48yPm3uT-gdNhFcoHxfKbZuqRVnnWWSkGBs",
                "aps": {
                    "alert": {
                        "loc-key": "MSG_FROM_USER_IN_ROOM_WITH_CONTENT",
                        "loc-args": [
                            "Major Tom",
                            "Mission Control",
                            "I'm floating in a most peculiar way.",
                        ],
                    },
                    "badge": 3,
                    "mutable-content": 1,
                },
                "content": {
                    "msgtype": "m.text",
                    "body": "I'm floating in a most peculiar way.",
                },
                "counts": '{"unread": 2, "missed_calls": 1}',
                "room_name": "Mission Control",
                "sender": "@exampleuser:matrix.org",
                "sender_display_name": "Major Tom",
                "type": "m.room.message",
            },
            notification_req.message,
        )

        self.assertEqual({"rejected": []}, resp)

    def test_misconfigured_payload_is_rejected(self) -> None:
        """Test that a malformed default_payload causes pushkey to be rejected"""

        resp = self._request(
            self._make_dummy_notification([DEVICE_EXAMPLE_WITH_BAD_DEFAULT_PAYLOAD])
        )

        self.assertEqual({"rejected": ["badpayload"]}, resp)

    def test_rejection(self) -> None:
        """
        Tests the rejection case: a rejection response from APNS leads to us
        passing on a rejection to the homeserver.
        """
        # Arrange
        method = self.apns_pushkin_snotif
        method.side_effect = testutils.make_async_magic_mock(
            NotificationResult("notID", "410", description="Unregistered")
        )

        # Act
        resp = self._request(self._make_dummy_notification([DEVICE_EXAMPLE]))

        # Assert
        self.assertEqual(1, method.call_count)
        self.assertEqual({"rejected": ["spqr"]}, resp)

    def test_no_retry_on_4xx(self) -> None:
        """
        Test that we don't retry when we get a 4xx error but do not mark as
        rejected.
        """
        # Arrange
        method = self.apns_pushkin_snotif
        method.side_effect = testutils.make_async_magic_mock(
            NotificationResult("notID", "429", description="TooManyRequests")
        )

        # Act
        resp = self._request(self._make_dummy_notification([DEVICE_EXAMPLE]))

        # Assert
        self.assertEqual(1, method.call_count)
        self.assertEqual(502, resp)

    def test_retry_on_5xx(self) -> None:
        """
        Test that we DO retry when we get a 5xx error and do not mark as
        rejected.
        """
        # Arrange
        method = self.apns_pushkin_snotif
        method.side_effect = testutils.make_async_magic_mock(
            NotificationResult("notID", "503", description="ServiceUnavailable")
        )

        # Act
        resp = self._request(self._make_dummy_notification([DEVICE_EXAMPLE]))

        # Assert
        self.assertGreater(method.call_count, 1)
        self.assertEqual(502, resp)

    def test_expected_with_push_type(self) -> None:
        """
        Tests the expected case: a good response from APNS means we pass on
        a good response to the homeserver.
        """
        # Arrange
        method = self.apns_pushkin_snotif
        method.side_effect = testutils.make_async_magic_mock(
            NotificationResult("notID", "200")
        )

        # Act
        resp = self._request(
            self._make_dummy_notification([DEVICE_EXAMPLE_FOR_PUSH_TYPE_PUSHKIN])
        )

        # Assert
        self.assertEqual(1, method.call_count)
        ((notification_req,), _kwargs) = method.call_args

        self.assertEqual(
            {
                "room_id": "!slw48wfj34rtnrf:example.com",
                "event_id": "$qTOWWTEL48yPm3uT-gdNhFcoHxfKbZuqRVnnWWSkGBs",
                "aps": {
                    "alert": {
                        "loc-key": "MSG_FROM_USER_IN_ROOM_WITH_CONTENT",
                        "loc-args": [
                            "Major Tom",
                            "Mission Control",
                            "I'm floating in a most peculiar way.",
                        ],
                    },
                    "badge": 3,
                },
                "content": {
                    "msgtype": "m.text",
                    "body": "I'm floating in a most peculiar way.",
                },
                "counts": '{"unread": 2, "missed_calls": 1}',
                "room_name": "Mission Control",
                "sender": "@exampleuser:matrix.org",
                "sender_display_name": "Major Tom",
                "type": "m.room.message",
            },
            notification_req.message,
        )

        self.assertEqual(PushType.ALERT, notification_req.push_type)

        # AC:RL-apns-alert-priority/8 — приоритет и push_type сосуществуют: даже
        # для pushkin с push_type=alert обычное сообщение уходит priority == 10.
        self.assertEqual(10, notification_req.priority)

        self.assertEqual({"rejected": []}, resp)

    # ------------------------------------------------------------------
    # RL-apns-alert-priority — приоритет доставки APNs по содержимому payload.
    #
    # Synapse шлёт prio="low" для всех обычных (не-highlight/не-encrypted)
    # сообщений (httppusher.py:472-480). Раньше apnspushkin понижал такие пуши до
    # APNs prio=5, а Apple низкоприоритетные пуши коалесцирует/придерживает
    # минутами → баннер приходил через ~10 мин, уже после прочтения. Фикс: prio=10
    # для видимых alert-пушей (aps несёт alert/sound/badge), prio=5 только для
    # истинно тихих. Матрица обязательно с prio:"low" — dummy по умолчанию "high"
    # (testutils.py) замаскировал бы регресс. Ассерт на РЕАЛЬНОМ NotificationRequest.
    # ------------------------------------------------------------------

    def _priority_of(self, notification: Dict[str, Any]) -> int:
        """Диспатчит notification и возвращает NotificationRequest.priority."""
        method = self.apns_pushkin_snotif
        method.side_effect = testutils.make_async_magic_mock(
            NotificationResult("notID", "200")
        )
        self._request(notification)
        self.assertEqual(1, method.call_count)
        ((notification_req,), _kwargs) = method.call_args
        return notification_req.priority

    def test_priority_text_message_low_prio_is_high(self) -> None:
        """ledger:RL-apns-alert-priority
        AC:RL-apns-alert-priority/1 — обычное текстовое сообщение (aps.alert),
        Synapse прислал prio="low" → APNs priority == 10 (немедленная доставка)."""
        notif = self._make_dummy_notification([DEVICE_EXAMPLE])
        notif["notification"]["prio"] = "low"
        self.assertEqual(10, self._priority_of(notif))

    def test_priority_media_message_low_prio_is_high(self) -> None:
        """AC:RL-apns-alert-priority/2 — медиа-пуш (m.image → aps.alert),
        prio="low" → priority == 10."""
        notif = self._make_dummy_notification([DEVICE_EXAMPLE])
        notif["notification"]["prio"] = "low"
        notif["notification"]["content"] = {"msgtype": "m.image", "body": "photo.jpg"}
        self.assertEqual(10, self._priority_of(notif))

    def test_priority_event_id_only_with_sound_is_high(self) -> None:
        """AC:RL-apns-alert-priority/3 — event_id_only-пуш (mention/e2ee, баннер
        рисует NSE, aps.alert НЕТ) с боевым default_payload (aps.sound),
        prio="low" → priority == 10 (aps.sound делает prio=10 легальным у Apple)."""
        notif = self._make_dummy_notification_event_id_only(
            [DEVICE_EXAMPLE_WITH_SOUND_DEFAULT_PAYLOAD]
        )
        notif["notification"]["prio"] = "low"
        self.assertEqual(10, self._priority_of(notif))

    def test_priority_story_low_prio_is_high(self) -> None:
        """AC:RL-apns-alert-priority/4 — story-пуш (com.liza.story → aps.alert),
        prio="low" → priority == 10."""
        notif = self._make_dummy_notification([DEVICE_EXAMPLE])
        notif["notification"]["prio"] = "low"
        notif["notification"]["room_name"] = "Stories - ivan"
        notif["notification"]["content"] = {"com.liza.story": {"expires_ts": 1}}
        self.assertEqual(10, self._priority_of(notif))

    def test_priority_silent_payload_without_aps_content_is_low(self) -> None:
        """AC:RL-apns-alert-priority/5 (red-proof, обратен AC-1) — event_id_only-пуш
        БЕЗ default_payload (пустой aps, нет alert/sound/badge) → priority == 5.
        Так тихий фон не будит экран; если фикс форсит 10 всем подряд — падает."""
        notif = self._make_dummy_notification_event_id_only([DEVICE_EXAMPLE])
        notif["notification"]["prio"] = "low"
        self.assertEqual(5, self._priority_of(notif))

    def test_priority_counts_only_without_badge_is_not_dispatched(self) -> None:
        """AC:RL-apns-alert-priority/6 — counts-only пуш без loc_key и без badge
        (пустой counts) → _get_payload_full == None → диспатча нет вовсе
        (регресс-якорь: приоритет к нему не применяется)."""
        method = self.apns_pushkin_snotif
        method.side_effect = testutils.make_async_magic_mock(
            NotificationResult("notID", "200")
        )
        notif = {
            "notification": {
                "id": "",
                "type": None,
                "sender": "",
                "counts": {},
                "devices": [DEVICE_EXAMPLE],
            }
        }
        self._request(notif)
        self.assertEqual(0, method.call_count)
