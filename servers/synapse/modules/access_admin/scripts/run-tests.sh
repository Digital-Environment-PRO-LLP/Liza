#!/usr/bin/env bash
# Прогон юнит-тестов access_admin без установленного Synapse.
# Пакет access_admin/__init__.py импортирует synapse.* — подкладываем
# минимальный stub, а modules/ монтируем под именем synapse_modules
# (как в docker-compose: ../servers/synapse/modules:/editable-src/synapse_modules).
set -euo pipefail
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)}"
BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT
mkdir -p "$BASE/pyroot" "$BASE/stub/synapse/module_api" "$BASE/stub/synapse/api" \
         "$BASE/stub/synapse/types" "$BASE/stub/synapse/logging"
ln -sfn "$REPO/servers/synapse/modules" "$BASE/pyroot/synapse_modules"
touch "$BASE/stub/synapse/__init__.py" "$BASE/stub/synapse/api/__init__.py" \
      "$BASE/stub/synapse/logging/__init__.py"
cat > "$BASE/stub/synapse/module_api/__init__.py" <<'EOF'
class ModuleApi: ...
class AccountDataManager: ...
EOF
cat > "$BASE/stub/synapse/api/errors.py" <<'EOF'
class AuthError(Exception):
    def __init__(self, code=401, msg=""): super().__init__(msg); self.code = code
class SynapseError(Exception):
    def __init__(self, code=400, msg="", errcode="M_UNKNOWN"):
        super().__init__(msg); self.code = code; self.errcode = errcode
EOF
cat > "$BASE/stub/synapse/types/__init__.py" <<'EOF'
class UserID:
    def __init__(self, localpart, domain): self.localpart = localpart; self.domain = domain
    @staticmethod
    def from_string(s):
        lp, _, dom = s[1:].partition(":"); return UserID(lp, dom)
    def to_string(self): return f"@{self.localpart}:{self.domain}"
EOF
cat > "$BASE/stub/synapse/logging/context.py" <<'EOF'
def run_in_background(f, *a, **kw): return f(*a, **kw)
def make_deferred_yieldable(d): return d
EOF
cd "$REPO/servers/synapse/modules"
PYTHONPATH="$BASE/pyroot:$BASE/stub" exec python3 -m pytest access_admin/tests/ "$@"
