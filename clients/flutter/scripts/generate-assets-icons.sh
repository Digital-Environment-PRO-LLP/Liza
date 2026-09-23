#!/bin/bash

# Скрипт для генерации иконок в /assets/ из исходной иконки 1024x1024
# Использует ImageMagick

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Путь к исходной иконке (1024x1024 из iOS)
SOURCE_ICON="ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"

# Целевая папка
ASSETS_DIR="assets"

echo -e "${GREEN}🎨 Генерация иконок для /assets/${NC}"
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

echo "📁 Исходная иконка: $SOURCE_ICON"
echo "📂 Целевая папка: $ASSETS_DIR"
echo ""

# ============================================
# Размеры файлов:
# - banner.png: 1000x400 (белый фон)
# - banner_transparent.png: 1000x400 (прозрачный фон)
# - favicon.png: 567x567 (прозрачный фон)
# - info-logo.png: 640x480 (прозрачный фон)
# - logo.png: 567x567 (белый фон)
# - logo_transparent.png: 567x567 (прозрачный фон)
# - logo.svg: viewBox 0 0 181.4 181.9 (белый фон)
# ============================================

# Функция для генерации квадратной иконки с прозрачным фоном
generate_transparent() {
    local size=$1
    local output_path=$2
    
    echo -e "  Генерация ${YELLOW}$(basename $output_path)${NC} (${size}x${size}, прозрачный фон)..."
    
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



# Функция для генерации баннера (иконка по центру)
generate_banner() {
    local width=$1
    local height=$2
    local output_path=$3
    local bg_color=$4  # "white" или "none"
    
    echo -e "  Генерация ${YELLOW}$(basename $output_path)${NC} (${width}x${height}, фон: $bg_color)..."
    
    # Размер иконки = высота баннера минус отступы
    local icon_size=$((height - 40))
    
    # Создаём временную иконку с прозрачными скруглёнными углами
    local temp_icon="/tmp/temp_icon_banner.png"
    local corner_radius=$((icon_size / 5))
    magick "$SOURCE_ICON" \
        -resize "${icon_size}x${icon_size}" \
        \( +clone -alpha extract \
           -fill black -colorize 100 \
           -fill white -draw "roundrectangle 0,0 $((icon_size-1)),$((icon_size-1)) ${corner_radius},${corner_radius}" \
        \) -alpha off -compose CopyOpacity -composite \
        "$temp_icon"
    
    # Создаём баннер с иконкой по центру
    if [ "$bg_color" = "white" ]; then
        magick -size "${width}x${height}" xc:white \
            "$temp_icon" -gravity center -composite \
            "$output_path"
    else
        magick -size "${width}x${height}" xc:none \
            "$temp_icon" -gravity center -composite \
            "$output_path"
    fi
    
    rm -f "$temp_icon"
    
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} $(basename $output_path) создан"
    else
        echo -e "  ${RED}✗${NC} Ошибка при создании $(basename $output_path)"
        return 1
    fi
}

# Функция для генерации info-logo (иконка по центру на прозрачном фоне)
generate_info_logo() {
    local width=$1
    local height=$2
    local output_path=$3
    
    echo -e "  Генерация ${YELLOW}$(basename $output_path)${NC} (${width}x${height}, прозрачный фон)..."
    
    # Размер иконки = меньшая сторона минус отступы
    local icon_size=$((height - 40))
    
    # Создаём временную иконку без фона
    local temp_icon="/tmp/temp_icon_info.png"
    magick "$SOURCE_ICON" \
        -resize "${icon_size}x${icon_size}" \
        -fuzz 5% -fill none -draw "color 0,0 floodfill" \
        "$temp_icon"
    
    # Создаём изображение с иконкой по центру
    magick -size "${width}x${height}" xc:none \
        "$temp_icon" -gravity center -composite \
        "$output_path"
    
    rm -f "$temp_icon"
    
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} $(basename $output_path) создан"
    else
        echo -e "  ${RED}✗${NC} Ошибка при создании $(basename $output_path)"
        return 1
    fi
}

# Функция для генерации SVG (трассировка PNG в векторный SVG)
generate_svg() {
    local output_path=$1
    
    echo -e "  Генерация ${YELLOW}$(basename $output_path)${NC} (SVG, векторная трассировка)..."
    
    # Проверяем наличие potrace для векторной трассировки
    if ! command -v potrace &> /dev/null; then
        echo -e "  ${YELLOW}⚠${NC} potrace не установлен, используем высококачественный PNG в SVG"
        echo "  Для лучшего качества установите: brew install potrace"
        
        # Fallback: высококачественный PNG встроенный в SVG
        local temp_png="/tmp/temp_logo_svg.png"
        magick "$SOURCE_ICON" \
            -resize "1024x1024" \
            -fuzz 5% -fill none -draw "color 0,0 floodfill" \
            "$temp_png"
        
        local base64_data=$(base64 -i "$temp_png")
        
        cat > "$output_path" << EOF
<?xml version="1.0" encoding="utf-8"?>
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" 
     viewBox="0 0 181.4 181.9" width="181.4" height="181.9">
  <image width="181.4" height="181.9" preserveAspectRatio="xMidYMid meet"
         xlink:href="data:image/png;base64,${base64_data}"/>
</svg>
EOF
        rm -f "$temp_png"
    else
        # Используем potrace для настоящей векторной трассировки
        local temp_png="/tmp/temp_logo_trace.png"
        local temp_pnm="/tmp/temp_logo_trace.pnm"
        local temp_svg="/tmp/temp_logo_trace.svg"
        
        # Подготавливаем изображение
        magick "$SOURCE_ICON" \
            -resize "1024x1024" \
            -fuzz 5% -fill none -draw "color 0,0 floodfill" \
            "$temp_png"
        
        # Конвертируем в PNM для potrace
        magick "$temp_png" "$temp_pnm"
        
        # Трассируем
        potrace -s -o "$temp_svg" "$temp_pnm"
        
        # Масштабируем viewBox
        sed -i '' 's/width="[^"]*"/width="181.4"/' "$temp_svg"
        sed -i '' 's/height="[^"]*"/height="181.9"/' "$temp_svg"
        
        cp "$temp_svg" "$output_path"
        rm -f "$temp_png" "$temp_pnm" "$temp_svg"
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} $(basename $output_path) создан"
    else
        echo -e "  ${RED}✗${NC} Ошибка при создании $(basename $output_path)"
        return 1
    fi
}

# ============================================
# Генерация файлов
# ============================================

echo "🔄 Генерация иконок..."
echo ""

# favicon.png: 567x567, прозрачный фон
generate_transparent 567 "$ASSETS_DIR/favicon.png"

# logo_transparent.png: 567x567, прозрачный фон
generate_transparent 567 "$ASSETS_DIR/logo_transparent.png"

# logo.png: 567x567, прозрачный фон (потом можно вручную добавить белый)
generate_transparent 567 "$ASSETS_DIR/logo.png"

# banner.png: 1000x400, прозрачный фон
generate_banner 1000 400 "$ASSETS_DIR/banner.png" "none"

# banner_transparent.png: 1000x400, прозрачный фон
generate_banner 1000 400 "$ASSETS_DIR/banner_transparent.png" "none"

# info-logo.png: 640x480, прозрачный фон
generate_info_logo 640 480 "$ASSETS_DIR/info-logo.png"

# logo.svg: viewBox 181.4x181.9, прозрачный фон
generate_svg "$ASSETS_DIR/logo.svg"

echo ""

# ============================================
# Проверка созданных файлов
# ============================================
echo "📊 Проверка созданных файлов:"
echo ""

check_file() {
    local file=$1
    local expected_w=$2
    local expected_h=$3
    
    if [ -f "$file" ]; then
        if [[ "$file" == *.svg ]]; then
            echo -e "  ${GREEN}✓${NC} $(basename $file) (SVG)"
        else
            local actual_w=$(sips -g pixelWidth "$file" | grep pixelWidth | awk '{print $2}')
            local actual_h=$(sips -g pixelHeight "$file" | grep pixelHeight | awk '{print $2}')
            if [ "$actual_w" = "$expected_w" ] && [ "$actual_h" = "$expected_h" ]; then
                echo -e "  ${GREEN}✓${NC} $(basename $file) (${actual_w}x${actual_h})"
            else
                echo -e "  ${YELLOW}⚠${NC} $(basename $file) (${actual_w}x${actual_h}, ожидалось ${expected_w}x${expected_h})"
            fi
        fi
    else
        echo -e "  ${RED}✗${NC} $(basename $file) отсутствует"
    fi
}

check_file "$ASSETS_DIR/favicon.png" 567 567
check_file "$ASSETS_DIR/logo.png" 567 567
check_file "$ASSETS_DIR/logo_transparent.png" 567 567
check_file "$ASSETS_DIR/banner.png" 1000 400
check_file "$ASSETS_DIR/banner_transparent.png" 1000 400
check_file "$ASSETS_DIR/info-logo.png" 640 480
check_file "$ASSETS_DIR/logo.svg" 0 0

echo ""
echo -e "${GREEN}✅ Готово! Иконки для /assets/ сгенерированы${NC}"
