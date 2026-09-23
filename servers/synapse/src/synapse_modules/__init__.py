"""Namespace package that points to ../modules.

In production (Docker) `servers/synapse/modules/` is mounted into the container
as `/editable-src/synapse_modules`, so Python imports `synapse_modules.user_roles`
directly. For local test runs this package extends its search path to
`../modules` so the same import works without a Docker mount.
"""

from pathlib import Path

_modules_dir = Path(__file__).resolve().parent.parent.parent / "modules"
if _modules_dir.is_dir():
    __path__.append(str(_modules_dir))
