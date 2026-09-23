#!/bin/bash

# Мастер-скрипт для генерации иконок всех платформ
# Запускает все скрипты генерации последовательно из корня проекта
# Требует: ImageMagick (brew install imagemagick)

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Генерация иконок для всех платформ${NC}"
echo -e "${BLUE}  Source: ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Проверка наличия ImageMagick
if ! command -v magick &> /dev/null; then
    echo -e "${RED}ImageMagick не установлен${NC}"
    echo "Установите: brew install imagemagick"
    exit 1
fi

# Проверка наличия source иконки
SOURCE_ICON="ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
if [ ! -f "$SOURCE_ICON" ]; then
    echo -e "${RED}Ошибка: Source иконка не найдена: $SOURCE_ICON${NC}"
    exit 1
fi

FAILED=0

# iOS
echo -e "${BLUE}[1/6] iOS иконки${NC}"
echo -e "${BLUE}------------------------------------------------${NC}"
if bash "$SCRIPT_DIR/generate-ios-icons.sh"; then
    echo -e "${GREEN}iOS: OK${NC}"
else
    echo -e "${RED}iOS: FAIL${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# macOS
echo -e "${BLUE}[2/6] macOS иконки${NC}"
echo -e "${BLUE}------------------------------------------------${NC}"
if bash "$SCRIPT_DIR/generate-macos-icons.sh"; then
    echo -e "${GREEN}macOS: OK${NC}"
else
    echo -e "${RED}macOS: FAIL${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Android
echo -e "${BLUE}[3/6] Android иконки${NC}"
echo -e "${BLUE}------------------------------------------------${NC}"
if bash "$SCRIPT_DIR/generate-android-icons.sh"; then
    echo -e "${GREEN}Android: OK${NC}"
else
    echo -e "${RED}Android: FAIL${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Windows
echo -e "${BLUE}[4/6] Windows иконка${NC}"
echo -e "${BLUE}------------------------------------------------${NC}"
if bash "$SCRIPT_DIR/generate-windows-icon.sh"; then
    echo -e "${GREEN}Windows: OK${NC}"
else
    echo -e "${RED}Windows: FAIL${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Web
echo -e "${BLUE}[5/6] Web иконки${NC}"
echo -e "${BLUE}------------------------------------------------${NC}"
if bash "$SCRIPT_DIR/generate-web-icons.sh"; then
    echo -e "${GREEN}Web: OK${NC}"
else
    echo -e "${RED}Web: FAIL${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Assets
echo -e "${BLUE}[6/6] Assets иконки${NC}"
echo -e "${BLUE}------------------------------------------------${NC}"
if bash "$SCRIPT_DIR/generate-assets-icons.sh"; then
    echo -e "${GREEN}Assets: OK${NC}"
else
    echo -e "${RED}Assets: FAIL${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Итоги
echo -e "${BLUE}================================================${NC}"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}Все платформы: OK (6/6)${NC}"
else
    echo -e "${RED}Завершено с ошибками: $FAILED из 6 не удалось${NC}"
    exit 1
fi
echo -e "${BLUE}================================================${NC}"
