#!/bin/bash

# Скрипт для генерации иконок iOS из исходной иконки 1024x1024
# Использует ImageMagick для ресайза

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Путь к исходной иконке (1024x1024 из iOS — мастер-файл)
SOURCE_ICON="ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"

# Путь к папке с иконками iOS
IOS_ICON_DIR="ios/Runner/Assets.xcassets/AppIcon.appiconset"

echo -e "${GREEN}Генерация иконок для iOS${NC}"
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
echo "Целевая папка: $IOS_ICON_DIR"
echo ""

# Функция генерации иконки
generate_icon() {
    local size=$1
    local filename=$2

    echo -e "  Генерация ${YELLOW}${filename}${NC} (${size}x${size})..."

    magick "$SOURCE_ICON" \
        -resize "${size}x${size}" \
        -strip \
        "$IOS_ICON_DIR/$filename"

    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}OK${NC} $filename"
    else
        echo -e "  ${RED}FAIL${NC} $filename"
        return 1
    fi
}

echo "Генерация иконок..."
echo ""

# iPhone иконки
generate_icon 40 "Icon-App-20x20@2x.png"    # 20x20 @2x
generate_icon 60 "Icon-App-20x20@3x.png"    # 20x20 @3x
generate_icon 29 "Icon-App-29x29@1x.png"    # 29x29 @1x
generate_icon 58 "Icon-App-29x29@2x.png"    # 29x29 @2x
generate_icon 87 "Icon-App-29x29@3x.png"    # 29x29 @3x
generate_icon 80 "Icon-App-40x40@2x.png"    # 40x40 @2x
generate_icon 120 "Icon-App-40x40@3x.png"   # 40x40 @3x
generate_icon 57 "Icon-App-57x57@1x.png"    # 57x57 @1x
generate_icon 114 "Icon-App-57x57@2x.png"   # 57x57 @2x
generate_icon 120 "Icon-App-60x60@2x.png"   # 60x60 @2x
generate_icon 180 "Icon-App-60x60@3x.png"   # 60x60 @3x

# iPad иконки
generate_icon 20 "Icon-App-20x20@1x.png"    # 20x20 @1x
generate_icon 50 "Icon-App-50x50@1x.png"    # 50x50 @1x
generate_icon 100 "Icon-App-50x50@2x.png"   # 50x50 @2x
generate_icon 40 "Icon-App-40x40@1x.png"    # 40x40 @1x
generate_icon 72 "Icon-App-72x72@1x.png"    # 72x72 @1x
generate_icon 144 "Icon-App-72x72@2x.png"   # 72x72 @2x
generate_icon 76 "Icon-App-76x76@1x.png"    # 76x76 @1x
generate_icon 152 "Icon-App-76x76@2x.png"   # 76x76 @2x
generate_icon 167 "Icon-App-83.5x83.5@2x.png"  # 83.5x83.5 @2x

# Маркетинговая иконка (1024x1024 — это сам source, но пересохраняем для единообразия)
echo -e "  ${GREEN}OK${NC} Icon-App-1024x1024@1x.png (source — без изменений)"

echo ""

# Проверка
echo "Проверка созданных файлов:"
echo ""

TOTAL=0
OK=0
for file in "$IOS_ICON_DIR"/Icon-App-*.png; do
    if [ -f "$file" ]; then
        TOTAL=$((TOTAL + 1))
        actual_size=$(sips -g pixelWidth "$file" 2>/dev/null | grep pixelWidth | awk '{print $2}' || magick identify -format "%w" "$file")
        echo -e "  ${GREEN}OK${NC} $(basename $file) (${actual_size}x${actual_size})"
        OK=$((OK + 1))
    fi
done

echo ""
echo -e "${GREEN}Готово! $OK/$TOTAL иконок для iOS сгенерированы${NC}"
echo ""
echo "Следующие шаги:"
echo "1. Откройте проект в Xcode: open ios/Runner.xcworkspace"
echo "2. Проверьте иконки в Assets.xcassets"
echo "3. Соберите: flutter build ios --release"
