<h1><img src="icon.png" align="center" width=50 height=50 /> <img src="IconDark.png" align="center" width=50 height=50 /> <img src="IconMono.png" align="center" width=50 height=50 /> Xcodes.app</h1>

The easiest way to install and switch between multiple versions of Xcode.

_If you're looking for a command-line version of Xcodes.app, try [`xcodes`](https://github.com/XcodesOrg/xcodes)._

![CI](https://github.com/XcodesOrg/XcodesApp/workflows/CI/badge.svg)

![](screenshot_light.png#gh-light-mode-only)
![](screenshot_dark.png#gh-dark-mode-only)

### :tada: Announcement

XcodesApp is now part of the `XcodesOrg` - [read more here](nextstep.md)

## Features

- List all available Xcode versions from [Xcode Releases'](https://xcodereleases.com) data or the Apple Developer website.
- Install any Xcode version, **fully automated** from start to finish. Xcodes uses [`aria2`](https://aria2.github.io), which uses up to 16 connections to download 3-5x faster than URLSession.
- Automatically resumes installs if network errors.
- Apple ID required to download Xcode versions.
- Just click a button to make a version active with `xcode-select`.
- View release notes, OS compatibility, included SDKs and compilers from [Xcode Releases](https://xcodereleases.com).
- Dark/Light Mode supported
- Security Key Authentication supported 
- Support installing Platforms/Runtimes
- Support installing Apple Silicon variants
- Review and clean developer storage in a separate Clean Up window.

Xcodes can install Apple’s `.aea` archives on macOS versions with `archiveutil extractXcodeAEA`. If Xcode Releases has an outdated download link, try the Apple Developer data source in Settings.

## Clean Up

Clean Up helps you review developer files, caches, and simulator storage. Open it from the bottom-left **Clean Up** button or the app menu. Nothing is selected or deleted automatically.

Xcodes scans on launch. The previous results appear immediately while a background scan refreshes them; the spinner shows when it is running. The window shows the last scan time and identifies cached results. Its **Available to clean up** estimate matches the bottom bar; **Total scanned** also includes incomplete and externally managed storage.

### Default folders

`~` means your home folder. Custom DerivedData and Xcodes storage paths are respected.

| Category | Location |
|---|---|
| Xcode build files | `~/Library/Developer/Xcode/DerivedData` |
| Archives | `~/Library/Developer/Xcode/Archives` |
| Device support | `~/Library/Developer/Xcode/iOS DeviceSupport` |
| Simulator devices | `~/Library/Developer/CoreSimulator/Devices` |
| Simulator runtimes | `/Library/Developer/CoreSimulator` (inventoried through `simctl`) |
| Xcodes downloads | Your configured Xcodes storage folder |

### Your folders

Use **Folders…** or **Settings → Cleanup** to add or remove scan locations. Suggestions include Downloads, device backups, app caches (`~/Library/Caches`), Trash, npm, Cargo, Gradle, and Docker storage; **Choose Folder…** adds any other folder. Removing a location only excludes it from scanning. Removed defaults can be restored through **Add Folder → Developer Folders**.

Added folders default to **1 level**: list immediate entries without opening child folders. Increase **Scan depth**, or choose **Unlimited**, for complete folder sizes. Developer locations scan fully. Recognized `node_modules` folders are also listed. Unreadable or depth-limited folders show unavailable or partial sizes. Protected locations may need Full Disk Access for the running copy of Xcodes, followed by a restart or rescan.

Folder settings are saved in `cleanup-folders.json` beside the Xcode and runtime lists in your configured Xcodes storage directory (normally `~/Library/Application Support/com.robotsandpencils.XcodesApp`). The readable JSON includes `developerFolders` category IDs, added `folders` with absolute `path` values, and `scanDepth` (`0` means unlimited). Edit it outside Xcodes, then restart or click **Rescan** to reload. IDs and names for added folders are optional. Existing preferences migrate automatically; invalid JSON is reported without overwriting it.

### Cleaning

Cleanup shows the current item and batch progress in the window and bottom bar. Closing the cleanup window keeps it running while Xcodes stays open. **Stop after current item** leaves remaining items untouched. Failures remain available for review.

- Select categories or individual rows. Use the OS filter to find older simulator, runtime, and device-support versions; changing the filter clears selections.
- Ordinary files move to Trash after confirmation. Space is reclaimed when Trash is emptied in Finder; Xcodes does not empty it.
- Shut-down simulator devices and eligible runtimes are removed through `simctl`. This permanently removes device data or uninstalls the runtime. Xcode associations are shown during confirmation.
- Docker, backups, and existing Trash are review/manage-only. Active tools, Xcodes operations, and changed targets can block cleanup; failures are reported individually.

Successful cleanup updates the results and persisted amount without rescanning. Use **Rescan** for changes made outside Xcodes. Changing folders or depth invalidates the cache.

## Platforms/Runtimes

- Xcodes supports downloading the Apple runtimes via the app. Simply click on the Platform, and Xcodes will install automatically for you.
- Platforms are listed in the order iOS, watchOS, visionOS, tvOS, with the newest version first.
- Remove installed runtimes from **Clean Up** or with **Uninstall** in an Xcode’s Platforms list.
- When uninstalling an Xcode, choose **Uninstall with Platforms** to also remove the simulator platforms that only that Xcode uses. Platforms that another installed Xcode still uses are never offered for removal.

**Note: iOS 18+, tvOS 18+, watchOS 11+, visionOS 2+ requires that Xcode 16.1 Beta 3+ be installed and active.** 

## Apple Silicon Variants

As of Xcode 26, Apple provides Apple Silicon as well as Universal variants for Xcode versions as well as each runtime. Simply tap on which variant you want installed. To install the Apple Silicon runtime variant Xcode 26 is required to be active.

## Experiments

- Thanks to the wonderful work of [https://github.com/saagarjha/unxip](https://github.com/saagarjha/unxip), turn on the experiment to increase your unxipping time by up to 70%! More can be found on his repo, but bugs, high memory may occur if used.

![](experiment_light.png#gh-light-mode-only)
![](experiment_dark.png#gh-dark-mode-only)

## Localization

Xcodes supports localization in several languages.

The following languages are supported because of the following community users!

|||||
|-|-|-|-|
|French 🇫🇷 |[@dompepin](https://github.com/dompepin)|Italian 🇮🇹 |[gualtierofrigerio](https://github.com/gualtierofrigerio)|
|Spanish 🇪🇸🇲 |[@cesartru88](https://github.com/cesartru88)|Korean 🇰🇷 |[@ryan-son](https://github.com/ryan-son)|
|Russian 🇷🇺 |[@alexmazlov](https://github.com/alexmazlov)|Turkish 🇹🇷 |[@egesucu](https://github.com/egesucu)|
|Hindi 🇮🇳 |[@KGurpreet](https://github.com/KGurpreet)|Chinese-Simplified 🇨🇳|[@megabitsenmzq](https://github.com/megabitsenmzq)|
|Finnish 🇫🇮 |[@marcusziade](https://github.com/marcusziade)|Chinese-Traditional 🇹🇼|[@itszero](https://github.com/itszero)|
|Ukranian 🇺🇦 |[@gelosi](https://github.com/gelosi)|Japanese 🇯🇵|[@tatsuz0u](https://github.com/tatsuz0u)|
|German 🇩🇪|[@drct](https://github.com/drct)|Dutch 🇳🇱|[@jfversluis](https://github/com/jfversluis)|
|Brazilian Portuguese 🇧🇷|[@brunomunizaf](https://github.com/brunomunizaf)|Polish 🇵🇱|[@jakex7](https://github.com/jakex7)|
|Catalan|[@ferranabello](https://github.com/ferranabello)|Greek 🇬🇷|[@alladinian](https://github.com/alladinian)
|Thai 🇹🇭|[@neetrath](https://github.com/neetrath)|Swedish 🇸🇪|[@dhindrik](https://github.com/dhindrik)|

Want to add more languages? Simply create a PR with the updated strings file.

## Installation
v1.X - requires macOS 11 or newer
v2.X - requires macOS 13
v3.X - requires macOS 13 - architecture variants and updated icon.

### Install with Homebrew

Developer ID-signed and notarized release builds are available on Homebrew. These don't require Xcode to already be installed in order to use.

```sh
brew install --cask xcodes
```

### Manually install

1. Download the latest version [here](https://github.com/XcodesOrg/XcodesApp/releases/latest) using the **Xcodes.zip** asset. These are Developer ID-signed and notarized release builds and don't require Xcode to already be installed in order to use.
2. Move the unzipped `Xcodes.app` to your `/Applications` directory

## Support

Xcodes.app and CLI is updated, maintained with contributors like yourself. Even open source libraries and tools come with expenses. If you would like to support Xcodes or donate to the development and maintenance of the tool, it would be greatly appreciated. There is absolutely no obligation!

<a href="https://opencollective.com/xcodesapp" target="_blank">
				<img src="https://opencollective.com/xcodesapp/donate/button@2x.png?color=blue" class="buymeacoffee" width=200 />
</a>

## Development

You'll need macOS 15.6 Ventura and Xcode 26 in order to build and run Xcodes.app.

The Clean Up window uses [XcodesCleanupKit](https://github.com/XcodesOrg/XcodesCleanupKit), pinned to version 1.0.0. Default folders come from `FindingCatalog.developer(...)`; Add Folder suggestions and their metadata come from `FindingCatalog.OptionalFolder` and `optional(home:)`. Folder models and the JSON configuration schema also live in the package; Xcodes owns saving and reloading the file. OS metadata, category candidate queries, and read-only classification are shared as well. Other UIs can use the same APIs. Xcode resolves the package from GitHub. See the package README for independent tests, API examples, and performance verification. The existing CLI does not depend on it.

### Known build warnings

The following dependency and helper limitations remain:

- `ld: building for macOS-14.6, but linking with dylib '@rpath/libcbor.0.11.0.dylib' which was built for newer version 15.0`: the prebuilt `libcbor` in LibFido2Swift targets macOS 15 while the app targets 14.6. Resolving it means raising the app's deployment target or rebuilding that dependency for 14.6.
- `SMJobBless` is deprecated in favor of `SMAppService`. The one legacy call is isolated in a marked shim in `HelperClient.swift` until the privileged helper moves to `SMAppService`, which uses a different install and approval model.

`Unxip` and `aria2` must be compiled as a universal binary
```
# compile for Intel
 swiftc -parse-as-library -O -target x86_64-apple-macos11 unxip.swift
# compile for M1
 swiftc -parse-as-library -O -target arm64-apple-macos11 unxip.swift

# combine for universal binary
 lipo -create -output unxip unxip_intel unxip_m1  
# check it
 lipo -archs unxip
```


[`xcode-install`](https://github.com/xcpretty/xcode-install) and [fastlane/spaceship](https://github.com/fastlane/fastlane/tree/master/spaceship) both deserve credit for figuring out the hard parts of what makes this possible.


## Releasing a new version

Merge the intended changes into `XcodesOrg/XcodesApp` `main`. Review the Release Drafter draft on GitHub and edit the notes there if needed. If any merged PRs were uncategorized, label them and rerun Release Drafter before reviewing the notes. If the privileged helper changed, decide whether to bump its version separately. A helper version bump requires users to reinstall the helper and approve it again.

From this checkout on your Mac, substitute the version you want to ship.

```sh
./Scripts/release 4.2.1 --dry-run
./Scripts/release 4.2.1
```

Add `--prerelease` to preview or publish a prerelease. The publish command builds the latest GitHub `main`, sets the app version and build, pushes the signed tag and version commit, and publishes the notarized `Xcodes.zip` with its Sparkle signature. It updates both appcasts in `XcodesOrg/website` and verifies them on `www.xcodes.app`. Prereleases appear only in the prerelease feed. Use the printed SHA-256 for the [Homebrew cask](https://github.com/XcodesOrg/homebrew-cask/blob/master/Casks/x/xcodes.rb).

### One-time local setup

- Select the Xcode you want to build with. Install its Apple Development signing identity and the Developer ID Application identity for team `ZU6GR6B2FY` in Keychain.
- Install Python 3.9 or newer and GitHub CLI. Sign in with `gh auth login` using a GitHub account that can publish releases, run Actions, and push to `XcodesOrg/XcodesApp` and `XcodesOrg/website`. Configure a Git signing key for release tags.
- Install the existing Sparkle private key from the Xcodes 1Password vault in your login Keychain. Store your Apple ID notarization credentials in the `AC_PASSWORD` Keychain profile. With an app-specific password ready, run the following and enter it when prompted.

```sh
xcrun notarytool store-credentials AC_PASSWORD --apple-id YOUR_APPLE_ID --team-id ZU6GR6B2FY
```

### Resuming a release

If the command stops after saving a signed archive, use the tag it prints to continue. Use the same checkout for an unpublished release so the command can find the saved archive in its Git directory. For a published release, `--resume` uses the existing GitHub release to repair or verify the appcasts.

```sh
./Scripts/release --resume v4.2.1b43
```

## Maintainers

[Matt Kiazyk](https://github.com/mattkiazyk) - [Twitter](https://www.twitter.com/mattkiazyk)

[Twitter](https://twitter.com/xcodesApp) | [GitHub](https://github.com/xcodesOrg) | [Mastadon](https://iosdev.space/@XcodesApp) |
