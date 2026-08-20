# Local Patches for `ffmpeg_kit_flutter_new`

This directory is a vendored copy of
[`ffmpeg_kit_flutter_new` 4.6.2](https://pub.dev/packages/ffmpeg_kit_flutter_new)
(`https://github.com/sk3llo/ffmpeg_kit_flutter`) used by the MeowTV iOS app.

It exists because the upstream 4.6.2 release declares an iOS deployment target
incompatible with what `flutter pub get` writes into the
FlutterGeneratedPluginSwiftPackage manifest, which causes **the first Xcode
build after `pub get` to fail** with a package graph error. There is no
upstream fix available — `ffmpeg_kit_flutter_new` 4.6.2 is the latest release
on pub.dev, and the Flutter-side gap is tracked as
[flutter/flutter#186804](https://github.com/flutter/flutter/issues/186804)
(P2, open, no milestone, found in 3.44; this machine runs 3.44.4).

When the upstream ships a fixed release (ffmpeg_kit_flutter_new lowers its iOS
SPM minimum, or flutter#186804 lands and `pub get` honours the build target),
revert to the pub.dev version and delete this directory.

## Symptom (with upstream `ffmpeg_kit_flutter_new: ^4.5.1`)

Running `xcodebuild` directly (or pressing Cmd+R in Xcode) right after
`flutter pub get` fails with:

```
The package product 'ffmpeg-kit-flutter-new' requires minimum platform version 14.0
for the iOS platform, but this target supports 13.0
```

The only documented workaround is to first run `flutter build ios` (any
variant), which invokes `SwiftPackageManager.updateMinimumDeployment` and
lifts the umbrella manifest to match the Runner target's
`IPHONEOS_DEPLOYMENT_TARGET = 14.0`. But `flutter pub get` writes the manifest
back to the hard-coded `.iOS("13.0")` every time it runs, so the failure
recurs on every "pub get → open Xcode" cycle. A scheme PreAction cannot fix
this — Xcode resolves the package graph before pre-actions run.

After a fresh `flutter clean`, two other pre-existing Flutter errors block
direct `xcodebuild` runs regardless of the ffmpeg issue:
`Unable to load contents of file list: FlutterInputs.xcfilelist` /
`FlutterOutputs.xcfilelist` (only `flutter build` creates empty versions of
these — see `flutter_tools/lib/src/macos/build_macos.dart:180-185`; emitted
non-blocking during the first xcodebuild, gone by the second) and possibly
`The sandbox is not in sync with the Podfile.lock` (needs `pod install` to
regenerate `Pods/Manifest.lock`).

## Root cause

- `flutter pub get` writes
  `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift`
  with `platforms: [.iOS("13.0")]` hard-coded by
  `flutter_tools/lib/src/darwin/darwin.dart:77` (`ios => Version(13, 0, null)`).
- `SwiftPackageManager.updateMinimumDeployment` (which lifts the manifest to
  match `IPHONEOS_DEPLOYMENT_TARGET`) is invoked from `ios/mac.dart:355` — i.e.
  only during the `flutter build` path, never during `pub get`.
- Upstream `ffmpeg_kit_flutter_new` 4.6.2 declares `.iOS("14.0")` in
  `ios/ffmpeg_kit_flutter_new/Package.swift`, so Xcode's direct resolution
  rejects the manifest on first build.
- Running a `flutter build` first lifts the manifest to `14.0` and the
  conflict disappears — but that defeats "open the project in Xcode and hit
  Cmd+R".

A grep across every SPM plugin in the lockfile confirms ffmpeg_kit_flutter_new
is the only plugin exceeding the manifest floor: `connectivity_plus 12.0`,
`device_info_plus 13.0`, `gal 11.0`, `mobile_scanner 12.0`, `share_plus 13.0`
etc. are all `<= 13.0`. No other plugin needs patching.

## Fix (vs. upstream 4.6.2)

### iOS SPM — `ios/ffmpeg_kit_flutter_new/Package.swift`

```diff
         .iOS("14.0")
     ],
```

```diff
         .iOS("13.0")
     ],
```

The macOS Package.swift under `macos/ffmpeg_kit_flutter_new/Package.swift` is
intentionally left untouched — the macOS shell is not integrated (no ffmpeg
macOS plug-in registration in this app), and the iOS-only patch is the minimum
change that fixes the failing path.

The `ffmpeg_kit_flutter_new.podspec` (kept untouched under `ios/`) still
declares `deployment_target = '14.0'`. The Runner Podfile declares
`platform :ios, '14.0'`. The project ships plugins via Swift Package Manager
(`ios/Podfile.lock` contains only Flutter + fl_pip), so the podspec is not
consulted. If CocoaPods is reintroduced later, the podspec target already
matches Runner.

## Why this is safe

The `ffmpeg-kit-flutter-new` product is built from **eight prebuilt XCFramework
binaryTargets** (the URL/checksum pairs declared inline in
`ios/ffmpeg_kit_flutter_new/Package.swift`) plus **one thin ObjC bridge
target** (`Sources/FFmpegKitFlutterPlugin.m`,
`include/ffmpeg_kit_flutter_new/FFmpegKitFlutterPlugin.h`).

- The binary targets carry their real minimum OS inside the prebuilt
  `Info.plist` of each xcframework slice; lowering the SPM `platforms`
  declaration cannot loosen that. None of the eight xcframeworks
  (`ffmpegkit`, `libavcodec`, `libavdevice`, `libavfilter`, `libavformat`,
  `libavutil`, `libswresample`, `libswscale`) ship new iOS-14-gated symbols
  beyond what `IPHONEOS_DEPLOYMENT_TARGET = 14.0` already requires at link
  time.
- The ObjC bridge is a plain Flutter method-channel shim. A grep across
  `Sources/` confirms there are zero `@available` / `__has_include` / SDK
  version-gated calls — it just forwards
  `MethodChannel.invokeMethod` calls between Dart and the static-link C ABI
  exposed by the eight xcframeworks.

The Runner target sets `IPHONEOS_DEPLOYMENT_TARGET = 14.0` (and the Podfile
declares `platform :ios, '14.0'`), so the runtime **always** runs on iOS 14+
regardless of what the SPM declaration says. Lowering the declaration to
`13.0` is a pure SPM-resolver compatibility shim, identical in spirit to the
gal macOS `11.0` → `10.15` patch (see `third_party/gal/LOCAL_PATCHES.md`).

## Versioning

The vendored `pubspec.yaml` is bumped to `4.6.2-local` to make it obvious in
dependency graphs that this is not the upstream artifact. The package `name`
stays `ffmpeg_kit_flutter_new` so the three existing
`package:ffmpeg_kit_flutter_new/...` imports in
`lib/features/player/capture/gif_generator.dart` continue to work without
changes.

## Practical local workflow

After a fresh clone or `flutter clean`, the working sequence is:

```sh
cd frontend/app
flutter pub get                                       # ffmpeg now declares 13.0, matches manifest
cd ios && xcodebuild -workspace Runner.xcworkspace -scheme Runner \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

The first xcodebuild after a clean downloads eight full-gpl xcframework zips
(hundreds of MB) from the `sk3llo/ffmpeg_kit_flutter` GitHub release
(`tag 8.1.2-full-gpl`); this is expected and not a failure. The same build
also creates the empty `FlutterInputs.xcfilelist` /
`FlutterOutputs.xcfilelist` files via `xcode_backend.sh`, so two non-blocking
warnings may appear on the first build only and vanish on the second.

If iterating on Dart code and `pub get` is rerun, the existing xcfilelists
and `Pods/Manifest.lock` are preserved and `xcodebuild` continues to work
without any further prep.

## Re-syncing with upstream

1. Delete this directory: `rm -rf frontend/app/third_party/ffmpeg_kit_flutter_new`
2. Restore the pub.dev dependency in `frontend/app/pubspec.yaml`:
   `ffmpeg_kit_flutter_new: ^4.5.1` (or the new fixed version)
3. From `frontend/app`: `flutter pub get` and (if needed)
   `flutter build ios --debug --no-codesign` to refresh the manifest.
4. After `pub get`, Xcode may still cache the old
   `.packages/ffmpeg_kit_flutter_new-4.6.2` resolution. Force-clear with:
   `rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*`
   (the new symlink name lacks the version suffix — `ffmpeg_kit_flutter_new`
   instead of `ffmpeg_kit_flutter_new-4.6.2` — so version bumps alone won't
   trigger Xcode to re-read the manifest).

## Upgrade flow (when bumping ffmpeg_kit_flutter_new)

1. Replace the vendored tree with the new pub-cache contents, preserving the
   exclusion of `example/`:
   ```sh
   rsync -a --exclude='example' \
     ~/.pub-cache/hosted/pub.dev/ffmpeg_kit_flutter_new-<NEW>/ \
     frontend/app/third_party/ffmpeg_kit_flutter_new/
   ```
2. Bump `version` in
   `frontend/app/third_party/ffmpeg_kit_flutter_new/pubspec.yaml` to
   `<NEW>-local`.
3. Re-apply the `.iOS("14.0")` → `.iOS("13.0")` patch in
   `ios/ffmpeg_kit_flutter_new/Package.swift` if still needed (check upstream
   first — only the iOS Package.swift needs the patch; the macOS one stays
   untouched regardless).
4. `flutter clean && flutter pub get`, then clear Xcode DerivedData (see
   re-sync step 4 above).
5. Update the version numbers and "vs. upstream" sections in this file.