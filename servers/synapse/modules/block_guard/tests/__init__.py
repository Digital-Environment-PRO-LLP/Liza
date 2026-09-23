"""Стаб synapse.api.errors для локального прогона без установленного Synapse.

`block_guard/__init__.py` импортирует `SynapseError` — это обязательно, иначе
отказ не доедет до клиента с нашим errcode. Но локально Synapse не установлен
(нет `matrix_common`), и по этой же причине СЕЙЧАС не собираются тесты
`channel_guard` — проверено: `pytest servers/synapse/modules/channel_guard/tests`
падает на импорте. Пакет тестов импортируется раньше самих тест-модулей, поэтому
стаб, поставленный здесь, чинит и `test_logic`, и `test_module`.

В контейнере (`/editable-src`) настоящий `synapse` импортируется первым, и
`sys.modules.setdefault` стаб НЕ подставляет — прод получает реальный
`SynapseError`.
"""

import sys
import types


def _install_synapse_stub() -> None:
    if "synapse.api.errors" in sys.modules:
        return
    try:  # настоящий Synapse доступен — стаб не нужен
        import synapse.api.errors  # noqa: F401
        return
    except Exception:
        # Неудачный импорт оставляет в sys.modules полуинициализированные
        # `synapse.*` — из-за них setdefault ниже вернул бы битый модуль,
        # и реальный `synapse/util/__init__.py` подхватился бы снова.
        for name in [n for n in sys.modules if n == "synapse" or n.startswith("synapse.")]:
            del sys.modules[name]

    class SynapseError(Exception):
        def __init__(self, code, msg, errcode="M_UNKNOWN", additional_fields=None):
            super().__init__(msg)
            self.code = code
            self.msg = msg
            self.errcode = errcode
            self.additional_fields = additional_fields or {}

    synapse_mod = sys.modules.setdefault("synapse", types.ModuleType("synapse"))
    api_mod = sys.modules.setdefault("synapse.api", types.ModuleType("synapse.api"))
    errors_mod = types.ModuleType("synapse.api.errors")
    errors_mod.SynapseError = SynapseError
    module_api_mod = types.ModuleType("synapse.module_api")
    module_api_mod.ModuleApi = object

    sys.modules["synapse.api.errors"] = errors_mod
    sys.modules["synapse.module_api"] = module_api_mod
    synapse_mod.api = api_mod
    api_mod.errors = errors_mod
    synapse_mod.module_api = module_api_mod


_install_synapse_stub()
