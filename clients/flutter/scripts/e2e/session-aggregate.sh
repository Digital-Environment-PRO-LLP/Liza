#!/usr/bin/env bash
# Кросс-сессионная агрегация требований/критериев приёмки перед e2e-full.
#
# ПОЧЕМУ (инцидент 3704): фичу футера времени делала ПАРАЛЛЕЛЬНАЯ сессия
# (коммиты ccd53e50 + debug 4904e4dd на общей ветке fixes-29) с точным
# требованием пользователя В ЕЁ диалоге. E2e гнали в ДРУГОЙ сессии, где этого
# требования в контексте не было; зелёные golden/widget тестировали РЕПЛИКУ, а не
# реальный рендер → баг уехал в сборку. Источник правды кросс-сессий = ЗАКОММИЧЕННЫЕ
# в ветку RL-записи + их критерии приёмки, а НЕ диалог конкретной сессии.
#
# Что делает (read-only, ничего не чинит):
#   1. По diff ветки (origin/main...HEAD) собирает СПИСОК ЗАТРОНУТЫХ RL-записей —
#      и напрямую изменённых tests/registry/RL-*.md, и косвенно затронутых (RL,
#      чей guard-тест/исходная область попали в diff). Это фичи ЛЮБОЙ сессии на
#      ветке, не только текущей.
#   2. Для каждой печатает БЛОК «Критерий приёмки» (Инвариант + шаги manual-стража)
#      как ОБЯЗАТЕЛЬНЫЙ ручной чек-лист прогона.
#   3. Сканирует ДРУГИЕ worktree (git worktree list) на незакоммиченные RL/критерии
#      и на debug-/отключённые правки — ПРЕДУПРЕЖДАЕТ (их нет в ветке = не источник
#      правды, но потерять/протащить сырыми нельзя).
#   4. Ловит debug()-коммиты и закомментированную работу в diff ветки — ПРЕДУПРЕЖДАЕТ.
#
# Блокирует (exit≠0) ТОЛЬКО при незакоммиченных RL в ДРУГОМ worktree на общей ветке
# (реальная потеря источника правды). Всё остальное — advisory (печать в чек-лист).
# Флаг E2E_AGG_STRICT=1 повышает debug-коммит/чужой-незакоммит до блока.
set -uo pipefail
cd "$(dirname "$0")/../../../.."   # корень репо

BASE="${E2E_AGG_BASE:-origin/main}"
LEDGER_DIR="tests/registry"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)
STRICT="${E2E_AGG_STRICT:-0}"
FAIL=0

git fetch origin main -q 2>/dev/null || true
if ! git rev-parse "$BASE" >/dev/null 2>&1; then
  echo "⚠ Нет базы $BASE — агрегация по ветке невозможна (offline?). Пропускаю кросс-diff, worktree-скан выполню."
  BASE=""
fi

echo "════════ Кросс-сессионная агрегация (ветка $BRANCH ← $BASE) ════════"

# ── 1. Затронутые файлы ветки ──
changed=""
[ -n "$BASE" ] && changed=$(git diff "$BASE"...HEAD --name-only 2>/dev/null)

# Прямо изменённые RL-записи (ЧУЖАЯ сессия могла завести/поправить RL на этой ветке).
direct_rl=$(printf '%s\n' "$changed" | grep -E "^$LEDGER_DIR/RL-.*\.md$" || true)

# Косвенно затронутые RL: у записи есть guard-тест, и его файл (или страж-тег) —
# в diff. Сопоставляем по grep guard-тега в изменённых тестовых файлах.
changed_tests=$(printf '%s\n' "$changed" | grep -E '(_test\.dart|/tests/.*\.py)$' || true)
indirect_slugs=""
if [ -n "$changed_tests" ]; then
  indirect_slugs=$(printf '%s\n' "$changed_tests" | while read -r t; do
    [ -f "$t" ] && grep -hoE 'ledger:RL-[a-z0-9-]+' "$t" 2>/dev/null
  done | sed 's/^ledger://' | sort -u)
fi

# Полный набор slug'ов затронутых RL (объединение прямых + косвенных).
# bash 3.2 (macOS) без ассоциативных массивов — копим в переменную, дедуп через sort -u.
touched=""
for f in $direct_rl; do
  [ -f "$f" ] || continue
  id=$(awk -F': *' '/^id:[[:space:]]/{print $2; exit}' "$f" | tr -d ' \r"'\''')
  [ -n "$id" ] && touched="$touched
$id"
done
for s in $indirect_slugs; do touched="$touched
$s"; done
touched=$(printf '%s\n' "$touched" | grep -E '^RL-' | sort -u)

# ── 2. Чек-лист критериев приёмки затронутых RL (ОБЯЗАТЕЛЬНЫЙ) ──
extract_ac() {  # печатает Инвариант + manual-шаги записи RL по slug
  local slug="$1" f="$LEDGER_DIR/$slug.md"
  [ -f "$f" ] || { echo "  ⚠ $slug — файл записи не найден ($f)"; return; }
  local title status gtype
  title=$(awk '/^# /{sub(/^# /,"");print;exit}' "$f")
  status=$(awk -F': *' '/^status:[[:space:]]/{print $2;exit}' "$f" | tr -d ' \r"'\''')
  gtype=$(awk '/^guard:/{g=1} g&&/^[[:space:]]+type:[[:space:]]/{sub(/.*type:[[:space:]]*/,"");print;exit}' "$f" | tr -d ' \r"'\''')
  echo "── [$slug] ${title:-—}  (guard:${gtype:-?} status:${status:-?})"
  # «Инвариант (что нельзя сломать …)» — абзац после маркера до пустой строки.
  awk '/\*\*Инвариант/{p=1} p{print "   "$0} p&&/^\s*$/{exit}' "$f" | sed 's/\*\*//g'
  # Шаги manual-стража, если есть (строки под "manual" в разделе Стражи / тела).
  awk '/manual/{m=1} m{print "   • "$0}' "$f" | grep -iE 'проверк|нативн|устройств|глаз|вручную|manual' | head -6
}

if [ -z "$touched" ]; then
  echo "→ Ветка не затрагивает ни одной RL-записи (прямо или через страж-тест)."
  echo "  Если правка меняет user-visible поведение, но RL нет — ЗАВЕДИ запись перед MR."
else
  echo
  echo "▓▓ КРИТЕРИИ ПРИЁМКИ ЗАТРОНУТЫХ ФИЧ (все сессии ветки — свери КАЖДЫЙ ЖИВЬЁМ) ▓▓"
  echo "   Зелёный автотест ≠ выполнен критерий: golden/widget часто тестируют РЕПЛИКУ."
  echo "   Сверяй реальный рендер/поведение с текстом ниже, а не только цвет теста."
  echo
  for slug in $touched; do
    extract_ac "$slug"
    echo
  done
fi

# ── 3. debug()-коммиты и закомментированная/отключённая работа в diff ветки ──
if [ -n "$BASE" ]; then
  dbg=$(git log "$BASE"..HEAD --oneline 2>/dev/null | grep -iE '^\w+ (debug|wip|tmp|temp|fixup)[:(]' || true)
  if [ -n "$dbg" ]; then
    echo "⚠ DEBUG/WIP-коммиты на ветке (поэтапная работа чужой сессии — не тащить сырьём в релиз):"
    printf '%s\n' "$dbg" | sed 's/^/   /'
    echo "   → Реши по КАЖДОМУ: свернуть диагностику до MR или задокументировать почему остаётся."
    [ "$STRICT" = 1 ] && FAIL=1
    echo
  fi
fi

# ── 4. Скан ДРУГИХ worktree на незакоммиченное (RL/критерии/фичи) ──
# Параллельная сессия могла оставить в своём worktree незакоммиченную RL-запись
# или отключённую фичу — их НЕТ в ветке, значит НЕТ в источнике правды. Предупреждаем;
# незакоммиченный RL на ОБЩЕЙ с нами ветке — блок (реальная потеря критерия).
self_wt=$(git rev-parse --show-toplevel 2>/dev/null)
git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}' | while read -r wt; do
  [ "$wt" = "$self_wt" ] && continue
  [ -d "$wt" ] || continue
  wt_branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  dirty=$(git -C "$wt" status --porcelain 2>/dev/null)
  [ -z "$dirty" ] && continue
  # Незакоммиченные RL-записи?
  rl_dirty=$(printf '%s\n' "$dirty" | grep -E ' tests/registry/RL-.*\.md$' || true)
  # Незакоммиченные тесты со страж-тегом / lib-правки?
  code_dirty=$(printf '%s\n' "$dirty" | grep -E ' (clients/flutter/lib/|clients/flutter/test/|servers/liza-bot-api/)' || true)
  if [ -n "$rl_dirty" ] || [ -n "$code_dirty" ]; then
    echo "⚠ WORKTREE $wt [$wt_branch] — незакоммиченная работа (нет в источнике правды ветки):"
    [ -n "$rl_dirty" ]  && { echo "   НЕЗАКОММИЧЕННЫЕ RL-записи (критерии приёмки будут ПОТЕРЯНЫ для прогона):"; printf '%s\n' "$rl_dirty" | sed 's/^/     /'; }
    [ -n "$code_dirty" ] && { echo "   Незакоммиченный код/тесты:"; printf '%s\n' "$code_dirty" | head -8 | sed 's/^/     /'; }
    echo "   → Попроси ту сессию закоммитить RL+тест в ветку ДО e2e-full, иначе критерий не учтён."
  fi
done

# Отдельный проход (не в subshell) — чтобы поднять FAIL при незакоммиченном RL на
# ТОЙ ЖЕ ветке, что и мы (общий HEAD источника правды реально дырявый).
while read -r wt; do
  [ "$wt" = "$self_wt" ] && continue
  [ -d "$wt" ] || continue
  wt_branch=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  [ "$wt_branch" = "$BRANCH" ] || continue
  git -C "$wt" status --porcelain 2>/dev/null | grep -qE ' tests/registry/RL-.*\.md$' && {
    echo "✗ БЛОК: worktree $wt на НАШЕЙ ветке $BRANCH имеет незакоммиченный RL — критерий приёмки вне прогона."
    FAIL=1; }
done < <(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')

echo "════════ конец агрегации ════════"
if [ "$FAIL" -ne 0 ]; then
  echo "→ БЛОК агрегации: незакоммиченный источник правды (RL) на общей ветке / STRICT. Закоммить и повтори."
  exit 1
fi
exit 0
