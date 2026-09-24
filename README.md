# Liza

Liza is a Matrix-based messenger. This repository contains the source code of
the Liza components that are derived from software licensed under the
**GNU Affero General Public License v3.0** (AGPL-3.0), as required by that
licence (§13, "Remote Network Interaction").

> This repository is an **automated daily export** of the relevant part of the
> internal Liza monorepo. Every commit is a snapshot named after the internal
> revision it was built from. Pull requests are not merged here; please open an
> issue instead.

## Components

| Path | Component | Upstream | Licence |
|---|---|---|---|
| `clients/flutter/` | Liza client (iOS, Android, macOS, Windows, Linux, Web) | [FluffyChat](https://github.com/krille-chan/fluffychat) | AGPL-3.0 |
| `servers/synapse/src/` | Liza homeserver | [Synapse](https://github.com/element-hq/synapse) | AGPL-3.0 |
| `servers/synapse/modules/` | Synapse modules running inside the Liza homeserver | — | AGPL-3.0 |
| `servers/sygnal/` | Liza push gateway | [Sygnal](https://github.com/matrix-org/sygnal) | AGPL-3.0 |

Bundled third-party packages keep their own licences (for example
`clients/flutter/packages/swipe_to_action` — MIT).

## What is not included

Deployment configuration, environment files, signing material, store metadata
and configuration files of the upstream projects (YAML, JSON, plist, etc.) are
intentionally not published. Package manifests (`pubspec.yaml`,
`pyproject.toml`, `Cargo.toml`) are kept so that dependencies are visible.
Values that bind the client to our Firebase project are replaced with
placeholders. To build and run the components, take the missing configuration
from the corresponding upstream project and provide your own values.

Services of the Liza platform that are not derived from AGPL-licensed software
and interact with the homeserver only over the network are not part of this
repository.

## Licence

See [LICENSE](LICENSE) and [NOTICE](NOTICE).
