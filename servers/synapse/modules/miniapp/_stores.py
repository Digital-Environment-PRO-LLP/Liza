"""In-memory хранилища nonce и rate-limit — чистые, без импорта Synapse/twisted.

Вынесено для unit-тестов. На multi-worker in-memory ломается (B4): nonce, выданный
одним процессом, невидим другому. Интерфейс узкий, чтобы заменить реализацию на
Redis/БД (атомарный GETDEL) без правки вызовов в `__init__.py`.
"""

from __future__ import annotations

import secrets
import time

_DEFAULT_NONCE_TTL = 30 * 60
_DEFAULT_RATE_MAX = 10
_DEFAULT_RATE_WINDOW = 60


class NonceStore:
    """Одноразовые nonce с TTL и привязкой к (user_id, app_id, room_id)."""

    def __init__(self, ttl: float = _DEFAULT_NONCE_TTL, clock=time.time) -> None:
        self._store: dict[str, tuple[str, str, str, float]] = {}
        self._ttl = ttl
        self._clock = clock

    def create(self, user_id: str, app_id: str, room_id: str | None) -> str:
        nonce = secrets.token_urlsafe(32)
        self._store[nonce] = (user_id, app_id, room_id or "", self._clock())
        return nonce

    def validate_and_consume(
        self, nonce: str, *, app_id: str | None = None, room_id: str | None = None
    ) -> bool:
        entry = self._store.pop(nonce, None)
        if entry is None:
            return False
        _user, bound_app, bound_room, created_at = entry
        if self._clock() - created_at > self._ttl:
            return False
        if app_id is not None and bound_app != app_id:
            return False
        if room_id is not None and bound_room != (room_id or ""):
            return False
        return True

    def cleanup(self) -> int:
        now = self._clock()
        expired = [k for k, v in self._store.items() if now - v[3] > self._ttl]
        for k in expired:
            del self._store[k]
        return len(expired)


class RateLimiter:
    """Скользящее окно на пользователя."""

    def __init__(
        self, max_requests: int = _DEFAULT_RATE_MAX, window: float = _DEFAULT_RATE_WINDOW, clock=time.time
    ) -> None:
        self._max = max_requests
        self._window = window
        self._clock = clock
        self._hits: dict[str, list[float]] = {}

    def check(self, user_id: str) -> bool:
        now = self._clock()
        cutoff = now - self._window
        hits = [t for t in self._hits.get(user_id, []) if t > cutoff]
        if len(hits) >= self._max:
            self._hits[user_id] = hits
            return False
        hits.append(now)
        self._hits[user_id] = hits
        return True
