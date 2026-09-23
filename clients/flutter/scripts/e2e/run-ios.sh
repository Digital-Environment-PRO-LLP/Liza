#!/usr/bin/env bash
# E2E на iOS-симуляторе: поднимает (или создаёт) сим LizaE2E, ставит
# mkcert CA в его keychain и гоняет integration_test против локального стека.
# Запуск: make e2e-ios (из корня репо). См. tests/e2e.md.
set -euo pipefail
cd "$(dirname "$0")/../.."

SIM_NAME="${LIZA_E2E_SIM_NAME:-LizaE2E}"

find_udid() {
  xcrun simctl list devices --json | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
for runtime, devs in devices.items():
    for dev in devs:
        if dev['name'] == '$SIM_NAME' and dev.get('isAvailable'):
            print(dev['udid'])
            sys.exit()
"
}

UDID="${LIZA_E2E_SIM_UDID:-$(find_udid)}"

if [ -z "$UDID" ]; then
  # Новейший доступный iOS runtime + iPhone device type, СОВМЕСТИМЫЙ именно с ним
  # (берём из runtime.supportedDeviceTypes — иначе список devicetypes не
  # отсортирован по новизне и «последний» бывает старым iPhone 6s, что даёт
  # SimError 403 Incompatible device на свежем рантайме). Модель выбираем по
  # наибольшему числу в имени; SE исключаем.
  SEL=$(xcrun simctl list runtimes --json | python3 -c "
import json, re, sys
runtimes = [r for r in json.load(sys.stdin)['runtimes']
            if r['platform'] == 'iOS' and r['isAvailable']]
runtimes.sort(key=lambda r: [int(x) for x in re.findall(r'\d+', r['version'])])
rt = runtimes[-1]
phones = [d for d in rt.get('supportedDeviceTypes', [])
          if d.get('productFamily') == 'iPhone' and 'SE' not in d['name']]
def num(d):
    m = re.findall(r'\d+', d['name'])
    return int(m[0]) if m else 0
phones.sort(key=num)
print(phones[-1]['identifier'] + '\t' + rt['identifier'])
")
  DEVICE_TYPE="${SEL%$'\t'*}"
  RUNTIME="${SEL#*$'\t'}"
  echo "Создаю симулятор $SIM_NAME ($DEVICE_TYPE, $RUNTIME)"
  UDID=$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME")
fi

echo "Симулятор: $UDID"

# ── Жизненный цикл симулятора: «кто поднял — тот и гасит» ─────────────────────
# Инцидент 2026-09-04: скрипт бутил сим и уходил БЕЗ teardown — сим LizaE2E висел
# сутками вторым тяжёлым процессом при бюджете в один. Гасим ТОЛЬКО то, что
# забутили сами (сим, загруженный владельцем до нас, щадим). `shutdown` — не
# `erase`: данные симулятора целы. Запись в общий ledger (формат prove-ui:
# pid\tios\tandroid) добивает сироту, если trap не сработает вовсе (SIGKILL).
# Оставить сим живым (цепочка make e2e-push-ios): LIZA_E2E_KEEP_EMULATOR=1.
STATEFILE="${PROVE_UI_STATEFILE:-/tmp/prove-ui-booted.tsv}"
BOOTED_IOS=""
LEDGER_WRITTEN=""

TEARDOWN_DONE=0
teardown_sim() {
  # trap ловит и TERM, и последующий EXIT — без флага teardown отработал бы дважды.
  if [ "$TEARDOWN_DONE" = 1 ]; then return 0; fi
  TEARDOWN_DONE=1
  # Код возврата grep НЕ проверяем: когда наша запись единственная, вывод пуст и
  # grep возвращает 1 — прежний `&& mv` оставлял бы строку в ledger навсегда, а
  # позже reaper погасил бы по ней ЧУЖУЮ цель с тем же идентификатором.
  if [ -n "$LEDGER_WRITTEN" ] && [ -f "$STATEFILE" ]; then
    grep -v "^$$	" "$STATEFILE" > "$STATEFILE.$$" 2>/dev/null || true   # grep=1 при пустом выводе; под set -e это оборвало бы трап
    mv "$STATEFILE.$$" "$STATEFILE" 2>/dev/null || rm -f "$STATEFILE.$$" 2>/dev/null
  fi
  [ -n "$BOOTED_IOS" ] || return 0
  if [ "${LIZA_E2E_KEEP_EMULATOR:-0}" = 1 ]; then
    echo "[e2e-ios] LIZA_E2E_KEEP_EMULATOR=1 — оставляю сим $BOOTED_IOS живым"
    return 0
  fi
  echo "[e2e-ios] teardown: гашу сим $BOOTED_IOS (подняли мы)"
  xcrun simctl shutdown "$BOOTED_IOS" >/dev/null 2>&1 || true
}
trap teardown_sim EXIT INT TERM

# Был ли сим загружен ДО нас — решает, наш он или владельца.
if xcrun simctl list devices booted 2>/dev/null | grep -q "$UDID"; then
  echo "Сим уже загружен до нас — щажу его на выходе"
else
  BOOTED_IOS="$UDID"
  printf '%s\t%s\t%s\n' "$$" "$UDID" "" >> "$STATEFILE" 2>/dev/null && LEDGER_WRITTEN=1
fi

xcrun simctl bootstatus "$UDID" -b

# CA mkcert: mkcert -install сим НЕ покрывает; ставим явно. После
# simctl erase — повторить (скрипт делает это на каждом прогоне, идемпотентно).
if command -v mkcert >/dev/null; then
  xcrun simctl keychain "$UDID" add-root-cert "$(mkcert -CAROOT)/rootCA.pem" || true
fi

flutter test integration_test/liza/receipts_test.dart \
  -d "$UDID" \
  --dart-define=APP_ENV=local \
  --timeout 10m
