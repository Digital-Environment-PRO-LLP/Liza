# Liza

This repository contains the source code of
the Liza components that are derived from software licensed under the
**GNU Affero General Public License v3.0** (AGPL-3.0), as required by that
licence (§13, "Remote Network Interaction").

## Components

| Path | Component | Upstream | Licence |
|---|---|---|---|
| `clients/flutter/` | Liza client (iOS, Android, macOS, Windows, Linux, Web) | [FluffyChat](https://github.com/krille-chan/fluffychat) | AGPL-3.0 |
| `servers/synapse/src/` | Liza homeserver | [Synapse](https://github.com/element-hq/synapse) | AGPL-3.0 |
| `servers/synapse/modules/` | Synapse modules running inside the Liza homeserver | — | AGPL-3.0 |
| `servers/sygnal/` | Liza push gateway | [Sygnal](https://github.com/matrix-org/sygnal) | AGPL-3.0 |

Bundled third-party packages keep their own licences (for example
`clients/flutter/packages/swipe_to_action` — MIT).

## Licence

See [LICENSE](LICENSE) and [NOTICE](NOTICE).
