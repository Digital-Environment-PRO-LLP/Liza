# media_lifecycle — Synapse-модуль quarantine медиа при redaction

При `m.room.redaction` оригинального медиа-события (non-E2EE) вызывает
MMR Admin API для quarantine соответствующего blob'а. Quarantine — мягкое
удаление: блокирует отдачу через MMR, но blob остаётся в S3 до storage
cleanup MMR. Это **не уничтожение данных**; для hard-delete нужна
отдельная итерация со сменой endpoint.

## Где работает

ТОЛЬКО на `dev.liza.laba.prodamus.tech`. В `__init__` есть жёсткий fail-fast
по `server_name` — на любом другом инстансе Synapse упадёт на старте с
`ConfigError`. Это намеренно: папка `servers/synapse/modules/` маунтится
во все инстансы, и регистрация модуля в prod homeserver.yaml не должна
приводить к молчаливому подключению.

## Что обрабатывает

- `m.room.message` с `msgtype` ∈ `{m.image, m.video, m.audio, m.file}`
- `event.content.url` начинается с `mxc://`
- НЕ обрабатывает `m.room.encrypted` (E2EE attachments — `mxc` не виден
  серверу внутри ciphertext; нужен hint от клиента в redaction event,
  отдельная задача)

## Idempotency

Таблица `media_lifecycle_processed` (создаётся на старте модуля):

| Колонка | Тип |
|---|---|
| `redacted_event_id` | TEXT PRIMARY KEY |
| `mxc_uri` | TEXT |
| `room_id` | TEXT |
| `processed_at` | BIGINT (ms timestamp) |
| `delete_status` | TEXT (`quarantined` / `already_absent` / `dry_run` / `error_*`) |

Повторный redaction того же события — no-op. Полезно при replay
federation-событий и при перезапуске Synapse.

## MMR Admin API

Используется **`POST /_matrix/media/unstable/admin/quarantine/{server}/{id}`**
(мягкое удаление — блокирует отдачу, blob остаётся в S3 до storage
cleanup MMR). Для hard-delete нужна замена на `DELETE` endpoint, но
для первой итерации quarantine безопаснее.

Аутентификация: `Authorization: Bearer <token>`, где `<token>` — admin
access_token Matrix-пользователя на dev-Synapse (MMR проверяет admin
через `/whoami` к Synapse).

## Включение

1. На сервере положить admin-token в файл каталога секретов инстанса
   (`secrets/synapse/<инстанс>/`, монтируется в контейнер как `/data/secrets/`):
   ```bash
   cat > secrets/synapse/dev-liza-laba/mmr_admin.token <<EOF
   <access_token админ-юзера dev-Synapse>
   EOF
   chmod 600 secrets/synapse/dev-liza-laba/mmr_admin.token
   ```

2. Добавить в `servers/synapse/instances/dev-liza-laba/config/homeserver.yaml`:
   ```yaml
   modules:
     - module: synapse_modules.media_lifecycle.MediaLifecycleModule
       config:
         mmr_admin_url: http://mmr:8000
         mmr_admin_token_path: /data/secrets/mmr_admin.token
         dry_run: true   # на первые 3-7 дней
   ```
   (Монт `secrets/synapse/dev-liza-laba/` в контейнер должен покрыть путь
   `/data/secrets/mmr_admin.token` — если нет, добавить в compose volumes.)

3. `docker compose restart synapse-dev-liza-laba`. В логах должна появиться:
   `MediaLifecycleModule loaded (server=dev.liza.laba.prodamus.tech, dry_run=True, mmr=http://mmr:8000)`

4. В обычной (non-E2EE) комнате отправить картинку, заредактить её
   (`redact event`). В логах Synapse:
   `media_lifecycle [DRY-RUN]: would quarantine mxc://... ...`

5. Через 3-7 дней DRY-RUN, если всё ок — переключить `dry_run: false`
   и снова рестартануть Synapse.

## Откат

- Удалить блок `modules:` из dev-homeserver.yaml.
- `docker compose restart synapse-dev-liza-laba`.
- Таблица `media_lifecycle_processed` остаётся, но не используется.
- Уже карантинные blob'ы можно восстановить через
  `POST /_matrix/media/unstable/admin/unquarantine/{server}/{id}`.
