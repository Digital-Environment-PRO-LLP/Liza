"""FFprobe-анализ видео при upload.

Запускает ffprobe как subprocess, возвращает метаданные (bitrate, codec,
resolution, fps) для вставки в upload response как `com.liza.media_profile`.
Клиент Liza использует эти данные для выбора оптимального качества стриминга.
"""

import asyncio
import json
import logging
from typing import Any

logger = logging.getLogger(__name__)


async def extract_video_metadata(file_path: str) -> dict[str, Any]:
    """Запустить ffprobe, вернуть метаданные видео.

    Не блокирует event loop: subprocess запускается через asyncio.
    Timeout 30 сек — не должен блокировать upload.
    """
    try:
        proc = await asyncio.create_subprocess_exec(
            "ffprobe",
            "-v", "error",
            "-show_entries",
            "format=duration,bit_rate"
            ":stream=width,height,codec_name,codec_type,r_frame_rate,"
            "bit_rate,color_transfer",
            "-of", "json",
            file_path,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=30.0,
        )

        if proc.returncode != 0:
            logger.warning("FFprobe failed (rc=%d): %s", proc.returncode, stderr.decode())
            return {}

        data = json.loads(stdout.decode())

        video_stream = next(
            (s for s in data.get("streams", []) if s.get("codec_type") == "video"),
            None,
        )
        fmt = data.get("format", {})

        result: dict[str, Any] = {}
        if video_stream:
            result["width"] = video_stream.get("width")
            result["height"] = video_stream.get("height")
            result["codec"] = video_stream.get("codec_name")
            # fps из дробного формата "30000/1001"
            r_frame_rate = video_stream.get("r_frame_rate")
            if r_frame_rate and "/" in r_frame_rate:
                try:
                    num, den = r_frame_rate.split("/")
                    result["fps"] = round(int(num) / int(den), 2)
                except (ValueError, ZeroDivisionError):
                    pass
            # HDR detection
            color_transfer = video_stream.get("color_transfer", "")
            result["is_hdr"] = color_transfer in ("smpte2084", "arib-std-b67")

        if fmt.get("duration"):
            result["duration_secs"] = float(fmt["duration"])
        if fmt.get("bit_rate"):
            result["bitrate_bps"] = int(fmt["bit_rate"])

        # Рекомендуемые профили качества для транскодинга
        w = result.get("width")
        h = result.get("height")
        bitrate = result.get("bitrate_bps")
        if w and h and bitrate:
            result["recommended_qualities"] = _calc_qualities(w, h, bitrate)
            result["should_transcode"] = _should_transcode(
                w, h, bitrate,
                result.get("codec", ""),
                result.get("is_hdr", False),
            )

        return result

    except asyncio.TimeoutError:
        logger.warning("FFprobe timeout for %s", file_path)
        return {}
    except Exception:
        logger.exception("FFprobe error")
        return {}


def _calc_qualities(w: int, h: int, bitrate_bps: int) -> list[dict[str, Any]]:
    """Рассчитать профили качества с минимальной пропускной способностью."""
    profiles = []
    presets = [
        ("720p", 1280, 720, 2_500_000),
        ("480p", 854, 480, 1_000_000),
        ("360p", 640, 360, 500_000),
        ("240p", 426, 240, 250_000),
    ]
    for name, pw, ph, target_br in presets:
        if w > pw or h > ph:
            profiles.append({
                "quality": name,
                "target_bitrate_bps": target_br,
                "min_bandwidth_bps": int(target_br * 1.5),
            })
    return profiles


def _should_transcode(
    w: int, h: int, bitrate_bps: int, codec: str, is_hdr: bool,
) -> list[str]:
    """Определить, какие варианты качества нужно генерировать.

    Не транскодировать если:
    - HDR (tone-mapping на CPU слишком дорог)
    - Уже <= 480p
    - Уже <= 720p И bitrate <= 3 Mbps (сжато мобильным клиентом)
    - HEVC <= 1280px (лучше не конвертировать в H.264)
    """
    if is_hdr:
        return []
    if w <= 854 and h <= 480:
        return []
    if w <= 1280 and h <= 720 and bitrate_bps <= 3_000_000:
        return ["480p"]
    if codec == "hevc" and w <= 1280:
        return ["480p"]
    return ["720p", "480p"]
