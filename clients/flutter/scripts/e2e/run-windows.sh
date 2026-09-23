#!/usr/bin/env bash
# E2E на Windows-десктопе. Windows-приложение Flutter нельзя собрать с macOS
# (сборка привязана к хосту), поэтому гоним внутри Windows 11 ARM в Parallels:
# macOS — дирижёр, до гостя достаём по SSH (хост win-runner в ~/.ssh/config),
# локальный Synapse пробрасываем тем же приёмом, что на Android — http-порт 8008
# (не воюем с TLS/user-CA). См. tests/e2e.md §2 «Windows-хост» и Очередь 4 (C2).
#
# Предпосылки (разовая ручная настройка, см. README):
#   1. Parallels Win11 ARM поднят, OpenSSH-сервер включён.
#   2. ~/.ssh/config: Host win-runner { HostName <ip>; User <user> }.
#   3. В госте установлен Flutter (windows-desktop) + Visual Studio Build Tools.
#   4. Репозиторий доступен в госте по WIN_REPO (общая папка Parallels или git clone).
set -euo pipefail

SSH_HOST="${LIZA_WIN_SSH:-win-runner}"
WIN_REPO="${LIZA_WIN_REPO:-C:/liza-monorepo}"
HS_PORT="${LIZA_E2E_HS_PORT:-8008}"
TEST="${LIZA_WIN_TEST:-integration_test/liza/receipts_test.dart}"

if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_HOST" "echo ok" >/dev/null 2>&1; then
  cat >&2 <<EOF
✗ Windows-раннер '$SSH_HOST' недоступен по SSH.
  Это ожидаемо, если Parallels Win11 ARM ещё не поднят (см. tests/e2e.md §2, §7:
  C2/C3 — honest-гэп). Шаги поднятия VM и SSH — в clients/flutter/scripts/e2e/README.md.
  На слабой машине Windows-фазу можно вынести в CI (GitHub Actions windows-раннер).
EOF
  exit 2
fi

# Synapse хоста (http) → порт гостя через обратный SSH-туннель: внутри гостя
# http://localhost:$HS_PORT смотрит на macOS-хост. -R прокидывает порт на время сессии.
echo "→ Прогон $TEST на Windows ($SSH_HOST), Synapse через reverse-tunnel :$HS_PORT"
ssh -R "${HS_PORT}:localhost:${HS_PORT}" "$SSH_HOST" \
  "cd $WIN_REPO/clients/flutter && flutter test $TEST -d windows \
     --dart-define=APP_ENV=local \
     --dart-define=E2E_HOMESERVER=http://localhost:${HS_PORT} \
     --timeout 15m"
