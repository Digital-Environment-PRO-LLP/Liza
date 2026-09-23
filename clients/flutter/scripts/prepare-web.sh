#!/bin/sh -ve

version=$(yq ".dependencies.flutter_vodozemac" < pubspec.yaml)
version=$(expr "$version" : '\^*\(.*\)')
git clone https://github.com/famedly/dart-vodozemac.git -b ${version} .vodozemac
cd .vodozemac
cargo install flutter_rust_bridge_codegen
flutter_rust_bridge_codegen build-web --dart-root dart --rust-root $(readlink -f rust) --release
cd ..
rm -f ./assets/vodozemac/vodozemac_bindings_dart*
mv .vodozemac/dart/web/pkg/vodozemac_bindings_dart* ./assets/vodozemac/
rm -rf .vodozemac

flutter pub get
flutter gen-l10n

dart compile js ./web/native_executor.dart -o ./web/native_executor.js -m

# Мониторинг ошибок (dart-defines, no-op без LIZA_FLUTTER_DSN)
. "$(dirname "$0")/_monitoring-args.sh"

# Контур сборки. Без APP_ENV=dev клиент берёт defaultValue 'prod' из
# app_config.dart и ходит в прод-auth-proxy — даже будучи выложенным на
# dev.web.liza.ru (так dev-домен раздавал prod-авторизацию до 2026-08-03).
APP_ENV="${APP_ENV:-prod}"

flutter build web --release --dart-define=APP_ENV="$APP_ENV" $MONITORING_ARGS
python3 ./scripts/remove_legacy_branding.py

# Cache-busting главного бандла.
#
# Flutter НЕ версионирует имена: main.dart.js одинаков от сборки к сборке,
# поэтому браузер с закешированной копией может отдать старый код до
# ревалидации (а service worker — ещё одну перезагрузку сверх того).
# Дописываем к ссылке ?v=<sha256 бандла> в flutter_bootstrap.js: URL меняется
# ТОЛЬКО когда изменилось содержимое, поэтому лишних загрузок 11 МБ нет.
#
# Именно query, а не переименование файла: внутри main.dart.js захардкожены
# имена 53 deferred-частей (main.dart.js_NNN.part.js) — переименование
# потребовало бы переписывать минифицированный JS. Для nginx query-строка при
# поиске файла на диске игнорируется, а для браузера это другой URL.
# flutter_bootstrap.js отдаётся с no-store, поэтому новую ссылку клиент
# увидит сразу; index.html править не нужно — он грузит bootstrap по имени.
./scripts/web-cache-bust.sh
# rm -rf ../../liza/test/**
# cp -rf ./build/web/* ../../liza/test/
