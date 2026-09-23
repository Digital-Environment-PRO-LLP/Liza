#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Copyright 2025 The Matrix.org Foundation C.I.C.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import json
import logging
from typing import TYPE_CHECKING, Any, Dict, List, Optional

from twisted.internet import defer
from twisted.web.client import readBody

from sygnal.helper.context_factory import ClientTLSOptionsFactory
from sygnal.notifications import ConcurrencyLimitedPushkin, Device, Notification
from sygnal.utils import twisted_sleep

if TYPE_CHECKING:
    from sygnal.sygnal import Sygnal

logger = logging.getLogger(__name__)


class ExpoResponse:
    def __init__(self, response_text: str):
        try:
            self.response_json = json.loads(response_text)
        except json.JSONDecodeError:
            self.response_json = {}
        
        self.success = self.response_json.get("data", {}).get("status") == "ok"
        self.retry_after = None  # Expo API doesn't use retry-after headers typically


class ExpoPushkin(ConcurrencyLimitedPushkin):
    """
    A pushkin that sends push notifications via Expo Push API.
    """

    UNDERSTOOD_CONFIG_FIELDS = {
        "type",
        "url",
        "inflight_request_limit",
    } | ConcurrencyLimitedPushkin.UNDERSTOOD_CONFIG_FIELDS

    def __init__(self, name: str, sygnal: "Sygnal", config: Dict[str, Any]) -> None:
        super().__init__(name, sygnal, config)

        self.url = config.get("url", "https://exp.host/--/api/v2/push/send")
        
        self.http_agent = self.sygnal.http_agent_wrapper.agent
        self.tls_client_options_factory = ClientTLSOptionsFactory()

    async def _perform_http_request(
        self,
        body: bytes,
        headers: Dict[str, List[str]],
    ) -> ExpoResponse:
        """
        Perform an HTTP request to the Expo Push API.
        """
        response = await self.http_agent.request(
            b"POST",
            self.url.encode(),
            bodyProducer=self._encode_body(body),
            headers=headers,
            contextFactory=self.tls_client_options_factory,
        )

        response_text = (await readBody(response)).decode()
        
        logger.info(
            f"Expo API response: status={response.code}, body={response_text}"
        )

        return ExpoResponse(response_text)

    def _encode_body(self, body: bytes):
        """
        Helper to create a body producer for the HTTP request.
        """
        from twisted.web.client import FileBodyProducer
        from io import BytesIO
        
        return FileBodyProducer(BytesIO(body))

    async def _dispatch_notification_unlimited(
        self,
        n: Notification,
        device: Device,
        context,
    ) -> List[str]:
        """
        Send a notification to a device via Expo Push API.
        """
        # Build the Expo push message
        expo_message = {
            "to": device.pushkey,
            "title": n.room_name or "New message",
            "body": n.content.get("body", "You have a new message"),
            "data": {
                "room_id": n.room_id,
                "event_id": n.event_id,
                "sender": n.sender,
                "type": n.type,
            },
            "sound": "default",
            "badge": n.counts.unread if n.counts else None,
        }

        body = json.dumps(expo_message).encode("utf-8")
        
        headers = {
            "Content-Type": ["application/json"],
            "Accept": ["application/json"],
            "Accept-Encoding": ["gzip"],
        }

        logger.info(
            f"Sending notification to {device.pushkey} via Expo Push API"
        )

        try:
            expo_response = await self._perform_http_request(body, headers)
            
            if expo_response.success:
                logger.info(f"Successfully sent notification to {device.pushkey}")
                return []
            else:
                logger.warning(
                    f"Failed to send notification to {device.pushkey}: {expo_response.response_json}"
                )
                return [device.pushkey]
                
        except Exception as e:
            logger.error(f"Error sending notification to {device.pushkey}: {e}")
            return [device.pushkey]

    async def _dispatch_notification(
        self, n: Notification, device: Device, context
    ) -> List[str]:
        """
        Wrapper for dispatch with concurrency limiting.
        """
        return await self._dispatch_notification_unlimited(n, device, context)
