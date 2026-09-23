"""Демо: подпись initData (как Synapse-модуль) + офлайн-проверка (как бэкенд app).

Показывает §3 (Ed25519 third-party validation) и HMAC БЕЗ поднятия Synapse:
1. «модуль» подписывает initData (HMAC per-app key + Ed25519);
2. «сторонний бэкенд» проверяет подпись Ed25519, зная ТОЛЬКО публичный ключ
   (не зная master_secret) — и ловит подделку.

Запуск (нужен только пакет cryptography):
    python servers/synapse/modules/miniapp/demo_initdata.py
"""

from __future__ import annotations

import base64
import json
import sys
import time
from pathlib import Path

# Импортируем чистое крипто-ядро напрямую (без пакета, тянущего twisted).
sys.path.insert(0, str(Path(__file__).resolve().parent))
import _crypto  # noqa: E402

MASTER = "demo-master-secret"          # секрет «как в MINIAPP_SECRET»
ED_SEED = bytes(range(32))             # seed Ed25519 (в проде — в secrets/)
APP_ID = "demo-shop"
USER_ID = "@alice:dev.liza.laba.prodamus.tech"


def sign_like_module() -> str:
    """Эмуляция _build_init_data модуля: HMAC per-app + Ed25519."""
    key = _crypto.signing_key(MASTER, APP_ID, per_app_keys=True)
    user_hash = _crypto.compute_user_hash(key, USER_ID)
    params = {
        "app_id": APP_ID,
        "auth_date": str(int(time.time())),
        "nonce": "demo-nonce",
        "user": json.dumps({"id": user_hash, "display_name": "Alice"}, ensure_ascii=False),
        "key_id": "1",
    }
    dcs = _crypto.build_data_check_string(params)
    h = _crypto.hmac_sign(key, dcs)
    sig = _crypto.ed25519_sign_b64url(ED_SEED, dcs)
    return _crypto.encode_init_data(params, h, sig)


def verify_like_third_party(init_data: str, public_key_b64url: str, expected_app: str) -> dict:
    """Эмуляция бэкенда стороннего app: проверка Ed25519 офлайн, без секрета."""
    from urllib.parse import parse_qsl

    parsed = dict(parse_qsl(init_data, keep_blank_values=True))
    sig = parsed.pop("signature")
    parsed.pop("hash", None)
    dcs = _crypto.build_data_check_string(parsed)

    pad = "=" * (-len(public_key_b64url) % 4)
    pub = base64.urlsafe_b64decode(public_key_b64url + pad)
    if not _crypto.ed25519_verify_b64url(pub, dcs, sig):
        raise ValueError("подпись Ed25519 невалидна")
    if parsed.get("app_id") != expected_app:
        raise ValueError("app_id не совпадает")
    if time.time() - int(parsed["auth_date"]) > 300:
        raise ValueError("initData протух (>5 мин)")
    return json.loads(parsed["user"])


def main() -> None:
    pub = _crypto.ed25519_public_key_b64url(ED_SEED)
    print("Публичный Ed25519-ключ (его модуль публикует в /keys и .well-known):")
    print("  ", pub, "\n")

    init_data = sign_like_module()
    print("initData (подписана модулем):")
    print("  ", init_data, "\n")

    print("=> Сторонний бэкенд проверяет, зная ТОЛЬКО публичный ключ:")
    user = verify_like_third_party(init_data, pub, APP_ID)
    print("   OK, user:", user)
    print("   (реальный MXID НЕ виден — только opaque user_hash)\n")

    print("=> Подделка: меняем app_id в initData →")
    tampered = init_data.replace("app_id=demo-shop", "app_id=evil-app", 1)
    try:
        verify_like_third_party(tampered, pub, APP_ID)
        print("   ОШИБКА: подделка прошла (так быть НЕ должно)")
    except ValueError as e:
        print("   отклонено, как и ожидалось:", e)


if __name__ == "__main__":
    main()
