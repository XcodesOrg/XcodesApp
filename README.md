# Rhodon Fork

> Work in progress. Maintained fork. Vibe-coded with intent.

This repository is an actively maintained fork of Rhodon, a macOS app for
installing, managing, and switching between multiple versions of Xcode.

The original project this fork came from is no longer maintained in the way this
fork needs it to be. This repository exists to keep the app useful, modern, and
working for current Apple developer tooling.

## Current Status

This fork is WIP.

Expect rough edges, unfinished work, and occasional breakage. The goal is not to
pretend this is a pristine long-term-maintenance branch. The goal is to keep the
tool moving, make practical improvements, and fix the things that matter for
day-to-day use.

This fork is also intentionally vibe-coded. That means development is pragmatic,
fast-moving, and assisted by AI. Changes may start from experiments, sketches, or
direct problem solving rather than a traditional roadmap process. The standard is
still that the result should be understandable, reviewable, and useful.

## What Rhodon Does

Rhodon helps macOS developers:

- Browse available Xcode releases.
- Download and install selected Xcode versions.
- Switch the active Xcode with `xcode-select`.
- View release metadata such as compatibility, SDKs, and compilers.
- Install Apple platform runtimes where supported.
- Work with Apple Silicon and Universal Xcode/runtime variants where available.
- Use faster downloads through a system-installed `aria2c` when configured.

Some features depend on Apple services, Apple Developer account behavior, and
Apple's current download infrastructure. Those parts can change without warning.

## Fork Goals

- Keep Rhodon usable on current macOS and Xcode versions.
- Remove or repair stale assumptions from the old codebase.
- Improve support for modern Xcode, runtimes, and Apple Silicon variants.
- Keep the app practical rather than perfect.
- Make maintenance transparent, including the parts that are experimental.

## Non-Goals

- This is not an official Apple tool.
- This is not a polished commercial product.
- This fork does not promise compatibility with every historical Xcode version.
- This fork does not guarantee that Apple account sign-in or download flows will
  always work, because Apple can change those flows at any time.

## Installation

There may not always be a signed, notarized, or generally recommended release
build available from this fork.

For now, treat this repository primarily as a source build unless a release is
explicitly published by this fork's maintainer.

If you need a stable production setup, verify the current state of releases,
signing, notarization, and update behavior before relying on this app.

## Development

Requirements:

- macOS 15 or newer.
- A recent Xcode version capable of opening and building this project.
- Optional: `aria2c` for faster downloads.

Open the project in Xcode:

```sh
open Rhodon.xcodeproj
```

Optional faster-download dependency:

```sh
brew install aria2
```

The main app target is `Rhodon`. The repository also contains supporting Swift
packages and helper code:

- `AppleAPI`
- `RhodonKit`
- `Sources/PrivilegedHelper`
- `Sources/HelperXPCShared`

## Safety Notes

This app interacts with developer tooling, installed Xcode bundles, privileged
helper code, and Apple downloads. Review changes before running a build you do
not trust.

If you are testing changes that affect the privileged helper, Xcode selection,
runtime installation, or app signing, use a machine where you are comfortable
debugging developer-tool state.

## Contributing

Contributions are welcome, but this fork is currently maintainer-led and WIP.

Good contributions are small, practical, and easy to review. Bug reports should
include:

- macOS version.
- Xcode version.
- App version or commit.
- Clear reproduction steps.
- Relevant logs or screenshots.

AI-assisted contributions are fine. Please make sure generated code is reviewed,
buildable, and explained well enough for a maintainer to reason about it.

## Relationship to the Original Project

This is a fork of Rhodon. Credit remains due to the original authors and
contributors who built the foundation of the app.

This fork has its own maintenance status, priorities, and direction. Do not
assume issues, releases, support expectations, or update channels from the
original project apply here.

## License

This project remains under the license provided in this repository. See
[`LICENSE`](LICENSE).
