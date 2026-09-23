#!/usr/bin/env bash
# Подсовывает Flutter-сборкам dart-defines для мониторинга ошибок
# (Sentry-совместимый DSN, например GlitchTip).
# Используется через `. "$(dirname "$0")/_monitoring-args.sh"`,
# затем — `flutter build … $MONITORING_ARGS`.
#
# Включается ТОЛЬКО когда задан LIZA_FLUTTER_DSN; без него сборка идёт без
# мониторинга, Monitoring.init() остаётся no-op.
#
#   export LIZA_FLUTTER_DSN="https://<key>@errors.example.org/1"
#   export MONITORING_ENV=prod

if [ -n "${LIZA_FLUTTER_DSN:-}" ]; then
  MONITORING_ARGS="\
--dart-define=MONITORING_ENABLED=true \
--dart-define=MONITORING_ENV=${MONITORING_ENV:-prod} \
--dart-define=MONITORING_DSN=${LIZA_FLUTTER_DSN}"
  echo "→ build с мониторингом ошибок (env=${MONITORING_ENV:-prod})"
else
  MONITORING_ARGS=""
  echo "→ build БЕЗ мониторинга ошибок (LIZA_FLUTTER_DSN не задан)"
fi
export MONITORING_ARGS
