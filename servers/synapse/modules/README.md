# Модули Synapse для Liza

Модули работают внутри процесса Synapse (Module API) и образуют с ним одну
программу, поэтому распространяются на условиях GNU AGPL-3.0, как и сам
Synapse (см. `LICENSE`).

## Установка

Каталог устанавливается как Python-пакет `synapse_modules` рядом с исходниками
Synapse: модули импортируют друг друга как `synapse_modules.<модуль>`.
В нашем развёртывании каталог монтируется в контейнер Synapse по пути
`/editable-src/synapse_modules`. Для своей установки достаточно положить его в
`PYTHONPATH` под этим именем и подключить нужные модули в `homeserver.yaml`:

```yaml
modules:
  - module: synapse_modules.client_guard.ClientGuardModule
    config: {}
```

Точные имена классов и параметры `config` — в `__init__.py` каждого модуля.

## Модули

| Модуль | Назначение |
|---|---|
| `access_admin` | управление доступами: обратимая деактивация/реактивация пользователей |
| `block_guard` | блокировка пользователя на уровне сервера |
| `channel_guard` | каналы: создание и публикация только для ролей admin/moderator |
| `channel_stories` | раздача историй канала по членству |
| `channel_sync` | зеркалирование корневых постов канала в привязанный чат |
| `chat_topology_sync_gate` | capability-эндпоинт и учёт возможностей устройств |
| `client_guard` | вход только с клиентов Liza |
| `knock_notify` | пуш админам и модераторам о заявке на вступление |
| `media_lifecycle` | карантин медиа в media-repo при удалении сообщения |
| `media_variants` | постановка видео в очередь транскодинга |
| `miniapp` | платформа мини-приложений |
| `single_space_guard` | ровно одно главное пространство на инстанс |
| `stories_membership` | автоприглашение в сторис и очистка истёкших |
| `user_roles` | роли пользователей (user/ai/developer/moderator/manager/admin) |
| `user_search_guard` | федеративный поиск пользователей между инстансами |
