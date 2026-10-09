# Assistant Link for Apple platforms

The [Assistant Link](https://github.com/assistant-link/assistant-link) iPhone app (SwiftUI, iOS 18+). macOS and
watchOS apps will live here too, as more targets in the same project. The Xcode project is generated
from `project.yml` with XcodeGen; `AssistantLink.xcodeproj` is git-ignored, so never
edit it by hand. Everything runs from the command line through `make`.

## Prerequisites

- macOS with Xcode 16 or later (Swift 6, iOS 18+ SDK; tested with Xcode 26.6), with
  an iOS 18 or later Simulator runtime (Xcode > Settings > Components, or
  `xcodebuild -downloadPlatform iOS`).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `mise install` installs the version pinned in `mise.toml`
  ([mise](https://mise.jdx.dev)), or `brew install xcodegen`.
- `jq` (preinstalled on macOS 15 and later).

The Makefile uses `/Applications/Xcode.app` automatically when `xcode-select` points at
the Command Line Tools. To use a different Xcode, run
`sudo xcode-select -s /path/to/Xcode.app` or set `DEVELOPER_DIR`.

## Make targets

Run these from the repository root:

| Target          | What it does                                                        |
| --------------- | ------------------------------------------------------------------- |
| `make generate` | Generate `AssistantLink.xcodeproj` from `project.yml`.              |
| `make build`    | Build the app for the Simulator into `build/`.                      |
| `make test`     | Run the unit tests (Swift Testing) on the Simulator.                |
| `make run`      | Build, boot the Simulator, install and launch Assistant Link.       |
| `make device`   | Build, sign, install and launch on a paired iPhone.                 |
| `make lint`     | Check Swift style with `swift format` and `.swift-format`.          |
| `make format`   | Reformat Swift sources in place with `swift format`.                |
| `make clean`    | Remove `build/` and the generated Xcode project.                    |

`build`, `test` and `run` generate the project first if it is missing or older than
`project.yml`. Run `make generate` yourself after adding or removing source files.

Add `XCODEBUILD_FLAGS=` to see full `xcodebuild` output, for example
`make build XCODEBUILD_FLAGS=`.

## Running in the Simulator

```sh
make run
```

This picks an available iPhone Simulator (a booted one first, otherwise one on the newest
iOS runtime), boots it, opens the Simulator app, and launches Assistant Link. To pick
the device yourself, pass its name or UDID:

```sh
make run SIMULATOR="iPhone 17"
```

`SIMULATOR=` works the same way for `make build` and `make test`. List devices with
`xcrun simctl list devices available`.

## Which service the app uses

Every build talks to the production service, `https://assistant-link.fly.dev`, unless you
override it. On first launch the app registers an anonymous account there and keeps its
credential in the Keychain, so the account survives reinstalls of the app on that
device or Simulator.

Debug builds accept a `-serviceURL` launch argument to use another service, such as a
local one for offline work. Start the service (see the
[backend README](https://github.com/assistant-link/backend#readme)), then run:

```sh
make run SERVICE_URL=http://localhost:4000
```

The override lasts only for that launch: opening the app from the home screen goes back
to production. The app keeps one credential per service URL, so the local service and
production each get their own account, and neither ever receives the other's credential.
Release builds ignore the argument.

## Running on a physical iPhone

`make device` needs a one-time setup (Xcode account, Developer Mode on the iPhone, and your
team ID in a git-ignored `Local.mk`). See [docs/physical-device.md](docs/physical-device.md).

## Opening in Xcode

To open the project in Xcode instead, run `make generate`, then
`open AssistantLink.xcodeproj`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The code is licensed under the [MIT License](LICENSE).

## Name and icon

The Assistant Link name and app icon are trademarks of Engineering Freedom Ltd and are not covered by the MIT License.
If you publish a build of your own, give it a different name and icon, and a bundle ID of your own. See
[TRADEMARK.md](https://github.com/assistant-link/assistant-link/blob/main/TRADEMARK.md).
