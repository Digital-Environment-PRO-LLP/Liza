#!/bin/sh -e
# Cache-busting главного бандла web-сборки.
#
# Проблема: Flutter не версионирует имена файлов — main.dart.js называется
# одинаково от сборки к сборке. Браузер (и его service worker) может отдать
# закешированный старый бандл, и свежий деплой доедет до пользователя не сразу.
#
# Решение: в flutter_bootstrap.js подменяем ссылку на бандл с
#   "mainJsPath":"main.dart.js"
# на
#   "mainJsPath":"main.dart.js?v=<sha256[:16] содержимого>"
#
# Почему query, а не переименование файла: внутри main.dart.js захардкожены
# имена deferred-частей (main.dart.js_NNN.part.js, их полсотни) — переименование
# главного файла потребовало бы переписывать минифицированный JS и ломалось бы
# при смене версии Flutter. Query-строка для nginx при поиске файла на диске
# игнорируется (отдаёт тот же файл, 200), а для браузера это ДРУГОЙ URL.
#
# Хеш от содержимого, а не номер сборки: URL меняется только когда бандл реально
# изменился, поэтому пользователи не перекачивают 11 МБ на каждый деплой.
#
# При повторном запуске хеш пересчитывается: предыдущий шаг сборки мог изменить
# содержимое бандла после первого проставления query-параметра.

BUILD_DIR="build/web"
BOOTSTRAP="$BUILD_DIR/flutter_bootstrap.js"
MAIN_JS="$BUILD_DIR/main.dart.js"

[ -f "$BOOTSTRAP" ] || { echo "✗ Нет $BOOTSTRAP — сначала flutter build web"; exit 1; }
[ -f "$MAIN_JS" ] || { echo "✗ Нет $MAIN_JS — сначала flutter build web"; exit 1; }

HASH=$(shasum -a 256 "$MAIN_JS" | cut -c1-16)

# Точечная подмена ровно значения mainJsPath: править весь файл нельзя —
# строка main.dart.js встречается в bootstrap и как дефолт лоадера, и в
# _flutter.buildConfig.
if grep -q 'main\.dart\.js?v=' "$BOOTSTRAP"; then
  sed -i.bak "s|\"mainJsPath\":\"main\.dart\.js?v=[^\"]*\"|\"mainJsPath\":\"main.dart.js?v=$HASH\"|g" "$BOOTSTRAP"
else
  sed -i.bak "s|\"mainJsPath\":\"main\.dart\.js\"|\"mainJsPath\":\"main.dart.js?v=$HASH\"|g" "$BOOTSTRAP"
fi
rm -f "$BOOTSTRAP.bak"

# Гейт: молчаливый промах здесь означал бы, что кеш-бастинг не работает, а
# сборка при этом «успешна». Формат buildConfig мог измениться с версией Flutter.
if ! grep -q "main\.dart\.js?v=$HASH" "$BOOTSTRAP"; then
  echo "✗ cache-bust: не нашёл \"mainJsPath\":\"main.dart.js\" в $BOOTSTRAP."
  echo "  Похоже, изменился формат flutter_bootstrap.js (версия Flutter?)."
  echo "  Почини подстановку в scripts/web-cache-bust.sh — молча пропускать нельзя."
  exit 1
fi

echo "✓ cache-bust: main.dart.js?v=$HASH"
