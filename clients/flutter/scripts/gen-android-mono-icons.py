#!/usr/bin/env python3
"""Монохромные Android-иконки Лизы из assets/logo_transparent.png.

Генерирует notifications_icon.png (smallIcon уведомлений) и
ic_launcher_monochrome.png (тематическая иконка Android 13+) во всех плотностях.
Android рисует такие значки только по альфе, поэтому цветной логотип сводится к
силуэту: волосы ∪ лицо, зазор между ними и прорези глаз/рта прозрачные.

Запуск из clients/flutter: python3 scripts/gen-android-mono-icons.py
Спека: docs/superpowers/specs/2026-09-24-android-notification-icon-liza-design.md
"""
import colorsys
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / 'android/app/src/main/res'
# Точка на подбородке: из неё заливкой выделяется лицо (белое внутри обводки),
# белая полоса между волосами и лицом отделена серой обводкой и в заливку не входит.
FACE_SEED = (283, 440)


def silhouette() -> Image.Image:
    src = Image.open(ROOT / 'assets/logo_transparent.png').convert('RGBA')
    w, h = src.size
    px = src.load()
    hair = Image.new('L', (w, h), 0)
    white = Image.new('L', (w, h), 0)
    hp, wp = hair.load(), white.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            _, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if s > 0.25 and v > 0.2:
                hp[x, y] = 255
            elif v > 0.85 and s < 0.15:
                wp[x, y] = 255
    face = Image.new('L', (w, h), 0)
    fp = face.load()
    fp[FACE_SEED] = 255
    queue = deque([FACE_SEED])
    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and fp[nx, ny] == 0 and wp[nx, ny] == 255:
                fp[nx, ny] = 255
                queue.append((nx, ny))
    hair = hair.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    # Зазор волосы/лицо шире, чем в логотипе, иначе на 24px он исчезает.
    hair = ImageChops.subtract(hair, face.filter(ImageFilter.MaxFilter(9)))
    sil = ImageChops.lighter(hair, face)
    sil = sil.crop(sil.getbbox())
    cw, ch = sil.size
    side = max(cw, ch)
    square = Image.new('L', (side, side), 0)
    square.paste(sil, ((side - cw) // 2, (side - ch) // 2))
    return square


def render(master: Image.Image, canvas: int, ratio: float, erode: int) -> Image.Image:
    # Эрозия утолщает прорези глаз/рта перед уменьшением — на mdpi/hdpi без неё
    # они схлопываются в пятно.
    m = master.filter(ImageFilter.MinFilter(erode)) if erode else master
    content = round(canvas * ratio)
    alpha = Image.new('L', (canvas, canvas), 0)
    offset = (canvas - content) // 2
    alpha.paste(m.resize((content, content), Image.LANCZOS), (offset, offset))
    out = Image.new('RGBA', (canvas, canvas), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def main() -> None:
    master = silhouette()
    densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    notif_erode = {'mdpi': 15, 'hdpi': 9, 'xhdpi': 5, 'xxhdpi': 0, 'xxxhdpi': 0}
    for name, k in densities.items():
        out_dir = RES / f'drawable-{name}'
        out_dir.mkdir(exist_ok=True)
        # Статус-бар: канвас 24dp, живая область 22dp.
        render(master, round(24 * k), 22 / 24, notif_erode[name]).save(
            out_dir / 'notifications_icon.png', optimize=True)
        # Слой адаптивной иконки: 108dp, логотип в safe-zone 66dp.
        render(master, round(108 * k), 0.45, 0).save(
            out_dir / 'ic_launcher_monochrome.png', optimize=True)


if __name__ == '__main__':
    main()
