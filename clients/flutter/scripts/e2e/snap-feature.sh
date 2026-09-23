#!/usr/bin/env bash
# Регистрирует reference-скриншот реального UI (Ярус B визуальных baseline) к
# записи реестра регрессии. Вызывается на этапе MR, когда UI-фича успешно
# проверена в интерфейсе: «успех виден глазами → фиксируем эталон».
#
# Скриншот кладётся в tests/screenshots/<RL-slug>/<name>.png и записывается в
# манифест tests/screenshots/<RL-slug>/baselines.md, чтобы make e2e-visual мог
# сопоставить заявленный baseline с файлом и с записью реестра.
#
# Usage:
#   snap-feature.sh <RL-slug> <name> <source.png> "<описание>" [platform] [build]
# Пример:
#   snap-feature.sh receipts-indicators seen-by-avatars-group /tmp/shot.png \
#     "аватарки прочтения в группе (до 10 + +N)" macos 3663
#
# Ярус A (детерминированный pixel-diff) — это golden-тесты Alchemist
# (make e2e-golden), они НЕ через этот скрипт. Здесь только Ярус B —
# недетерминированный реальный UI, сверяется глазами по манифесту.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
cd "$REPO_ROOT"

slug="${1:-}"; name="${2:-}"; src="${3:-}"; desc="${4:-}"
platform="${5:-unknown}"; build="${6:-}"

if [ -z "$slug" ] || [ -z "$name" ] || [ -z "$src" ] || [ -z "$desc" ]; then
  echo "Usage: snap-feature.sh <RL-slug> <name> <source.png> \"<описание>\" [platform] [build]" >&2
  exit 2
fi

rl="tests/registry/RL-${slug}.md"
if [ ! -f "$rl" ]; then
  echo "✗ Нет записи реестра $rl — сначала заведи RL-запись (/pin-feature)." >&2
  exit 1
fi
if [ ! -f "$src" ]; then
  echo "✗ Исходный скриншот не найден: $src" >&2
  exit 1
fi

# имя без .png + защита от мусорных символов
name="${name%.png}"
case "$name" in *[!a-zA-Z0-9_-]*) echo "✗ name только [a-zA-Z0-9_-]" >&2; exit 2;; esac

dir="tests/screenshots/${slug}"
mkdir -p "$dir"
dest="${dir}/${name}.png"
cp "$src" "$dest"

manifest="${dir}/baselines.md"
if [ ! -f "$manifest" ]; then
  {
    echo "# Визуальные baseline (Ярус B, реальный UI) — RL-${slug}"
    echo
    echo "Reference-скриншоты успешно реализованного UI. Сверяются ГЛАЗАМИ на"
    echo "\`make e2e-visual\` / \`/e2e-full\` (реальный UI недетерминирован —"
    echo "авто-pixel-diff даёт golden, см. \`tests/registry/RL-${slug}.md\`)."
    echo "Машиночитаемая таблица ниже — НЕ редактировать вручную, пиши через"
    echo "\`snap-feature.sh\`."
    echo
    echo "| file | platform | build | captured | desc |"
    echo "|------|----------|-------|----------|------|"
  } > "$manifest"
fi

# дата без Date.now() недоступна в shell? нет — это bash, date есть
captured=$(date +%Y-%m-%d)

# если строка с этим file уже есть — заменяем, иначе добавляем
row="| ${name}.png | ${platform} | ${build:-—} | ${captured} | ${desc} |"
if grep -qE "^\| ${name}\.png \|" "$manifest"; then
  tmp=$(mktemp)
  sed "s#^| ${name}\.png |.*#${row}#" "$manifest" > "$tmp" && mv "$tmp" "$manifest"
  echo "↻ Обновлён baseline: $dest"
else
  printf '%s\n' "$row" >> "$manifest"
  echo "✓ Добавлен baseline: $dest"
fi

echo "  манифест: $manifest"
echo "  запись реестра: $rl"
echo "  → закоммить tests/screenshots/${slug}/ вместе с фиксом (это эталон, не /tmp-артефакт)."
