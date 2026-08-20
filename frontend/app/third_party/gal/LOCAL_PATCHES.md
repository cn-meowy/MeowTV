# Local Patches for `gal`

This directory is a vendored copy of [`gal` 2.3.3](https://pub.dev/packages/gal)
(`https://github.com/natsuk4ze/gal`) used by the MeowTV macOS app.

It exists because the upstream 2.3.3 release declares a macOS deployment target
incompatible with what `flutter pub get` writes into the FlutterGeneratedPluginSwiftPackage
manifest, which causes **first Xcode build after `pub get` to fail** with a package
graph error. There is no upstream fix available
([flutter/flutter#186804](https://github.com/flutter/flutter/issues/186804),
P2, open, no milestone, found in 3.44).

When the upstream ships a fixed release (gal lowers its darwin SPM minimum, or
flutter#186804 lands and `pub get` honours the build target), revert to the
pub.dev version and delete this directory.

## Symptom (with upstream `gal: ^2.3.0`)

Running `xcodebuild` directly (or pressing Cmd+R in Xcode) right after
`flutter pub get` fails with:

```
The package product 'gal' requires minimum platform version 11.0 for the macOS platform,
but this target supports 10.15
```

The only documented workaround is `flutter build macos --config-only` (or any
`flutter build macos` variant), which forces the manifest platforms to be lifted
to match the Runner target. A scheme PreAction cannot fix this — Xcode resolves
the package graph before pre-actions run.

Note also that after a fresh `flutter clean`, two other pre-existing Flutter
errors block direct `xcodebuild` runs regardless of the gal issue:
`Unable to load contents of file list: FlutterInputs.xcfilelist` /
`FlutterOutputs.xcfilelist` (only `flutter build` creates empty versions of
these — see `flutter_tools/lib/src/macos/build_macos.dart:180-185`) and
`The sandbox is not in sync with the Podfile.lock` (needs `pod install` to
regenerate `Pods/Manifest.lock`). `flutter build macos --config-only` handles
both as a side effect.

## Root cause

- `flutter pub get` writes
  `macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift`
  with `platforms: [.macOS("10.15")]` hard-coded by
  `flutter_tools/lib/src/darwin/darwin.dart:77` (`macos => Version(10, 15, null)`).
- `SwiftPackageManager.updateMinimumDeployment` (which lifts the manifest to
  match `MACOSX_DEPLOYMENT_TARGET`) is invoked from `build_macos.dart:170` /
  `ios/mac.dart:355` — i.e. only during the `flutter build` path, never during
  `pub get`.
- Upstream `gal` 2.3.3 declares `.macOS("11.0")` in `darwin/gal/Package.swift`,
  so Xcode's direct resolution rejects the manifest on first build.
- Running a `flutter build` first lifts the manifest to `11.0` and the conflict
  disappears — but that defeats "open the project in Xcode and hit Cmd+R".

## Fix (vs. upstream 2.3.3)

### darwin SPM — `darwin/gal/Package.swift`

```diff
-        .macOS("11.0")
+        .macOS("10.15")
```

`.iOS("11.0")` is intentionally left unchanged — iOS has no `pub get`/Xcode
direct-build conflict, and the App Store iOS deployment target is unaffected.

## Why this is safe

Every PhotoKit API used by `GalPlugin.swift` works on macOS 10.15:

- `PHAssetChangeRequest`, `PHAssetCollectionChangeRequest`,
  `PHPhotoLibrary.shared().performChanges`, `PHAsset.fetchAssets`,
  `PHAssetCollection.fetchAssetCollections` — all 10.15+.
- The only macOS-11-gated APIs in the plugin are
  `PHPhotoLibrary.authorizationStatus(for:)` and
  `PHPhotoLibrary.requestAuthorization(for:)`, both wrapped in
  `#available(iOS 14, macOS 11, *)` guards with explicit 10.15 fallback
  branches (`GalPlugin.swift:145`, `:158`).

Since the Runner target sets `MACOSX_DEPLOYMENT_TARGET = 11.0`, the runtime
**always** takes the `11+` branch; the `10.15` lower declaration is a pure
SPM-resolver compat shim and never executes at runtime.

The `gal.podspec` (kept untouched under `darwin/`) still declares `osx 11.0`,
but the project ships via Swift Package Manager, so the podspec is not
consulted. If CocoaPods is reintroduced later, `pod 'osx 11.0'` against Runner
target `11.0` is already satisfied.

## Versioning

The vendored `pubspec.yaml` is bumped to `2.3.3-local` to make it obvious in
dependency graphs that this is not the upstream artifact. The package `name`
stays `gal` so existing `import 'package:gal/...';` lines in the app continue
to work without changes.

## Practical local workflow

After a fresh clone or `flutter clean`, the working sequence is:

```sh
cd frontend/app
flutter pub get                              # gal now declares 10.15, matches manifest
flutter build macos --config-only            # creates xcfilelists, lifts manifest, runs pod install
cd macos && xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug build
```

The gal-specific failure mode that this patch addresses is the `package product
'gal' requires minimum platform version 11.0` error. Without this patch, the
`xcodebuild` line above fails on the gal platform error even with the prep
steps in place. With this patch, `xcodebuild` succeeds (matching upstream gal
on iOS, which already targets 11.0, is unaffected).

If only iterating on Dart code and `pub get` is rerun, the existing xcfilelists
and `Pods/Manifest.lock` are preserved and `xcodebuild` continues to work.

## Re-syncing with upstream

1. Delete this directory: `rm -rf frontend/app/third_party/gal`
2. Restore the pub.dev dependency in `frontend/app/pubspec.yaml`:
   `gal: ^2.3.0` (or the new fixed version)
3. From `frontend/app`: `flutter build macos --config-only && flutter pub get`
   (the `--config-only` step restores xcfilelists and `Pods/Manifest.lock`).
4. After `pub get`, Xcode may still cache the old `.packages/gal-2.3.3`
   resolution. Force-clear with:
   `rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*`
   (the symlink name now lacks the version suffix — `gal` instead of
   `gal-2.3.3` — so version bumps alone won't trigger Xcode to re-read the
   manifest).

## Upgrade flow (when bumping gal)

1. Replace the vendored tree with the new pub-cache contents, preserving the
   exclusion of `example/` and `darwin/gal/.swiftpm/`:
   ```sh
   rsync -a --exclude='example' --exclude='darwin/gal/.swiftpm' \
     ~/.pub-cache/hosted/pub.dev/gal-<NEW>/ \
     frontend/app/third_party/gal/
   ```
2. Bump `version` in `frontend/app/third_party/gal/pubspec.yaml` to
   `<NEW>-local`.
3. Re-apply the `.macOS("11.0")` → `.macOS("10.15")` patch in
   `darwin/gal/Package.swift` if still needed (check upstream first).
4. `flutter clean && flutter pub get`, then clear Xcode DerivedData (see step 4
   above).
5. Update the version numbers and "vs. upstream" sections in this file.