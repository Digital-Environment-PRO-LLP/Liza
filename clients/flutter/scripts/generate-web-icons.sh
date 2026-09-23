#!/bin/bash

# Скрипт для генерации веб-иконок, favicon и splash из исходной иконки 1024x1024
# Использует ImageMagick для скруглённых углов и прозрачного фона

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Путь к исходной иконке (1024x1024 из iOS)
SOURCE_ICON="ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"

# Пути к целевым папкам
WEB_ICONS_DIR="web/icons"
WEB_SPLASH_DIR="web/splash/img"
WEB_ROOT="web"

echo -e "${GREEN}🎨 Генерация иконок для Web${NC}"
echo ""

# Проверка наличия ImageMagick
if ! command -v magick &> /dev/null; then
    echo -e "${RED}❌ ImageMagick не установлен${NC}"
    echo "Установите: brew install imagemagick"
    exit 1
fi

# Проверка наличия исходной иконки
if [ ! -f "$SOURCE_ICON" ]; then
    echo -e "${RED}❌ Ошибка: Исходная иконка не найдена: $SOURCE_ICON${NC}"
    echo "Убедитесь, что файл существует"
    exit 1
fi

# Проверка размера исходной иконки
ICON_SIZE=$(sips -g pixelWidth "$SOURCE_ICON" | grep pixelWidth | awk '{print $2}')
if [ "$ICON_SIZE" != "1024" ]; then
    echo -e "${YELLOW}⚠️  Предупреждение: Размер исходной иконки $ICON_SIZE x $ICON_SIZE${NC}"
    echo "Рекомендуется использовать иконку 1024x1024"
fi

# Создание папок если не существуют
mkdir -p "$WEB_ICONS_DIR"
mkdir -p "$WEB_SPLASH_DIR"

echo "📁 Исходная иконка: $SOURCE_ICON"
echo "📂 Целевые папки:"
echo "   - $WEB_ICONS_DIR"
echo "   - $WEB_SPLASH_DIR"
echo "   - $WEB_ROOT"
echo ""

# Функция для генерации иконки со скруглёнными углами
# Радиус скругления ~22.37% от размера иконки (как в macOS)
generate_rounded_icon() {
    local size=$1
    local output_path=$2
    local radius=$(echo "$size * 0.2237" | bc | cut -d. -f1)
    
    # Минимальный радиус 1 для маленьких иконок
    if [ "$radius" -lt 1 ]; then
        radius=1
    fi
    
    echo -e "  Генерация ${YELLOW}$(basename $output_path)${NC} (${size}x${size}, radius=${radius})..."
    
    # Масштабируем и применяем скруглённые углы
    magick "$SOURCE_ICON" \
        -resize "${size}x${size}" \
        \( +clone -alpha extract \
           -draw "fill black polygon 0,0 0,$radius $radius,0 fill white circle $radius,$radius $radius,0" \
           \( +clone -flip \) -compose Multiply -composite \
           \( +clone -flop \) -compose Multiply -composite \
        \) -alpha off -compose CopyOpacity -composite \
        "$output_path"
    
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} $(basename $output_path) создан"
    else
        echo -e "  ${RED}✗${NC} Ошибка при создании $(basename $output_path)"
        return 1
    fi
}

# Функция для генерации splash иконки (удаление чёрного фона)
# Splash иконки должны быть с прозрачным фоном
generate_splash_icon() {
    local size=$1
    local output_path=$2
    
    echo -e "  Генерация ${YELLOW}$(basename $output_path)${NC} (${size}x${size}, удаление фона)..."
    
    # Масштабируем и удаляем чёрный фон (делаем его прозрачным)
    # Используем floodfill от углов с небольшим fuzz
    magick "$SOURCE_ICON" \
        -resize "${size}x${size}" \
        -fuzz 5% -fill none -draw "color 0,0 floodfill" \
        "$output_path"
    
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} $(basename $output_path) создан"
    else
        echo -e "  ${RED}✗${NC} Ошибка при создании $(basename $output_path)"
        return 1
    fi
}

# ============================================
# Генерация иконок для web/icons (со скруглением)
# ============================================
echo "🔄 Генерация иконок для web/icons (со скруглёнными углами)..."
echo ""

generate_rounded_icon 192 "$WEB_ICONS_DIR/Icon-192.png"
generate_rounded_icon 512 "$WEB_ICONS_DIR/Icon-512.png"

echo ""

# ============================================
# Генерация favicon (со скруглением)
# ============================================
echo "🔄 Генерация favicon..."
echo ""

generate_rounded_icon 32 "$WEB_ROOT/favicon.png"

echo ""

# ============================================
# Генерация splash screen иконок (прозрачный фон)
# Размеры: 1x=177, 2x=354, 3x=531, 4x=709
# ============================================
echo "🔄 Генерация splash screen иконок (прозрачный фон)..."
echo ""

# Light версии
generate_splash_icon 177 "$WEB_SPLASH_DIR/light-1x.png"
generate_splash_icon 354 "$WEB_SPLASH_DIR/light-2x.png"
generate_splash_icon 531 "$WEB_SPLASH_DIR/light-3x.png"
generate_splash_icon 709 "$WEB_SPLASH_DIR/light-4x.png"

# Dark версии (те же иконки, можно использовать одинаковые или разные)
generate_splash_icon 177 "$WEB_SPLASH_DIR/dark-1x.png"
generate_splash_icon 354 "$WEB_SPLASH_DIR/dark-2x.png"
generate_splash_icon 531 "$WEB_SPLASH_DIR/dark-3x.png"
generate_splash_icon 709 "$WEB_SPLASH_DIR/dark-4x.png"

echo ""

# ============================================
# Проверка созданных файлов
# ============================================
echo "📊 Проверка созданных файлов:"
echo ""

echo "web/icons:"
for size in 192 512; do
    file="$WEB_ICONS_DIR/Icon-${size}.png"
    if [ -f "$file" ]; then
        actual_size=$(sips -g pixelWidth "$file" | grep pixelWidth | awk '{print $2}')
        echo -e "  ${GREEN}✓${NC} Icon-${size}.png (${actual_size}x${actual_size})"
    else
        echo -e "  ${RED}✗${NC} Icon-${size}.png отсутствует"
    fi
done

echo ""
echo "web/ (favicon):"
if [ -f "$WEB_ROOT/favicon.png" ]; then
    actual_size=$(sips -g pixelWidth "$WEB_ROOT/favicon.png" | grep pixelWidth | awk '{print $2}')
    echo -e "  ${GREEN}✓${NC} favicon.png (${actual_size}x${actual_size})"
else
    echo -e "  ${RED}✗${NC} favicon.png отсутствует"
fi

echo ""
echo "web/splash/img:"
for variant in light dark; do
    for scale in 1 2 3 4; do
        file="$WEB_SPLASH_DIR/${variant}-${scale}x.png"
        if [ -f "$file" ]; then
            actual_size=$(sips -g pixelWidth "$file" | grep pixelWidth | awk '{print $2}')
            echo -e "  ${GREEN}✓${NC} ${variant}-${scale}x.png (${actual_size}x${actual_size})"
        else
            echo -e "  ${RED}✗${NC} ${variant}-${scale}x.png отсутствует"
        fi
    done
done

echo ""
echo -e "${GREEN}✅ Готово! Веб-иконки сгенерированы${NC}"
echo ""
echo "Следующие шаги:"
echo "1. Проверьте иконки в папках web/icons и web/splash/img"
echo "2. Соберите веб-версию: flutter build web --release"
echo "3. Или используйте: ./scripts/prepare-web.sh"
