#!/bin/bash

# Скрипт для генерации иконок macOS из исходной иконки 1024x1024
# Использует ImageMagick для скруглённых углов в стиле macOS

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Путь к исходной иконке (1024x1024 из iOS)
SOURCE_ICON="ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"

# Путь к папке с иконками macOS
MACOS_ICON_DIR="macos/Runner/Assets.xcassets/AppIcon.appiconset"

echo -e "${GREEN}🎨 Генерация иконок для macOS${NC}"
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

# Создание папки если не существует
mkdir -p "$MACOS_ICON_DIR"

echo "📁 Исходная иконка: $SOURCE_ICON"
echo "📂 Целевая папка: $MACOS_ICON_DIR"
echo ""

# Функция для генерации иконки со скруглёнными углами macOS
# Apple HIG: контент ~80.5% холста (padding ~9.6% с каждой стороны)
# Радиус скругления для macOS squircle ~22.37% от размера контента
generate_icon() {
    local size=$1
    local output_name=$2
    
    # Размер контента ~80.5% от холста (9.6% padding с каждой стороны по Apple HIG)
    local content_size=$(echo "$size * 1" | bc | cut -d. -f1)
    local radius=$(echo "$content_size * 0.2237" | bc | cut -d. -f1)
    
    # Минимальный радиус 1 для маленьких иконок
    if [ "$radius" -lt 1 ]; then
        radius=1
    fi
    
    echo -e "  Генерация ${YELLOW}${output_name}${NC} (${size}x${size}, content=${content_size}x${content_size}, radius=${radius})..."
    
    # Пошагово: resize → маска → CopyOpacity → padding
    local max_xy=$((content_size - 1))
    local tmp_resized="/tmp/macos_icon_resized.png"
    local tmp_mask="/tmp/macos_icon_mask.png"
    local tmp_masked="/tmp/macos_icon_masked.png"

    # 1. Масштабируем исходную иконку
    magick "$SOURCE_ICON" -resize "${content_size}x${content_size}" "$tmp_resized"

    # 2. Создаём чёрно-белую маску со скруглёнными углами
    magick -size "${content_size}x${content_size}" xc:black \
        -fill white -draw "roundrectangle 0,0 ${max_xy},${max_xy} ${radius},${radius}" \
        "$tmp_mask"

    # 3. Применяем маску как альфа-канал (сохраняет цвета)
    magick "$tmp_resized" "$tmp_mask" -alpha off -compose CopyOpacity -composite "$tmp_masked"

    # 4. Центрируем на прозрачном холсте с padding
    magick "$tmp_masked" -gravity center -background none -extent "${size}x${size}" \
        "$MACOS_ICON_DIR/$output_name"

    rm -f "$tmp_resized" "$tmp_mask" "$tmp_masked"
    
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} $output_name создан"
    else
        echo -e "  ${RED}✗${NC} Ошибка при создании $output_name"
        return 1
    fi
}

# Генерация всех необходимых размеров для macOS
echo "🔄 Генерация иконок..."
echo ""

generate_icon 16 "16-mac.png"
generate_icon 32 "32-mac.png"
generate_icon 64 "64-mac.png"
generate_icon 128 "128-mac.png"
generate_icon 256 "256-mac.png"
generate_icon 512 "512-mac.png"
generate_icon 1024 "1024-mac.png"

echo ""

# Создание правильного Contents.json
echo "📝 Создание Contents.json..."

cat > "$MACOS_ICON_DIR/Contents.json" << 'EOF'
{
  "images" : [
    {
      "filename" : "16-mac.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "32-mac.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "32-mac.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "64-mac.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "128-mac.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "256-mac.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "256-mac.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "512-mac.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "512-mac.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "1024-mac.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo -e "${GREEN}✓${NC} Contents.json создан"
echo ""

# Проверка созданных файлов
echo "📊 Проверка созданных файлов:"
echo ""

for size in 16 32 64 128 256 512 1024; do
    file="$MACOS_ICON_DIR/${size}-mac.png"
    if [ -f "$file" ]; then
        actual_size=$(sips -g pixelWidth "$file" | grep pixelWidth | awk '{print $2}')
        echo -e "  ${GREEN}✓${NC} ${size}-mac.png (${actual_size}x${actual_size})"
    else
        echo -e "  ${RED}✗${NC} ${size}-mac.png отсутствует"
    fi
done

echo ""
echo -e "${GREEN}✅ Готово! Иконки для macOS сгенерированы${NC}"
echo ""
echo "Следующие шаги:"
echo "1. Откройте проект в Xcode: open macos/Runner.xcworkspace"
echo "2. Проверьте иконки в Assets.xcassets"
echo "3. Соберите проект: flutter build macos --release"
