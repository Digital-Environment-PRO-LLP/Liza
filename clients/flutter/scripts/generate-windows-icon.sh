#!/bin/bash

# Скрипт для генерации Windows ICO из исходной иконки 1024x1024
# Использует ImageMagick для создания multi-resolution ICO

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Путь к исходной иконке (1024x1024 из iOS)
SOURCE_ICON="ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"

# Путь к целевому ICO файлу
WINDOWS_ICON="windows/runner/resources/app_icon.ico"

echo -e "${GREEN}Генерация иконки для Windows${NC}"
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

echo "Исходная иконка: $SOURCE_ICON"
echo "Целевой файл: $WINDOWS_ICON"
echo ""

# Создание папки если не существует
mkdir -p "$(dirname "$WINDOWS_ICON")"

# Размеры для ICO файла (стандартные Windows)
SIZES=(16 24 32 48 64 128 256)

echo "Генерация multi-resolution ICO..."
echo ""

# Создаём временные PNG для каждого размера
TEMP_DIR=$(mktemp -d)
TEMP_FILES=""

for size in "${SIZES[@]}"; do
    temp_file="$TEMP_DIR/icon_${size}.png"
    echo -e "  Подготовка ${YELLOW}${size}x${size}${NC}..."
    magick "$SOURCE_ICON" -resize "${size}x${size}" -strip "$temp_file"
    TEMP_FILES="$TEMP_FILES $temp_file"
done

echo ""
echo -e "  Сборка ICO файла..."

# Создаём ICO из всех временных PNG
magick $TEMP_FILES "$WINDOWS_ICON"

# Очистка временных файлов
rm -rf "$TEMP_DIR"

if [ -f "$WINDOWS_ICON" ]; then
    file_size=$(du -h "$WINDOWS_ICON" | awk '{print $1}')
    echo -e "  ${GREEN}OK${NC} $WINDOWS_ICON ($file_size)"
else
    echo -e "  ${RED}FAIL${NC} Не удалось создать ICO файл"
    exit 1
fi

echo ""
echo -e "${GREEN}Готово! Иконка для Windows сгенерирована${NC}"
echo ""
echo "Содержит размеры: ${SIZES[*]}"
echo ""
echo "Следующие шаги:"
echo "1. Проверьте иконку: $WINDOWS_ICON"
echo "2. Соберите: flutter build windows --release"
