#!/usr/bin/env bash
# Страж жизненного цикла тест-эмуляторов (AC-11/12/13 реестра
# tests/registry/RL-prove-ui-device-lifecycle.md). Запуск: make e2e-lifecycle.
#
# Зачем: инцидент 2026-09-04 — run-android.sh поднимал AVD и уходил БЕЗ teardown,
# эмулятор прожил 1д16ч и утащил MacBook 24 ГБ в своп. Ни один существующий страж
# этого не ловил: `run.sh --self-test` грепает ТОЛЬКО собственный исходник и был
# зелёным при живой дыре в соседнем файле. Этот скрипт проверяет ВСЕ лончеры
# сразу — чтобы следующий добавленный лончер без teardown краснел машинно, а не
# обнаруживался через двое суток по окну на экране.
#
# Дешёвый статический анализ: ни одного устройства не поднимает, секунды.
set -uo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 1

ok=1
fail() { echo "  ✗ $1"; ok=0; }
pass() { echo "  ✓ $1"; }

# Отсутствие ТРЕКАЕМОГО лончера — красный, а не «пропуск»: страж, зеленеющий
# оттого что ничего не нашёл, повторяет ровно тот дефект, который мы чиним.
missing_ok() {
  [ -f "$1" ] && return 0
  case "$1" in
    .claude/*) echo "  · $1 — owner-local, в этом чекауте нет: пропуск"; return 1 ;;
    *) fail "$1 — трекаемый лончер отсутствует"; return 1 ;;
  esac
}

# Лончеры, которые ФАКТИЧЕСКИ бутят цель (оркестратор run-all.sh делегирует boot
# им же, поэтому в AC-12 не участвует, но trap обязан иметь и он).
BOOTERS="clients/flutter/scripts/e2e/run-android.sh
clients/flutter/scripts/e2e/run-ios.sh
.claude/tools/prove-ui/run.sh"
ALL="$BOOTERS
clients/flutter/scripts/e2e/run-all.sh"

echo "AC-11 — trap teardown на EXIT INT TERM в каждом лончере:"
for f in $ALL; do
  missing_ok "$f" || continue
  grep -qE 'trap +[A-Za-z_]+ +EXIT INT TERM' "$f" && pass "$f" || fail "$f — нет trap"
done

echo "AC-12 — регистрация поднятого в общий ledger (сирота после SIGKILL):"
for f in $BOOTERS; do
  missing_ok "$f" || continue
  if grep -q 'STATEFILE' "$f" && grep -qE "printf .*\\\\t.*>> *\"?\\\$STATEFILE" "$f"; then
    pass "$f"
  else
    fail "$f — не пишет в ledger: сироту после SIGKILL никто не найдёт"
  fi
done

echo "AC-13 — гашение точечное (никакого площадного shutdown all / pkill qemu):"
for f in $ALL; do
  missing_ok "$f" || continue
  code=$(grep -vE '^[[:space:]]*#' "$f")   # комментарии описывают антипаттерн дословно
  if printf '%s' "$code" | grep -qE 'simctl +shutdown +all'; then
    fail "$f — есть 'simctl shutdown all' (убьёт чужой сим владельца)"
  elif printf '%s' "$code" | grep -qE 'pkill +(-[a-zA-Z]+ +)*-f +["'"'"']?qemu'; then
    fail "$f — есть безфильтровый pkill по qemu (убьёт чужой эмулятор)"
  else
    pass "$f"
  fi
done

echo
[ "$ok" = 1 ] && { echo "✓ Жизненный цикл эмуляторов: AC-11/12/13 зелёные"; exit 0; }
echo "✗ Жизненный цикл эмуляторов: см. отметки выше" >&2
exit 1
