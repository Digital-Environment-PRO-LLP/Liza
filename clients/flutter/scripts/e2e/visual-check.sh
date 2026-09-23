#!/usr/bin/env bash
# Реконсиляция ВИЗУАЛЬНЫХ baseline (Ярус B) с реестром регрессии и файлами.
# Дополняет ledger-check.sh (тот сверяет страж-теги): здесь — что у заявленных
# reference-скриншотов есть файлы, что они привязаны к существующей RL-записи, и
# печатает чек-лист «сравни текущий UI с этим эталоном глазами» для /e2e-full.
#
# Ярус A (golden, авто-pixel-diff) проверяется отдельно — make e2e-golden.
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
cd "$REPO_ROOT"

REG_DIR="tests/registry"
SHOT_DIR="tests/screenshots"

echo "════════ Сверка визуальных baseline (Ярус B) ════════"

ok=0; pending=0; missing=0; orphan=0
review_lines=""

# 1) Записи реестра, помеченные visual: required — должны иметь baseline-дир.
for rl in "$REG_DIR"/RL-*.md; do
  [ -e "$rl" ] || continue
  slug=$(awk -F': *' '/^id:[[:space:]]/{print $2;exit}' "$rl" | tr -d ' \r"'\''')
  slug="${slug#RL-}"
  vis=$(awk -F': *' '/^visual:[[:space:]]/{print $2;exit}' "$rl" | tr -d ' \r"'\''')
  if [ "$vis" = "required" ]; then
    if [ ! -f "$SHOT_DIR/$slug/baselines.md" ]; then
      echo "⚠ UI-РЕЕСТР без baseline: RL-$slug (visual: required), нет $SHOT_DIR/$slug/baselines.md"
      echo "    → сними эталон при следующей проверке UI: snap-feature.sh $slug <name> <png> \"<desc>\""
      missing=$((missing+1))
    fi
  elif [ "$vis" = "recommended" ]; then
    # НЕ молчим про recommended без baseline: иначе UI-фича живёт с visual:
    # recommended и НИКОГДА не получает reference-эталон, а /e2e-full не даёт ни
    # строчки сигнала (выстрадано 2026-07-28 — правки рендера времени уехали без
    # baseline, регресс не фиксировался). Сигнал НЕ блокирующий (recommended ≠
    # required), но видимый — чтобы поднять до required и снять эталон.
    if [ ! -f "$SHOT_DIR/$slug/baselines.md" ]; then
      echo "○ RECOMMENDED без baseline: RL-$slug (visual: recommended) — эталон не снят"
      echo "    → сними при следующей проверке UI (или подними до visual: required): snap-feature.sh $slug <name> <png> \"<desc>\""
      pending=$((pending+1))
    fi
  fi
done

# 2) Каждый манифест baseline — проверить файлы и привязку к RL.
if [ -d "$SHOT_DIR" ]; then
  for manifest in "$SHOT_DIR"/*/baselines.md; do
    [ -e "$manifest" ] || continue
    slug=$(basename "$(dirname "$manifest")")
    # есть ли запись реестра?
    if ! ls "$REG_DIR"/RL-*.md >/dev/null 2>&1 || \
       ! grep -qiE "^id:[[:space:]]*\"?RL-${slug}\"?" "$REG_DIR"/RL-*.md 2>/dev/null; then
      echo "⚠ ОСИРОТЕВШИЙ baseline-каталог: $SHOT_DIR/$slug (нет RL-$slug в реестре)"
      orphan=$((orphan+1))
    fi
    # строки таблицы: | file | platform | build | captured | desc |
    while IFS='|' read -r _ file platform build captured desc _; do
      file=$(echo "$file" | xargs 2>/dev/null)
      [ -z "$file" ] && continue
      case "$file" in file|----*|"") continue;; esac
      [ "${file##*.}" = "png" ] || continue
      captured=$(echo "$captured" | xargs 2>/dev/null)
      desc=$(echo "$desc" | xargs 2>/dev/null)
      if [ "$captured" = "pending" ]; then
        echo "○ PENDING: RL-$slug / $file — эталон ещё не снят ($desc)"
        pending=$((pending+1))
        continue
      fi
      if [ -f "$SHOT_DIR/$slug/$file" ]; then
        ok=$((ok+1))
        review_lines="${review_lines}\n  [ ] RL-$slug — $SHOT_DIR/$slug/$file — $desc"
      else
        echo "✗ ОТСУТСТВУЕТ ФАЙЛ: $SHOT_DIR/$slug/$file (заявлен в манифесте, captured=$captured)"
        missing=$((missing+1))
      fi
    done < "$manifest"
  done
fi

echo
echo "──────── Чек-лист визуальной сверки (сравни ГЛАЗАМИ текущий UI с эталоном) ────────"
if [ -n "$review_lines" ]; then
  printf '%b\n' "$review_lines"
else
  echo "  (нет готовых reference-эталонов)"
fi

echo
echo "Итог: OK=$ok  PENDING=$pending  MISSING=$missing  ORPHAN=$orphan"
echo "Ярус A (golden, авто-pixel-diff): make e2e-golden."
# Разводим два исхода (внедрено после 3704, где visual:required без baseline лишь
# ПРЕДУПРЕЖДАЛ, а маркер всё равно писался → баг рендера уехал):
#   MISSING (visual:required без снятого baseline) → exit 2 → run-all.sh кладёт в
#     FAIL[] → маркер НЕ пишется → push в main заблокирован. Это БЛОКИРУЮЩИЙ долг
#     приёмки: единственная проверка реального рендера глазами не выполнена.
#   ORPHAN/пропавший файл (без missing) → exit 1 → предупреждение (реестр отстал).
if [ "$missing" -gt 0 ]; then
  echo "БЛОКИРУЮЩИЙ ДОЛГ: visual: required без снятого baseline ($missing). Перед MR:"
  echo "  1. Прогони фичу на нативной сборке (iOS/Android/macOS) и проверь ГЛАЗАМИ."
  echo "  2. Сними эталон: clients/flutter/scripts/e2e/snap-feature.sh <slug> <name> <png> \"<desc>\" <platform> <build>"
  exit 2
fi
if [ "$orphan" -gt 0 ]; then
  echo "⚠ Осиротевшие baseline-каталоги без RL-записи — почини перед MR."
  exit 1
fi
exit 0
