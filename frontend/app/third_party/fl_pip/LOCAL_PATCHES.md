# Local Patches for `fl_pip`

This directory is a vendored copy of [`fl_pip` 3.2.3](https://pub.dev/packages/fl_pip)
(`https://github.com/Wayaer/fl_pip`) used by the MeowTV mobile app.

It exists because the upstream 3.2.3 release fails to compile against modern
Flutter (≥ 3.27) and the upstream maintainer has not released a fix yet
(see [Wayaer/fl_pip#33](https://github.com/Wayaer/fl_pip/issues/33),
[Wayaer/fl_pip#26](https://github.com/Wayaer/fl_pip/issues/26)).

When the upstream ships a fixed release, revert to the pub.dev version and
delete this directory.

## Versioning

The vendored `pubspec.yaml` is bumped to `3.2.4-local` to make it obvious in
dependency graphs that this is not the upstream artifact. The package `name`
stays `fl_pip` so existing `import 'package:fl_pip/...';` lines in the app
continue to work without changes.

## Patches Applied (vs. upstream 3.2.3)

### iOS — `ios/Classes/PiPHelper.swift`

**Symptom**: Swift compiler errors when building for iOS:

```
Cannot use optional chaining on non-optional value of type 'FlutterEngine'
  PiPHelper.swift:199:18
Cannot force unwrap value of non-optional type 'FlutterEngine'
  PiPHelper.swift:203:68
Cannot use optional chaining on non-optional value of type 'FlutterEngine'
  PiPHelper.swift:242:22
Cannot force unwrap value of non-optional type of type 'FlutterEngine'
  PiPHelper.swift:245:72
```

**Root cause**: Upstream 3.2.3 added "FIX" code (see comments at lines 196–203
and 242–246 of the upstream file) that treated `FlutterViewController.engine`
as optional. In modern Flutter (≥ 3.27) `engine` is non-optional, so the
optional chaining `engine?.` and force-unwrap `engine!` are compile errors.

**Fix**: Drop the optional chaining and force-unwrap, since `engine` is
guaranteed non-optional. Concretely, in two locations (`pictureInPictureControllerDidStartPictureInPicture`
~L199, `dispose` ~L242):

| Before                                            | After                       |
| ------------------------------------------------- | --------------------------- |
| `let engine = flController.engine`                | unchanged                   |
| `engine?.viewController = nil`                    | `engine.viewController = nil` |
| `FlutterViewController(engine: engine!, ...)`    | `FlutterViewController(engine: engine, ...)` |

The misleading "FIX 1/2/3" / "FIX" comments have been removed since they no
longer apply.

No changes to the Dart layer (`lib/`), Android layer (`android/`), podspec,
assets, or plugin manifest are required.

## Re-syncing with upstream

1. Delete this directory: `rm -rf frontend/app/third_party/fl_pip`
2. Restore the pub.dev dependency in `frontend/app/pubspec.yaml`:
   `fl_pip: ^3.2.3` (or the new fixed version)
3. From `frontend/app`: `flutter pub get && cd ios && pod install`