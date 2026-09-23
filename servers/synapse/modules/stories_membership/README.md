# stories_membership

Synapse-модуль сторисов Liza. Три задачи:

1. **Автоинвайт по DM-графу.** При join в личный чат взаимно инвайтит
   участников в сторис-комнаты друг друга (хук `on_new_event`). Сторисы
   доставляются родным механизмом Matrix, включая федерацию (удалённый
   контакт инвайтится с `remote_room_hosts`, авто-джойн делает его клиент).
2. **Backfill существующих DM.** При старте модуля разово подписывает все
   существующие DM-пары (созданные до деплоя модуля, на которые хук не
   сработал). Реализован через `run_db_interaction` (читает `account_data`
   с типом `m.direct`, проверяет локальность комнаты и 2 join-участника через
   `current_state_events`). Если упрётся в ошибку БД - деградирует до no-op,
   новые DM продолжают обрабатываться хуком.
3. **Чистка протухших.** Периодически (`reactor.callLater`) redact-ит
   события с истёкшим `com.liza.story.expires_ts`.

## Конфиг (homeserver.yaml)

```yaml
modules:
  - module: synapse_modules.stories_membership.StoriesMembershipModule
    config:
      cleanup_interval_minutes: 30
      story_ttl_hours: 24
```

## Известные ограничения прототипа

- Реестр сторис-комнат и выборка событий для redaction зависят от store API
  Synapse 1.151; если интеграция упрётся - чистка на сервере деградирует до
  no-op, клиентский фильтр по `expires_ts` продолжает скрывать протухшее.
- `_service_sender` (от кого шлётся redaction) уточняется под реальный
  сервисный аккаунт инстанса.
- Backfill зависит от `run_db_interaction` Synapse 1.151 (публичный API,
  используется также в `single_space_guard` и `media_lifecycle`). Если API
  изменится - backfill деградирует до no-op, новые DM через хук не затронуты.
