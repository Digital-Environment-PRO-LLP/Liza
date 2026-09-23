# -*- coding: utf-8 -*-
# ledger:RL-stories-publish-push AC:RL-stories-publish-push/1
# LABA-1970: пуш на публикацию сторис — текст «{автор} опубликовал историю».
# Проверяет ветки детекта com.liza.story в gcm/apns пушкинах: имя автора в
# заголовке (НЕ room_name "Stories - ivan"), тело «опубликовал историю», и
# top-level маркер story для нативного NSE/AppDelegate.

from types import SimpleNamespace
from unittest import TestCase

from sygnal._clean_body import STORY_PUBLISHED_BODY
from sygnal.apnspushkin import ApnsPushkin
from sygnal.gcmpushkin import GcmPushkin
from sygnal.notifications import Notification


def _story_notif(**over):
    raw = {
        "type": "m.room.message",
        "room_id": "!s:local",
        "event_id": "$e",
        "sender": "@ivan:local",
        "sender_display_name": "Иван",
        # room_name намеренно "Stories - ..." — штатный путь взял бы его в title.
        "room_name": "Stories - ivan",
        "content": {"com.liza.story": {"expires_ts": 1}},
        "devices": [],
    }
    raw.update(over)
    return Notification(raw)


class GcmStoryTextTestCase(TestCase):
    def test_android_title_is_author_body_is_published(self) -> None:
        notif = GcmPushkin._build_android_notification(_story_notif())
        # НЕ room_name "Stories - ivan", а имя автора.
        self.assertEqual(notif["title"], "Иван")
        self.assertEqual(notif["body"], STORY_PUBLISHED_BODY)

    def test_android_fallback_to_liza_without_sender_name(self) -> None:
        notif = GcmPushkin._build_android_notification(
            _story_notif(sender_display_name=None)
        )
        self.assertEqual(notif["title"], "Liza")
        self.assertEqual(notif["body"], STORY_PUBLISHED_BODY)

    def test_android_story_still_coalesces_by_room(self) -> None:
        notif = GcmPushkin._build_android_notification(_story_notif())
        # Серия сторис одного автора схлопывается OS по room_id.
        self.assertEqual(notif["tag"], "!s:local")


class ApnsStoryPayloadTestCase(TestCase):
    def _payload(self, n: Notification):
        # _get_payload_story использует только self.MAX_FIELD_LENGTH.
        stub = SimpleNamespace(MAX_FIELD_LENGTH=1024)
        device = SimpleNamespace(data=None)
        return ApnsPushkin._get_payload_story(
            stub, n, device, n.sender_display_name or " ", True
        )

    def test_literal_alert_author_and_published(self) -> None:
        payload = self._payload(_story_notif())
        alert = payload["aps"]["alert"]
        self.assertEqual(alert["title"], "Иван")
        self.assertEqual(alert["body"], STORY_PUBLISHED_BODY)

    def test_story_marker_and_top_level_fields(self) -> None:
        payload = self._payload(_story_notif())
        self.assertTrue(payload["story"])
        self.assertEqual(payload["sender_display_name"], "Иван")
        self.assertEqual(payload["type"], "m.room.message")
        self.assertEqual(payload["room_id"], "!s:local")
