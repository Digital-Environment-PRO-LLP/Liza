#!/usr/bin/env bash
# Полная матрица e2e ФАЗАМИ под бюджет RAM (см. tests/e2e.md §4б, §6, Очередь 4 C5).
# Никогда не держим iOS-сим и Android-эмулятор в памяти одновременно: каждая фаза
# по очереди, между фазами — teardown (освобождение RAM). Недоступные таргеты
# честно пропускаются (SKIP с кодом причины), не валят прогон. В конце — сводка
# PASS/FAIL/SKIP; exit≠0 только если что-то РЕАЛЬНО упало (не из-за ресурсов).
#
# Калибровка под фактическую доступную RAM в рантайме (машина бывает 18 ГБ, не
# целевые 48). macOS не имеет GNU `timeout` → свой perl-watchdog. Прерывание на
# середине → trap прибирает симулятор/эмулятор, иначе следующий прогон уйдёт в OOM.
#
# Выключатели: E2E_SKIP_IOS=1, E2E_SKIP_ANDROID=1, E2E_WITH_WINDOWS=1,
#              E2E_FORCE=1 (гнать мобильные даже при красном golden/macOS).
set -uo pipefail
cd "$(dirname "$0")/../../../.."   # корень репо
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"

PASS=(); FAIL=(); SKIP=(); VISUAL_WARN=0
phase() { echo; echo "════════ ФАЗА: $1 ════════"; }
ok()    { PASS+=("$1"); echo "✓ $1"; }
bad()   { FAIL+=("$1: $2"); echo "✗ $1 ($2)"; }
skip()  { SKIP+=("$1: $2"); echo "– skip $1 ($2)"; }

# ── perl-watchdog вместо отсутствующего на macOS `timeout` ──
run_to() { # run_to <секунды> <команда...>
  local t="$1"; shift
  perl -e 'my $t=shift; my $pid=fork; if($pid==0){exec @ARGV or exit 127}
           local $SIG{ALRM}=sub{kill "TERM",$pid; sleep 3; kill "KILL",$pid; exit 124};
           alarm $t; waitpid($pid,0); exit($?>>8)' "$t" "$@"
}

# ── доступная RAM в МБ (free+inactive+speculative страницы) ──
avail_mb() {
  local ps free inact spec
  ps=$(vm_stat 2>/dev/null | awk '/page size of/{print $8}'); ps=${ps:-16384}
  free=$(vm_stat 2>/dev/null | awk '/Pages free/{gsub("\\.","",$3);print $3}')
  inact=$(vm_stat 2>/dev/null | awk '/Pages inactive/{gsub("\\.","",$3);print $3}')
  spec=$(vm_stat 2>/dev/null | awk '/speculative/{gsub("\\.","",$3);print $3}')
  echo $(( ( ${free:-0} + ${inact:-0} + ${spec:-0} ) * ps / 1048576 ))
}

# Уже загруженный Android-эмулятор ЗАПОМИНАЕМ ДО первого teardown — чтобы его
# переиспользовать (run-android.sh), а не убить и на sub-4GB-машине уйти в
# SKIP_NO_RAM. Без этого захвата вся BOOTED_EMU-логика ниже — мёртвый код:
# defensive-teardown на старте гасил бы эмулятор раньше проверки (BLOCKER-1,
# трибунал 2026-07-28). teardown_mobile ниже щадит именно этот серийник.
REUSE_ANDROID=""
[ -x "$ADB" ] && REUSE_ANDROID=$("$ADB" devices 2>/dev/null | awk '/^emulator-/{print $1; exit}')
[ -n "$REUSE_ANDROID" ] && echo "Загружен Android-эмулятор $REUSE_ANDROID — сохраняю для переиспользования"

# Симы, открытые владельцем ДО старта, тоже щадим (не `shutdown all` — он убил бы
# чужой сим параллельной работы). Захват ДО первого teardown (по аналогии с
# REUSE_ANDROID); гасим лишь то, что забутила эта фаза.
REUSE_IOS="$(xcrun simctl list devices booted 2>/dev/null \
  | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | sort -u || true)"
[ -n "$REUSE_IOS" ] && echo "Загружены iOS-симы (щажу): $(echo "$REUSE_IOS" | tr '\n' ' ')"

# ── teardown: прибрать мобильные цели, освободить RAM (идемпотентно, data-safe) ──
# Щадит $REUSE_ANDROID (уже загруженный до старта эмулятор) — его переиспользует
# Android-фаза, и $REUSE_IOS (симы владельца до старта). iOS-сим на sub-4GB всё
# равно скипнется по RAM, двойного mobile нет.
teardown_mobile() {
  # Точечно: гасим лишь booted-симы, которых НЕ было до старта (не `shutdown all` —
  # он прибил бы чужой сим параллельной работы владельца).
  for u in $(xcrun simctl list devices booted 2>/dev/null \
             | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}'); do
    printf '%s\n' "$REUSE_IOS" | grep -qx "$u" && continue   # сохранить pre-existing сим
    xcrun simctl shutdown "$u" >/dev/null 2>&1 || true       # НЕ erase — это снос данных
  done
  if [ -x "$ADB" ]; then
    for s in $("$ADB" devices 2>/dev/null | awk '/^emulator-/{print $1}'); do
      [ "$s" = "$REUSE_ANDROID" ] && continue   # сохранить переиспользуемый эмулятор
      "$ADB" -s "$s" emu kill >/dev/null 2>&1 || true
    done
  fi
  pkill -f "build/macos/Build/Products/Debug/Liza.app" >/dev/null 2>&1 || true
  sleep 3   # kill асинхронный — дать RAM реально вернуться до следующей фазы
}
trap teardown_mobile EXIT INT TERM
teardown_mobile   # defensive: прибрать остатки прошлого упавшего прогона

echo "Доступная RAM: $(avail_mb) МБ; своп: $(sysctl -n vm.swapusage 2>/dev/null || echo n/a)"

# Папка кандидатов-скриншотов (Ярус B): авто-захват на зелёных UI-кейсах. macOS-
# приложение под app-sandbox пишет их в свой контейнер (Documents/liza-e2e-shots);
# сюда, в /tmp вне репо, run-all забирает после фазы. По git-sha → перезаписывается
# между прогонами одного HEAD, не растёт бесконечно.
export LIZA_E2E_SHOTS_DIR="${LIZA_E2E_SHOTS_DIR:-/tmp/liza-e2e-shots/$(git rev-parse --short HEAD 2>/dev/null || echo nogit)}"
# sandbox-контейнер macOS-приложения, куда snapCandidate пишет кадры.
MACOS_SHOTS_CONTAINER="$HOME/Library/Containers/com.prodamus.laba.liza/Data/Documents/liza-e2e-shots"
# Пред-очистка: чтобы не собрать устаревшие кадры прошлого прогона как свежие.
rm -f "$MACOS_SHOTS_CONTAINER"/*.png 2>/dev/null || true
echo "Кандидаты-скриншоты соберём в: $LIZA_E2E_SHOTS_DIR"

# Забрать кандидаты из sandbox-контейнера macOS-приложения в LIZA_E2E_SHOTS_DIR.
collect_macos_shots() {
  ls "$MACOS_SHOTS_CONTAINER"/*.png >/dev/null 2>&1 || return 0
  mkdir -p "$LIZA_E2E_SHOTS_DIR"
  cp "$MACOS_SHOTS_CONTAINER"/*.png "$LIZA_E2E_SHOTS_DIR"/ 2>/dev/null || true
  echo "Собрано кандидатов из sandbox: $(ls "$LIZA_E2E_SHOTS_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')"
}

# ── 0a. Кросс-сессионная агрегация требований (read-only, до golden) ──
# Собирает по diff ветки (origin/main...HEAD) затронутые RL-записи ЛЮБОЙ сессии и
# выводит их критерии приёмки обязательным чек-листом. Внедрено после 3704, где
# требование футера жило в диалоге ПАРАЛЛЕЛЬНОЙ сессии, а e2e гнали в другой.
# Advisory по умолчанию (не роняет прогон); блок — при незакоммиченных RL в чужом
# worktree на общей ветке (реальная потеря источника правды) или E2E_AGG_STRICT=1.
phase "aggregate (кросс-сессионные требования)"
if bash clients/flutter/scripts/e2e/session-aggregate.sh; then ok "aggregate"; else
  bad "aggregate" "CROSS_SESSION_DEBT (незакоммиченные RL/критерии в чужом worktree)"
fi

# Жизненный цикл эмуляторов (AC-11/12/13). Дёшево и без устройств, поэтому стоит
# ДО тяжёлых фаз: лончер без teardown должен краснеть сразу, а не обнаруживаться
# через двое суток по забытому окну на экране (инцидент 2026-09-04).
phase "lifecycle (жизненный цикл эмуляторов)"
if bash clients/flutter/scripts/e2e/emulator-lifecycle-check.sh; then ok "lifecycle"; else
  bad "lifecycle" "LAUNCHER_WITHOUT_TEARDOWN"
fi

# ── 0. Golden (детерминированный гейт, без устройств) ──
phase "golden (Ярус 0)"
if run_to 600 make e2e-golden; then ok "golden"; else
  rc=$?; [ "$rc" = 124 ] && bad "golden" "FAIL_TIMEOUT" || bad "golden" "FAIL_ASSERT"
fi

# ── A0б. Host-набор клиента ЦЕЛИКОМ (Ярус 0) ──
# Фаза заведена 2026-09-09 по той же находке, что и push-monitoring ниже.
# `make e2e-golden` — это `flutter test --tags golden`, то есть ТОЛЬКО тесты с
# тегом; 314 из 321 host-файлов клиента (2425 тестов) не исполнял НИКТО — ни эта
# фаза, ни macOS/iOS/Android (те гоняют integration_test), ни CI. ledger-check.sh
# проверяет НАЛИЧИЕ тега `ledger:`/`AC:`, а не зелёность — поэтому страж мог быть
# красным или вовсе не компилироваться, а реестр числил запись покрытой.
# Замер при заведении фазы: 2425 тестов, all passed, 79 с — цена фазы копеечная.
phase "host-suite (весь flutter test)"
if run_to 900 make client-test; then ok "host-suite"; else
  rc=$?; [ "$rc" = 124 ] && bad "host-suite" "FAIL_TIMEOUT" || bad "host-suite" "FAIL_ASSERT"
fi

# ── A1. macOS desktop ──
phase "macOS"
if run_to 600 make e2e-local; then ok "macOS"; else
  rc=$?; [ "$rc" = 124 ] && bad "macOS" "FAIL_TIMEOUT" || bad "macOS" "FAIL_ASSERT"
fi
collect_macos_shots   # забрать кандидаты-скриншоты из sandbox независимо от исхода

# fail-fast вверх по цене: красный golden/macOS → мобильные не гоняем (дорого
# валидировать поверх сломанного), кроме явного E2E_FORCE=1.
UPSTREAM_RED=0
[ ${#FAIL[@]} -gt 0 ] && UPSTREAM_RED=1

# ── A2. iOS-симулятор ──
phase "iOS"
if [ "${E2E_SKIP_IOS:-0}" = 1 ]; then skip "iOS" "E2E_SKIP_IOS=1"
elif [ "$UPSTREAM_RED" = 1 ] && [ "${E2E_FORCE:-0}" != 1 ]; then skip "iOS" "SKIP_UPSTREAM (golden/macOS красные)"
elif ! xcrun simctl list runtimes 2>/dev/null | grep -qi ios; then
  skip "iOS" "SKIP_NO_TOOLING (нет iOS-runtime: xcodebuild -downloadPlatform iOS)"
elif [ "$(avail_mb)" -lt 3000 ]; then skip "iOS" "SKIP_NO_RAM ($(avail_mb)<3000 МБ)"
else
  teardown_mobile
  if run_to 900 make e2e-ios; then ok "iOS"; else
    rc=$?; [ "$rc" = 124 ] && bad "iOS" "FAIL_TIMEOUT" || bad "iOS" "FAIL"
  fi
fi

# ── A3. Android-эмулятор — КРИТИЧНАЯ фаза блок-гейта (см. .githooks/pre-push).
# host-golden платформо-независим и не ловит расхождения рендера Android; поэтому
# девайсный render_widgets_test обязателен. run-android.sh переиспользует уже
# загруженный эмулятор / существующий AVD (liza_test), свой не плодит. SKIP по
# инфраструктуре НЕ пишет Android в pass[] → push такой lib-ветки блокируется до
# реального прогона (или осознанного LIZA_SKIP_E2E_GATE=1). ──
phase "Android"
# Переиспользуемый эмулятор ПЕРЕЖИЛ teardown'ы (щажение в teardown_mobile) — он и
# есть основание не RAM-скипаться: считаем его загруженным, если серийник ещё жив.
BOOTED_EMU=0
[ -n "$REUSE_ANDROID" ] && "$ADB" devices 2>/dev/null | grep -q "^$REUSE_ANDROID" && BOOTED_EMU=1
if [ "${E2E_SKIP_ANDROID:-0}" = 1 ]; then skip "Android" "E2E_SKIP_ANDROID=1"
elif [ "$UPSTREAM_RED" = 1 ] && [ "${E2E_FORCE:-0}" != 1 ]; then skip "Android" "SKIP_UPSTREAM (golden/macOS красные)"
elif [ ! -x "$ADB" ]; then skip "Android" "SKIP_NO_TOOLING (нет Android SDK: $ANDROID_HOME)"
elif [ "$(avail_mb)" -lt 4000 ] && [ "$BOOTED_EMU" = 0 ]; then skip "Android" "SKIP_NO_RAM ($(avail_mb)<4000 МБ, эмулятор не загружен)"
else
  # teardown_mobile щадит $REUSE_ANDROID (см. определение выше) — гасит только
  # iOS-сим/остатки, сохраняя переиспользуемый эмулятор для run-android.sh.
  teardown_mobile
  if run_to 1200 make e2e-android; then ok "Android"; else
    rc=$?; [ "$rc" = 124 ] && bad "Android" "FAIL_TIMEOUT" || bad "Android" "FAIL"
  fi
fi

# ── A4. Windows (опц., через ssh win-runner) ──
phase "Windows"
if [ "${E2E_WITH_WINDOWS:-0}" != 1 ]; then skip "Windows" "E2E_WITH_WINDOWS≠1 (включить осознанно)"
else
  if bash clients/flutter/scripts/e2e/run-windows.sh; then ok "Windows"; else
    rc=$?; [ "$rc" = 2 ] && skip "Windows" "SKIP_NO_TOOLING (win-runner недоступен)" || bad "Windows" "FAIL"
  fi
  command -v prlctl >/dev/null && prlctl suspend "${LIZA_WIN_VM:-Windows 11}" 2>/dev/null || true
fi

# ── Серверные стражи пушей/мониторинга (Ярус 0, host-pytest) ──
# Фаза заведена 2026-09-09: до неё ~186 зелёных тестов (deploy/tests 110 +
# monitoring-notifier 76) не исполнял НИКТО — ни make-цели для deploy/tests, ни
# фазы здесь, ни CI. ledger-check.sh грепает наличие тега `AC:`, а не зелёность,
# поэтому критерии приёмки серверной ноги пушей числились выполненными вхолостую.
phase "push-monitoring (серверные стражи)"
if make -s test-push-monitoring; then ok "push-monitoring"; else
  bad "push-monitoring" "серверные стражи пушей/мониторинга красные"
fi

# ── Стражи AI-ботов (Ярус 0, host-pytest) ──
# Фаза заведена 2026-09-10 по тому же поводу, что и push-monitoring выше: ~382
# теста ботов (@liza 268, shared 33, xl 38, liza_news 27, manage_admin_db 16) не
# исполнял НИКТО. Два из них были КРАСНЫМИ с коммита f10d6b67 и невидимыми.
# Здесь живут стражи MCP-расширений: кап итераций, allowlist тулов, усечение
# результата, деградация вместо молчания, порядок MCP→advisor.
phase "bots (стражи @liza/MCP/XL)"
if make -s test-bots; then ok "bots"; else
  bad "bots" "стражи AI-ботов красные"
fi

# ── Классы Synapse-инстансов (Ярус 0, host-pytest) ──
# Фаза заведена 2026-09-17 (LABA-2539): конфиг инстанса — тоже прод-поведение.
# `auto_add_new: true` уехало копипастой на общий B2C-инстанс, и чаты посторонних
# людей три недели цеплялись в личное пространство первого юзера. Машинной
# проверки у конфигов не было вовсе (grep даёт ложный матч на комментарий).
phase "instance-config (классы инстансов)"
if make -s test-instance-config; then ok "instance-config"; else
  bad "instance-config" "авто-привязка чатов объявлена не на компании"
fi

# ── Реконсиляция реестра регрессии (что «полное» отличает от «прогнать всё») ──
phase "ledger (реестр регрессии)"
if bash clients/flutter/scripts/e2e/ledger-check.sh; then ok "ledger"; else
  bad "ledger" "UNCOVERED (запись без живого стража — возможно потеряно)"
fi

# ── Визуальные baseline (Ярус B): reference-скриншоты реального UI ──
# ГЛОБАЛЬНО visual остаётся advisory: если сделать «любой visual:required без
# baseline» блокирующим, один незакрытый скрин навсегда рубит push ЛЮБОЙ lib-ветки
# (сейчас 11 записей без эталона). БЛОКИРУЮЩАЯ часть — ветко-СКОУПНАЯ: фаза
# `aggregate` + `AC_UNASSERTED` в ledger требуют покрытия для ЗАТРОНУТЫХ веткой
# фич. Здесь — громкий сигнал по всему реестру (visual-check.sh: exit 2 = долг
# required-baseline, exit 1 = осиротевший каталог). Внедрено после 3704: раньше
# этот долг тонул молча, и баг рендера уехал в релиз.
phase "visual (reference-скриншоты)"
if bash clients/flutter/scripts/e2e/visual-check.sh; then ok "visual"; else
  vrc=$?
  VISUAL_WARN=1
  [ "$vrc" = 2 ] && echo "⚠ visual: есть visual:required без снятого baseline — ДОЛГ приёмки (см. MOCK_ONLY/aggregate; сними эталон перед релизом затронутой фичи)."
fi

# ── Сводка ──
echo; echo "════════ ИТОГ ════════"
printf 'PASS (%d): %s\n' "${#PASS[@]}" "${PASS[*]:-—}"
printf 'SKIP (%d): %s\n' "${#SKIP[@]}" "${SKIP[*]:-—}"
printf 'FAIL (%d): %s\n' "${#FAIL[@]}" "${FAIL[*]:-—}"
echo
echo "НЕ покрыто этим прогоном (всегда ручное/девайсное): iOS-NSE/фоновый пуш,"
echo "реальные устройства, звук/визуальный jank, federation/OIDC. См. tests/e2e.md §6."

# Кандидаты-скриншоты: путь + готовая команда приёмки эталона Яруса B.
if [ -d "$LIZA_E2E_SHOTS_DIR" ] && ls "$LIZA_E2E_SHOTS_DIR"/*.png >/dev/null 2>&1; then
  echo
  echo "Кандидаты-скриншоты (сверь ГЛАЗАМИ, НЕ коммить из /tmp):"
  ls -1 "$LIZA_E2E_SHOTS_DIR"/*.png 2>/dev/null | sed 's/^/  /'
  echo "Принять эталон (Ярус B): clients/flutter/scripts/e2e/snap-feature.sh \\"
  echo "  <slug> <name> $LIZA_E2E_SHOTS_DIR/<slug>__<case>.png \"<описание>\" macos <build>"
fi

# Маркер прохождения e2e для гейта на push/MR (см. .githooks/pre-push). Пишем
# ТОЛЬКО при отсутствии FAIL и с реальными списками фаз — «маркер валиден» и
# «e2e зелёный» атомарно связаны, echo-подделка не проходит гейт (нужны фазы).
write_marker() {
  local sha ts
  sha=$(git rev-parse HEAD 2>/dev/null || echo unknown)
  ts=$(date +%s)
  mkdir -p test-results
  {
    printf '{\n'
    printf '  "sha": "%s",\n' "$sha"
    printf '  "ts": %s,\n' "$ts"
    printf '  "pass": [%s],\n' "$(printf '"%s",' "${PASS[@]}" | sed 's/,$//')"
    printf '  "skip": [%s]\n'  "$(printf '"%s",' "${SKIP[@]:-}" | sed 's/,$//;s/""//')"
    printf '}\n'
  } > test-results/e2e-pass.json
  echo "Маркер e2e записан: test-results/e2e-pass.json (sha=${sha:0:8})"
}

if [ ${#FAIL[@]} -eq 0 ]; then
  write_marker
  echo "→ Автоматические фазы зелёные (SKIP ≠ pass)."
  if [ "${VISUAL_WARN:-0}" = 1 ]; then
    echo "⚠ VISUAL (Ярус B, РУЧНАЯ сверка): есть незакрытые/осиротевшие эталоны."
    echo "  Маркер записан по автофазам, НО перед MR сними/сверь эталоны глазами:"
    echo "  make e2e-visual → snap-feature.sh <slug> <name> <png> \"<desc>\" macos <build>"
  fi
  exit 0
else
  # Красный прогон не должен оставлять валидный маркер от прошлого раза.
  rm -f test-results/e2e-pass.json 2>/dev/null || true
  exit 1
fi
