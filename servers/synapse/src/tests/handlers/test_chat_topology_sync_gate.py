"""Тесты sync-gate для hidden-комнат (chat topology). См. design doc
docs/superpowers/specs/2026-07-01-chat-topology-stories-sync-gate-design.md."""

from synapse.rest import admin
from synapse.rest.client import login, room, sync

from tests import unittest


class ChatTopologySyncGateTestCase(unittest.HomeserverTestCase):
    servlets = [
        admin.register_servlets,
        login.register_servlets,
        room.register_servlets,
        sync.register_servlets,
    ]

    def default_config(self):
        config = super().default_config()
        config["modules"] = [
            {
                "module": "synapse_modules.chat_topology_sync_gate.ChatTopologySyncGateModule",
                "config": {"enabled": True, "version_gate_base_url": None},
            }
        ]
        return config

    def prepare(self, reactor, clock, hs):
        self.user_id = self.register_user("alice", "pass")
        self.token = self.login("alice", "pass")
        self.hidden_room_id = self.helper.create_room_as(
            self.user_id,
            tok=self.token,
            extra_content={
                "creation_content": {"com.liza.chat.type": "stories"},
                "initial_state": [
                    {
                        "type": "com.liza.chat.topology",
                        "state_key": "",
                        "content": {"hidden": True},
                    }
                ],
            },
        )
        self.normal_room_id = self.helper.create_room_as(self.user_id, tok=self.token)

    def test_device_without_capability_does_not_see_hidden_room(self):
        channel = self.make_request("GET", "/sync", access_token=self.token)
        self.assertEqual(channel.code, 200, channel.result)
        joined = channel.json_body["rooms"]["join"]
        self.assertNotIn(self.hidden_room_id, joined)
        self.assertIn(self.normal_room_id, joined)

    def test_device_gains_full_state_after_passing_gate(self):
        # Первый sync без capability — hidden-комната не видна
        channel = self.make_request("GET", "/sync", access_token=self.token)
        since_token = channel.json_body["next_batch"]

        # Устройство отправляет capability с проходным build
        module = self.hs.liza_chat_topology_sync_gate_module
        device_id = self.login("alice", "pass", device_id="DEVICE_NEW")

        # thresholds=None в этом тесте (version_gate_base_url не задан),
        # поэтому device_passed_gate всегда вернёт False через реальный
        # путь — мокаем именно device_passed_gate, ОДНАКО форс-full-state
        # завязан не на него напрямую, а на факт "маркер выставлен и
        # consume() его нашёл" (см. sync.py: forced_full_state.consume).
        # Реальный REST-эндпоинт (chat_topology.py) выставляет маркер сам
        # ПОСЛЕ upsert_capability, если build_increased И
        # device_passed_gate — здесь имитируем оба шага, которые он бы
        # сделал, а не только upsert.
        self.get_success(
            module.capabilities_store.upsert_capability(
                device_id="DEVICE_NEW",
                user_id=self.user_id,
                platform="android",
                build=999999,
            )
        )

        async def _passed(device_id_arg):
            return device_id_arg == "DEVICE_NEW"

        module.device_passed_gate = _passed
        self.get_success(module.forced_full_state.mark("DEVICE_NEW"))

        channel2 = self.make_request(
            "GET",
            f"/sync?since={since_token}",
            access_token=device_id,
        )
        self.assertEqual(channel2.code, 200, channel2.result)
        joined = channel2.json_body["rooms"]["join"]
        self.assertIn(self.hidden_room_id, joined)
        # full_state ожидание: комната пришла с полным набором state-событий,
        # не пустой дельтой. Synapse кладёт полный набор либо в отдельный
        # блок state, либо (если он умещается в лимит) прямо в timeline —
        # оба варианта корректны, важно что данные реально дошли клиенту.
        room_entry = joined[self.hidden_room_id]
        all_event_types = {ev["type"] for ev in room_entry["state"]["events"]} | {
            ev["type"] for ev in room_entry["timeline"]["events"]
        }
        self.assertIn("m.room.create", all_event_types)
        self.assertIn("m.room.member", all_event_types)

    def test_legacy_stories_room_without_topology_state_defaults_hidden(self):
        legacy_room_id = self.helper.create_room_as(
            self.user_id,
            tok=self.token,
            extra_content={"creation_content": {"com.liza.stories": True}},
        )
        channel = self.make_request("GET", "/sync", access_token=self.token)
        self.assertEqual(channel.code, 200, channel.result)
        joined = channel.json_body["rooms"]["join"]
        self.assertNotIn(legacy_room_id, joined)

    def test_hidden_room_becomes_visible_immediately_after_unhiding(self):
        """Per-user кэш (I2) не должен мешать увидеть свежее значение hidden
        сразу на следующем /sync - инвалидация в _on_new_event обязана
        сработать синхронно с персистом com.liza.chat.topology, без TTL-
        задержки. Это устройство прошло gate заранее (thresholds=None +
        мок device_passed_gate), поэтому единственная переменная в этом
        тесте - hidden, не gate."""
        module = self.hs.liza_chat_topology_sync_gate_module

        async def _always_passed(device_id_arg):
            return True

        module.device_passed_gate = _always_passed

        # Прогреваем кэш: комната ещё hidden=true, но устройство прошло gate,
        # так что она видна (кэш строится и хранит текущее hidden-множество,
        # проверяем что оно там ЕСТЬ до анхайда).
        channel_before = self.make_request("GET", "/sync", access_token=self.token)
        joined_before = channel_before.json_body["rooms"]["join"]
        self.assertIn(self.hidden_room_id, joined_before)

        self.helper.send_state(
            self.hidden_room_id,
            "com.liza.chat.topology",
            {"hidden": False},
            tok=self.token,
            state_key="",
        )

        channel_after = self.make_request("GET", "/sync", access_token=self.token)
        self.assertEqual(channel_after.code, 200, channel_after.result)
        # Комната остаётся видна (устройство прошло gate) - реальная
        # проверка кэша в том, что get_hidden_room_ids_for_user() для этого
        # юзера не вернула бы устаревшее hidden=true и не сломала бы
        # какую-то другую логику, полагающуюся на актуальность множества.
        # Косвенно подтверждаем через второй, ГЕЙТ-НЕ-ПРОШЕДШИЙ токен: если
        # бы кэш был не инвалидирован, следующая проверка тоже считала бы
        # комнату hidden, но теперь hidden=false, так что негейченное
        # устройство ДОЛЖНО увидеть комнату.
        async def _never_passed(device_id_arg):
            return False

        module.device_passed_gate = _never_passed

        ungated_channel = self.make_request("GET", "/sync", access_token=self.token)
        ungated_joined = ungated_channel.json_body["rooms"]["join"]
        self.assertIn(
            self.hidden_room_id,
            ungated_joined,
            "после hidden:false комната обязана быть видна даже 'негейченному' "
            "устройству - если тест провалился, кэш HiddenRoomsLookup вернул "
            "устаревшее значение hidden:true из-за отсутствующей инвалидации",
        )
