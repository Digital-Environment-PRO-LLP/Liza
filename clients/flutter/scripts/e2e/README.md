# E2E-скрипты Liza

Агентное e2e-тестирование, полный разбор — `tests/e2e.md`. Здесь — операционная
шпаргалка по скриптам и разовой настройке Windows-контура.

## Make-цели (из корня репо)

| Цель | Что делает |
|---|---|
| `make e2e-golden` | Ярус 0: golden-тесты Alchemist (`flutter test --tags golden`) |
| `make e2e-golden-update` | Перегенерировать эталоны после намеренной правки UI |
| `make e2e-local` | macOS desktop: доставка + прочтение |
| `make e2e-local-bugs` | macOS: кейсы «багов пятницы» |
| `make e2e-ios` | iOS-симулятор (нужен установленный iOS-runtime) |
| `make e2e-android` | Android-эмулятор (создаёт AVD, adb reverse) |
| `make e2e-windows` | Windows через `ssh win-runner` (см. ниже) |
| `make e2e-all` | Полная матрица **фазами** под бюджет RAM |
| `make e2e-push-android` / `make e2e-push-ios` | Нативные пуш-сценарии (Ярус C) |

`make e2e-all` пропускает недоступные таргеты (нет iOS-runtime, нет SDK,
`win-runner` недоступен) с пометкой `skip`, не валя весь прогон. Выключатели
фаз: `E2E_SKIP_IOS=1`, `E2E_SKIP_ANDROID=1`, `E2E_WITH_WINDOWS=1`.

## Windows-контур (разовая настройка)

Flutter-приложение под Windows нельзя собрать с macOS → гоним в Windows 11 ARM
в Parallels. macOS — дирижёр, до гостя по SSH. Подробности — `tests/e2e.md` §2.

1. **Parallels + Windows 11 ARM.** Поставить Parallels Desktop, установить
   Win11 ARM (Parallels качает образ сам). Настройки VM: ~8 ГБ RAM, 4 vCPU,
   авто-suspend при простое (Configure → Optimization).
2. **В госте — Flutter + сборочный тулчейн:** Visual Studio Build Tools
   (workload «Desktop development with C++»), Flutter SDK, `flutter config
   --enable-windows-desktop`, `flutter doctor` зелёный по Windows.
3. **OpenSSH-сервер в Windows:** Settings → Apps → Optional Features → OpenSSH
   Server → Start (и Automatic). Проверить порт 22 из macOS.
4. **`~/.ssh/config` на macOS:**
   ```
   Host win-runner
       HostName <IP-гостя из Parallels>
       User <ваш-windows-user>
   ```
   Ключ — `ssh-copy-id` или вручную в `C:\Users\<user>\.ssh\authorized_keys`.
5. **Репозиторий в госте:** общая папка Parallels (Shared Folders) или
   `git clone`; путь задаётся `LIZA_WIN_REPO` (по умолчанию `C:/liza-monorepo`).
6. **Прогон:** `make e2e-windows`. Локальный Synapse пробрасывается обратным
   SSH-туннелем (`ssh -R 8008:localhost:8008`), клиент ходит на
   `http://localhost:8008` (как Android — http, без TLS/user-CA).

Переменные: `LIZA_WIN_SSH` (хост, деф. `win-runner`), `LIZA_WIN_REPO`,
`LIZA_WIN_TEST`, `LIZA_E2E_HS_PORT`.

**Альтернатива VM:** на слабой машине Windows-фазу дешевле держать в CI
(GitHub Actions windows-раннер), а не в локальной Parallels — см. `tests/e2e.md` §4б.

## Нативный Windows-слой (Ярус B/C)

- **FlaUI** (.NET) — клики по системным окнам через UIA `AutomationId`
  (берётся из `Semantics(identifier:)` Flutter); живее заброшенного WinAppDriver.
- **Windows-MCP** (CursorTouch) — ставится **внутри гостя**, агентный «глаз»
  под Windows. На macOS не ставится.
