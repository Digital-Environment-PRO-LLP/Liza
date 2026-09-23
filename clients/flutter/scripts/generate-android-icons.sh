#!/bin/bash

# Скрипт для генерации иконок Android из исходной иконки 1024x1024
# Использует ImageMagick

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Путь к исходной иконке (1024x1024 из iOS)
SOURCE_ICON="ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"

# Путь к папке с ресурсами Android
ANDROID_RES_DIR="android/app/src/main/res"

echo -e "${GREEN}Генерация иконок для Android${NC}"
echo ""

# Проверка наличия ImageMagick
if ! command -v magick &> /dev/null; then
    echo -e "${RED}ImageMagick не установлен${NC}"
    echo "Установите: brew install imagemagick"
    exit 1
fi

# Проверка наличия исходной иконки
if [ ! -f "$SOURCE_ICON" ]; then
    echo -e "${RED}Ошибка: Исходная иконка не найдена: $SOURCE_ICON${NC}"
    echo "Убедитесь, что файл существует"
    exit 1
fi

# Проверка размера исходной иконки
ICON_SIZE=$(sips -g pixelWidth "$SOURCE_ICON" 2>/dev/null | grep pixelWidth | awk '{print $2}' || magick identify -format "%w" "$SOURCE_ICON")
if [ "$ICON_SIZE" != "1024" ]; then
    echo -e "${YELLOW}Предупреждение: Размер исходной иконки ${ICON_SIZE}x${ICON_SIZE}${NC}"
    echo "Рекомендуется использовать иконку 1024x1024"
fi

echo "Исходная иконка: $SOURCE_ICON"
echo "Целевая папка: $ANDROID_RES_DIR"
echo ""

# Размеры иконок для каждой плотности экрана
# mdpi: 48x48, hdpi: 72x72, xhdpi: 96x96, xxhdpi: 144x144, xxxhdpi: 192x192
DENSITY_NAMES="mdpi hdpi xhdpi xxhdpi xxxhdpi"
DENSITY_SIZES="48 72 96 144 192"

echo "Генерация растровых иконок..."
echo ""

# Генерация
set -- $DENSITY_SIZES
for density in $DENSITY_NAMES; do
    size=$1; shift
    output_dir="$ANDROID_RES_DIR/mipmap-${density}"
    output_file="$output_dir/ic_launcher.png"

    mkdir -p "$output_dir"

    echo -e "  Генерация ${YELLOW}mipmap-${density}/ic_launcher.png${NC} (${size}x${size})..."

    magick "$SOURCE_ICON" \
        -resize "${size}x${size}" \
        -strip \
        "$output_file"

    echo -e "  ${GREEN}OK${NC} mipmap-${density}/ic_launcher.png"
done

echo ""

# Проверка созданных файлов
echo "Проверка созданных файлов:"
echo ""

set -- $DENSITY_SIZES
for density in $DENSITY_NAMES; do
    expected_size=$1; shift
    file="$ANDROID_RES_DIR/mipmap-${density}/ic_launcher.png"
    if [ -f "$file" ]; then
        actual_size=$(sips -g pixelWidth "$file" 2>/dev/null | grep pixelWidth | awk '{print $2}' || magick identify -format "%w" "$file")
        if [ "$actual_size" = "$expected_size" ]; then
            echo -e "  ${GREEN}OK${NC} mipmap-${density}/ic_launcher.png (${actual_size}x${actual_size})"
        else
            echo -e "  ${YELLOW}WARN${NC} mipmap-${density}/ic_launcher.png (${actual_size}x${actual_size}, ожидалось ${expected_size}x${expected_size})"
        fi
    else
        echo -e "  ${RED}FAIL${NC} mipmap-${density}/ic_launcher.png отсутствует"
    fi
done

echo ""
echo -e "${GREEN}Готово! Иконки для Android сгенерированы${NC}"
echo ""
echo "Следующие шаги:"
echo "1. Проверьте иконки в $ANDROID_RES_DIR/mipmap-*/"
echo "2. Соберите: flutter build apk --release"
