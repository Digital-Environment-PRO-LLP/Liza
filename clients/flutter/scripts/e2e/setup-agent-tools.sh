#!/usr/bin/env bash
# Разовая установка инструментов агентного e2e (ярус B из tests/e2e.md):
#  - AXe      — клики/ввод/describe-ui на iOS-симуляторе
#  - Peekaboo — скриншот+AX-дерево+клики на macOS desktop
#  - cliclick — координатный fallback на macOS
#  - MCP: официальный dart mcp-server, mobile-mcp, peekaboo
set -uo pipefail

echo "── brew-инструменты ──"
brew list axe >/dev/null 2>&1 || brew install cameroncooke/axe/axe
brew list peekaboo >/dev/null 2>&1 || brew install steipete/tap/peekaboo
brew list cliclick >/dev/null 2>&1 || brew install cliclick
brew list watchexec >/dev/null 2>&1 || brew install watchexec   # fast-suite watch (Очередь 4 C5)

echo "── MCP для Claude Code ──"
claude mcp add --transport stdio dart -- dart mcp-server || true
claude mcp add mobile-mcp -- npx -y @mobilenext/mobile-mcp@latest || true
# peekaboo v3 несёт встроенный MCP-режим — поднимаем через brew-бинарь.
# НЕ через npx @steipete/peekaboo (тот не коннектится).
claude mcp add peekaboo -- peekaboo mcp serve || true

cat <<'EOF'

✓ Установлено. Осталось руками (из CLI не автоматизируется):
  System Settings → Privacy & Security →
    - Accessibility: добавить терминал (iTerm/Terminal/IDE), peekaboo
    - Screen Recording: то же
  Без этих прав Peekaboo/cliclick не смогут видеть экран и кликать.

Проверка: claude mcp list; axe --help; peekaboo see --app Liza
EOF
