#!/usr/bin/env bash
# E2E на Android-эмуляторе. Запуск: make e2e-android. См. tests/e2e.md.
#
# Две проверки на РЕАЛЬНОМ Android-бинаре:
#   1) render_widgets_test — рендер прод-виджетов AudioWaveformSlider +
#      CornerTimeLayout (Ярус C, сервер НЕ нужен). Ловит расхождения рендера
#      Android, которые host-golden (Ahem, платформо-независим) не видит.
#   2) receipts_test — сквозная доставка+прочтение против локального Synapse
#      (adb reverse http://localhost:8008; Dart на Android не доверяет user-CA).
#
# ⚠️ AVD: НЕ создаём свой каждый раз (это ломалось на отсутствующем system-image).
# Порядок выбора устройства:
#   а) уже загруженный эмулятор — используем его (ничего не создаём/не грузим);
#   б) существующий AVD: $LIZA_E2E_AVD → liza_test → первый из `avdmanager list`;
#   в) как ПОСЛЕДНЕЕ средство — создать liza_e2e (нужен system-image). Если
#      тулинга/образа нет — выходим с кодом 2 (NO_TOOLING), чтобы run-all.sh
#      пометил фазу SKIP, а не FAIL.
set -uo pipefail
cd "$(dirname "$0")/../.."

ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
IMG="system-images;android-34;google_apis;arm64-v8a"

no_tooling() { echo "SKIP_NO_TOOLING: $1" >&2; exit 2; }
[ -x "$ADB" ] || no_tooling "нет adb ($ADB) — Android SDK не установлен"

# ⚠ JDK ≥17 ОБЯЗАТЕЛЕН для avdmanager/sdkmanager (рецидив 2026-09-08). Иначе они
# печатают «This tool requires JDK 17 or later» в stderr и выходят с ошибкой, а
# `avds=$(...)` тихо получает ПУСТУЮ строку — скрипт решает «AVD нет вовсе»,
# пытается создать свой и падает на отсутствующем system-image, выдавая
# SKIP_NO_TOOLING. То есть настоящая причина (старый java в PATH) маскируется
# под «нет тулинга», хотя AVD `liza_test` на месте. Берём JBR Android Studio —
# он ставится вместе с ним и заведомо ≥17.
if ! java -version 2>&1 | grep -qE '"(1[7-9]|2[0-9])[.".]'; then
  for jbr in "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
             "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home"; do
    if [ -x "$jbr/bin/java" ]; then export JAVA_HOME="$jbr"; PATH="$jbr/bin:$PATH"; break; fi
  done
fi

# ── Жизненный цикл эмулятора: «кто поднял — тот и гасит» ──────────────────────
# Инцидент 2026-09-04: скрипт бутил AVD и уходил БЕЗ teardown (ни одного `trap`) —
# эмулятор прожил 1д16ч и утащил MacBook в своп. Teardown точечный: гасим ТОЛЬКО
# забученное НАМИ; уже загруженный до нас эмулятор щадим (тот же принцип, что в
# run-all.sh:teardown_mobile). Запись в общий ledger нужна на случай, когда trap
# не сработает вовсе (SIGKILL/краш) — сироту подберёт reap-orphaned.sh по мёртвому
# pid-владельцу. Оставить эмулятор живым (цепочка make e2e-push-android):
# LIZA_E2E_KEEP_EMULATOR=1.
STATEFILE="${PROVE_UI_STATEFILE:-/tmp/prove-ui-booted.tsv}"
WE_BOOTED=0          # 1 — эмулятор подняли мы (а не переиспользовали)
BOOTED_ANDROID=""    # serial, забученный нами; пусто → teardown молчит
LEDGER_WRITTEN=""

TEARDOWN_DONE=0
teardown_emulator() {
  # trap ловит и TERM, и последующий EXIT — без флага teardown отработал бы дважды.
  if [ "$TEARDOWN_DONE" = 1 ]; then return 0; fi
  TEARDOWN_DONE=1
  # Код возврата grep НЕ проверяем: когда наша запись единственная, вывод пуст и
  # grep возвращает 1 — прежний `&& mv` оставлял бы строку в ledger навсегда, а
  # позже reaper погасил бы по ней ЧУЖОЙ эмулятор с тем же serial.
  if [ -n "$LEDGER_WRITTEN" ] && [ -f "$STATEFILE" ]; then
    grep -v "^$$	" "$STATEFILE" > "$STATEFILE.$$" 2>/dev/null || true   # grep=1 при пустом выводе; под set -e это оборвало бы трап
    mv "$STATEFILE.$$" "$STATEFILE" 2>/dev/null || rm -f "$STATEFILE.$$" 2>/dev/null
  fi
  [ -n "$BOOTED_ANDROID" ] || return 0
  if [ "${LIZA_E2E_KEEP_EMULATOR:-0}" = 1 ]; then
    echo "[e2e-android] LIZA_E2E_KEEP_EMULATOR=1 — оставляю $BOOTED_ANDROID живым"
    return 0
  fi
  echo "[e2e-android] teardown: гашу $BOOTED_ANDROID (подняли мы)"
  "$ADB" -s "$BOOTED_ANDROID" emu kill >/dev/null 2>&1 || true
  # `emu kill` умеет молча провалиться при включённой console-auth. Добиваем
  # ТОЧЕЧНО: console-порт эмулятора равен числу в serial, владелец сокета — его
  # собственный qemu. Маску всех qemu не трогаем — это убило бы чужой эмулятор.
  sleep 2
  if "$ADB" devices 2>/dev/null | grep -q "^$BOOTED_ANDROID"; then
    port="${BOOTED_ANDROID#emulator-}"
    pid=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -1)
    [ -n "${pid:-}" ] && { echo "[e2e-android] emu kill не сработал — гашу pid $pid"; kill "$pid" 2>/dev/null || true; }
  fi
}
trap teardown_emulator EXIT INT TERM

# ── а) уже загруженный эмулятор? ──
SERIAL=$("$ADB" devices 2>/dev/null | awk '/^emulator-/{print $1; exit}')

if [ -z "${SERIAL:-}" ]; then
  # ── б) выбрать существующий AVD (не плодим свой) ──
  avds=""
  [ -x "$AVDMANAGER" ] && avds=$("$AVDMANAGER" list avd 2>/dev/null | awk -F': *' '/Name:/{print $2}')
  pick=""
  for cand in "${LIZA_E2E_AVD:-}" "liza_test"; do
    [ -n "$cand" ] || continue
    if printf '%s\n' "$avds" | grep -qx "$cand"; then pick="$cand"; break; fi
  done
  # иначе — первый доступный AVD
  [ -z "$pick" ] && pick=$(printf '%s\n' "$avds" | awk 'NF{print;exit}')

  # ── в) последнее средство: создать liza_e2e (нужен system-image) ──
  if [ -z "$pick" ]; then
    [ -x "$EMULATOR" ] && [ -x "$AVDMANAGER" ] || no_tooling "нет emulator/avdmanager"
    echo "Нет ни одного AVD — создаю liza_e2e ($IMG)"
    yes | "$SDKMANAGER" "$IMG" >/dev/null 2>&1 || no_tooling "не ставится system-image $IMG"
    echo no | "$AVDMANAGER" create avd -n liza_e2e -d pixel_7 --package "$IMG" \
      >/dev/null 2>&1 || no_tooling "не создаётся AVD liza_e2e"
    pick="liza_e2e"
  fi

  echo "Запускаю эмулятор $pick"
  [ -x "$EMULATOR" ] || no_tooling "нет emulator-бинаря ($EMULATOR)"
  "$EMULATOR" @"$pick" -no-audio -no-boot-anim -no-snapshot-save >/dev/null 2>&1 &
  WE_BOOTED=1   # подняли мы → гасим на выходе (serial станет известен после boot)
  SERIAL=$("$ADB" devices 2>/dev/null | awk '/^emulator-/{print $1; exit}')
else
  echo "Переиспользую уже загруженный эмулятор: $SERIAL"
fi

# Ждём загрузки С ТАЙМАУТОМ. `adb wait-for-device` и голый `while boot_completed`
# без предела при `make e2e-android` (нет watchdog run_to) вешали сессию навсегда
# на битом/зависшем эмуляторе (SERIOUS-5, трибунал 2026-07-28). Единый bounded
# poll: getprop молча падает пока девайс не поднялся, дедлайн ограничивает висяк.
BOOT_DEADLINE=$((SECONDS + 300))
until [ "$("$ADB" -s "${SERIAL:-none}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  [ -n "${SERIAL:-}" ] || SERIAL=$("$ADB" devices 2>/dev/null | awk '/^emulator-/{print $1; exit}')
  [ "$SECONDS" -gt "$BOOT_DEADLINE" ] && no_tooling "эмулятор ${SERIAL:-?} не загрузился за 300с (битый/висит)"
  sleep 2
done
echo "Эмулятор готов: $SERIAL"

# Регистрация в ledger — ДО передачи управления тестам, чтобы сирота нашлась даже
# если нас убьют посреди прогона. Формат общий с prove-ui: pid\tios\tandroid.
if [ "$WE_BOOTED" = 1 ] && [ -n "${SERIAL:-}" ]; then
  BOOTED_ANDROID="$SERIAL"
  printf '%s\t%s\t%s\n' "$$" "" "$SERIAL" >> "$STATEFILE" 2>/dev/null && LEDGER_WRITTEN=1
fi

# Детерминируем установку: сносим прошлый APK, чтобы инкрементальный gradle/APK-кэш
# не подсунул СТАРЫЙ бинарь без нового Dart-кода → ложный FAIL/PASS render-теста
# (SERIOUS-3, трибунал 2026-07-28). Best-effort — на свежем эмуляторе пакета нет.
"$ADB" -s "$SERIAL" uninstall com.prodamus.laba.liza >/dev/null 2>&1 || true

# ── 1) Девайсный рендер прод-виджетов — ОБЯЗАТЕЛЬНАЯ проверка (блокирует фазу).
# Сервер НЕ нужен → детерминированно, без флаки. Это и есть суть Android-гейта:
# поймать расхождение рендера на устройстве, невидимое платформо-независимому
# host-golden. `|| exit 1` обязателен — у скрипта НЕТ `set -e` (AVD-логика выше
# использует `A && B`), поэтому падение теста надо провалить явно, иначе его
# замаскировал бы следующий best-effort шаг.
echo "── render_widgets_test (Ярус C, рендер на устройстве) — ОБЯЗАТЕЛЬНО ──"
flutter test integration_test/liza/render_widgets_test.dart \
  -d "$SERIAL" \
  --dart-define=APP_ENV=local \
  --timeout 10m \
  || { echo "✗ render_widgets_test упал на устройстве — Android-фаза FAIL" >&2; exit 1; }

# ── 2) Сквозная доставка+прочтение (receipts) — ТОЛЬКО по opt-in, НЕ в гейте.
# Смысл Android-гейта — девайсный РЕНДЕР (шаг 1), детерминированный и без сервера.
# receipts требует ПОЛНЫЙ локальный стек + сид + adb reverse и на Android
# исторически флака по времени/сети, а её падение-cleanup умеет ВИСНУТЬ — под
# watchdog'ом run-all это убило бы фазу уже ПОСЛЕ зелёного рендера. Поэтому в гейт
# её не берём (та же доставка+прочтение надёжно проверяется на macOS в e2e-local).
# Кто хочет прогнать её и на Android — E2E_ANDROID_RECEIPTS=1 (best-effort, не
# влияет на exit-код фазы).
if [ "${E2E_ANDROID_RECEIPTS:-0}" = 1 ]; then
  echo "── receipts_test (доставка+прочтение) — opt-in best-effort, НЕ блокирует ──"
  "$ADB" -s "$SERIAL" reverse tcp:8008 tcp:8008 || true
  if flutter test integration_test/liza/receipts_test.dart \
    -d "$SERIAL" \
    --dart-define=APP_ENV=local \
    --dart-define=E2E_HOMESERVER=http://localhost:8008 \
    --timeout 10m; then
    echo "✓ receipts_test на устройстве прошёл"
  else
    echo "⚠ receipts_test на Android НЕ прошёл (best-effort; покрыто на macOS e2e-local)." >&2
  fi
fi

echo "✓ Android render-гейт зелёный (render_widgets_test на устройстве)."
exit 0
