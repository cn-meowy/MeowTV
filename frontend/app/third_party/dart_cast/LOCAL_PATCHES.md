# Local Patches for `dart_cast`

This directory is a vendored copy of [`dart_cast` 0.7.3](https://pub.dev/packages/dart_cast)
(`https://github.com/abdelaziz-mahdy/dart_cast`) used by the MeowTV mobile app.

The fork is re-synced to upstream `0.7.3` and applies only **non-AirPlay** patches.
AirPlay support in the app is now provided by native iOS/macOS `AVRoutePickerView`
(see `frontend/app/ios/Runner/AirPlayPlugin.swift` and
`frontend/app/macos/Runner/AirPlayPlugin.swift`), so all AirPlay patches previously
shipped in this fork have been dropped.

When the upstream ships a fixed release of these patches, revert to the pub.dev
version and delete this directory (see [Re-syncing with upstream](#re-syncing-with-upstream)).

## Versioning

The vendored `pubspec.yaml` is bumped to `0.7.3-local` to make it obvious in
dependency graphs that this is not the upstream artifact. The package `name`
stays `dart_cast` so existing `import 'package:dart_cast/...';` lines in the app
continue to work without changes.

## Patches Applied (vs. upstream 0.7.3)

### `lib/src/core/media_proxy.dart` — HLS & subtitle rewrite gate accepts 206

**Symptom**: When casting Strategy A (HLS standard buffering) to a DLNA device
whose renderer is libmpv (e.g. Apple TV via UnPlay, UA=`libmpv(iPhone)`), the TV
gets stuck on the "connecting" overlay with `position=0s, duration=0s` and
repeatedly re-requests `index.m3u8` once per second. Logs show:

```
MediaProxy: upstream 206 type=application/vnd.apple.mpegurl len=96 url=...index.m3u8
MediaProxy: GET /stream/3000k/hls/mixed.m3u8   ← TV requesting an un-rewritten relative segment path → 404
```

The `rewritten HLS playlist` log line that should follow the upstream 206 never
appears.

**Root cause**: libmpv sends a `Range: bytes=0-` request header. The proxy
forwards it upstream, and the origin responds with `206 Partial Content` for the
m3u8 playlist. The HLS rewrite gate, however, requires
`statusCode == HttpStatus.ok`:

```dart
// upstream 0.7.3
if (_isHlsResponse(targetUrl, upstreamContentType) &&
    upstreamResponse.statusCode == HttpStatus.ok) {
```

`_isHlsResponse` returns `true` (the Content-Type contains `mpegurl`), but
`206 == 200` is `false`, so the rewrite branch is skipped. The raw m3u8 —
containing relative segment paths — is passed through to the TV verbatim and
resolves against the proxy base URL to a 404 route.

The identical gate pattern exists for the subtitle (SRT→VTT) rewrite branch,
so it suffers the same defect whenever a Range request produces 206 for a
subtitle file.

**Fix**: Four coordinated changes in `lib/src/core/media_proxy.dart`:

1. **HLS rewrite gate**: accept `206 Partial Content` in addition to `200 OK`.
2. **Subtitle rewrite gate**: same 206 relaxation for the SRT→VTT branch.
3. **Force 200 + strip Range headers in both rewrite branches**: the upstream
   response status code is propagated to the response, so when upstream returns
   206 the rewritten response inherits 206 / `Content-Range` / `Accept-Ranges`
   semantics. Since the rewritten body is brand-new content (segment URLs
   rewritten to absolute proxy URLs, or SRT converted to VTT), 206/Content-Range
   no longer applies. Both branches explicitly override the status to 200 and
   remove the forwarded Range headers before writing the new body.

**Why this is safe**: The relaxation only affects responses where
`_isHlsResponse` / `_isSubtitleResponse` is `true`. MPEG-TS segments
(`video/mp2t`) and all other media pass through the streaming branch unchanged
and are unaffected. Playlists and subtitle files are small text payloads;
a `Range: bytes=0-` request returns the complete body, so 206 with a full range
is equivalent to 200 for rewriting. The existing `#EXTM3U` prefix check still
guards against partial/non-m3u8 bodies — if the body doesn't start with
`#EXTM3U` it falls through and is sent as-is.

### `lib/src/core/media_proxy.dart` — MediaProxy onError logging

**Symptom**: HttpServer-level errors (e.g. malformed HTTP from a cast device
that opens a TCP socket but never sends a valid request) are silently swallowed
by `dart:io`. The errors never reach the proxy's request handler and never
appear in logs, making cast-time connection issues difficult to diagnose.

**Fix**: Add an `onError` callback to `_server!.listen()` that surfaces parse
errors via `CastLogger.warning`:

```dart
_server!.listen(
  _handleRequest,
  onError: (Object error) {
    CastLogger.warning('MediaProxy: server error: $error');
  },
);
```

Bare TCP connections that send no data are handled internally by `HttpServer`
and remain unobservable here, but parse-level failures that would otherwise
be silent are now surfaced.

### `lib/src/core/media_transformer.dart` — `.m3u8` pathExtension for HLS

**Symptom**: When the proxy registers an HLS media URL with `registerMedia`,
the resulting proxy URL has no file extension:

```
http://{proxy}/stream/{token}/resource
```

Some cast receivers (notably certain DLNA renderers and Chromecast's
content-type probe) inspect the URL path for `.m3u8` and fall back to
treating the response as raw MPEG-TS when the extension is absent. The
playlist is then parsed as a TS stream, producing zero-duration silent
playback.

**Fix**: In `DefaultMediaTransformer.transform()`, when registering remote
media, append the `.m3u8` extension for HLS media:

```dart
: proxy.registerMedia(
    media.url,
    headers: media.httpHeaders,
    pathExtension:
        media.type == CastMediaType.hls ? 'm3u8' : null,
  );
```

`source` and `isLocalFile` branches are unchanged. The non-HLS branch passes
`pathExtension: null`, preserving upstream behavior.

### `lib/src/protocols/dlna/dlna_discovery_provider.dart` — bind concrete IPv4 + try/catch SSDP sends

```
SocketException: Send failed (OS Error: No route to host, errno = 65),
  address = 0.0.0.0, port = 0    ← DLNA / SSDP
```

The `0.0.0.0` in the log is the **local** socket address (`INADDR_ANY`),
not the target. The actual destination `239.255.255.250:1900` is being
silently blocked by the kernel because the app has not yet triggered
the Local Network Privacy system prompt (iOS 14+ only blocks the send;
it does not throw from `socket.bind()`). Worse, the unhandled
`SocketException` propagates from `multicast_dns`/`dart:io` straight to
`dart_vm_initializer`, polluting logs even when the user is on WiFi
(`NetworkUtils: picked 10.232.80.233 (private address)` proves the
device has a valid LAN interface).

**Fix**: Two coordinated changes in `lib/src/protocols/dlna/dlna_discovery_provider.dart`:

1. **Bind a concrete IPv4 instead of `InternetAddress.anyIPv4`.** Use
   `NetworkUtils.getLocalIpAddress()` (which already prefers RFC 1918
   private addresses and excludes link-local / loopback) to pick the
   user's actual LAN interface, and bind the UDP socket to it. Falling
   back to `anyIPv4` preserves upstream behavior when `NetworkInterface.list`
   returns empty (e.g. unusual VPN-only setups).
2. **Wrap both the initial M-SEARCH send and the 500 ms retry in
   `try / catch`.** Log a `CastLogger.warning` on failure, but **do not
   `dispose`** the socket or close the controller — the user may grant
   Local Network permission a few seconds later, and we want the
   listener loop to remain active in case any device manages to send
   responses over a permitted path.

**Why this is safe**: Binding a concrete interface IPv4 instead of
wildcard is invisible to upstream SSDP responders (SSDP replies are
unicast to the socket's local address, which the kernel will rewrite
correctly). Catching `SocketException` from `send()` is also invisible
on platforms where `send()` cannot fail this way (Android, macOS,
desktop Linux) — those platforms never enter the catch branch.

### `lib/src/utils/mdns_discovery.dart` — iOS Local Network pre-warm + try/catch PTR lookup

**Symptom**: Same root cause as above, but for the mDNS path used by
Chromecast and AirPlay discovery. `multicast_dns 0.3.3+1`'s internal
socket is also bound to wildcard and its `send()` is un-wrapped:

```
SocketException: Send failed (OS Error: No route to host, errno = 65),
  address = 0.0.0.0, port = 5353    ← mDNS (Chromecast + AirPlay)
```

The exception bubbles all the way to `dart_vm_initializer`'s
`unhandled exception` channel.

**Fix**: Two coordinated changes in `lib/src/utils/mdns_discovery.dart`:

1. **Pre-warm probe right after `client.start()`.** Issue one bounded
   `lookup<PtrResourceRecord>(serverPointer(serviceType))` with a 2 s
   timeout. We do not consume the result — this is purely to fire the
   first mDNS send and trigger the iOS Local Network system prompt
   earlier in the lifecycle. The whole block is wrapped in
   `try / catch (e)`, with a `CastLogger.warning` on failure.
2. **Wrap each round's PTR `lookup` in a `try / catch`.** Failures
   emit a warning and let the `for (round ...)` loop continue. Already-
   discovered services are preserved via `seenServices`. SRV/A/TXT
   sub-lookups already had their own try/catch in upstream and are
   unchanged.

**Why this is safe**: The pre-warm probe is bounded by a 2 s timeout;
on Android / macOS / desktop the result is essentially instant and
`break`s out of the loop on the first PTR. On iOS pre-permission the
exception is caught and logged but does not abort the real discovery
flow — once the user grants permission, the next round (which already
runs every 2 s × 3) succeeds normally. The pre-warm replaces the
upstream `mDNS: client started, querying PTR records` debug log, so
debug output is functionally equivalent.

### `lib/src/protocols/dlna/dlna_discovery_provider.dart` — surface double-send failure via `addError`

**Symptom**: After the bind-concrete-IPv4 + try/catch patch above, an
iOS device without the `com.apple.developer.networking.multicast`
capability *silently* drops the SSDP M-SEARCH at the kernel. Both
`socket.send()` calls (initial + 500 ms retry) raise `SocketException`
which we log as `CastLogger.warning` but otherwise swallow, so the
discovery stream completes cleanly with zero devices.

Result: `MeowCastService.startDiscovery`'s `onDone` only sets
`_lastDiscoveryAllFailed = true` when the stream emitted an error
(`onError` flips `anyError = true`). With both sends swallowed, the
stream ends normally and `cast_panel.dart`'s "请到 iOS 设置 →
MeowTV → 本地网络 中允许" hint never shows up — even though the
actual root cause is the missing multicast entitlement, not the Local
Network toggle.

**Fix**: Track the result of both M-SEARCH sends in two local variables
(`sendSucceeded`, `sendError`). On timeout, if both sends failed, wrap
the last error in a `StateError` and `_controller.addError(...)`
before `_controller.close()`. If at least one send succeeded we keep
the current "no error, zero devices is fine" behavior (we genuinely
can't distinguish "no devices on LAN" from "kernel silently dropped
the packet" once a send returns normally — the only honest answer is
a warning log).

**Why this is safe**: The added error path mirrors the existing outer
`catch (e)` at the top of `_doDiscovery` (which already calls
`addError` + `close`), so the onError/onDone contract with
`MeowCastService` is unchanged for the bind-failure case. The
double-send-failure case now reaches that contract too. The bind
strategy and iOS 14+ Local Network Privacy Chinese comment block are
preserved verbatim. Android / macOS / desktop Linux never enter the
catch branch and are unaffected.

## Re-syncing with upstream

## Re-syncing with upstream

1. Delete this directory: `rm -rf frontend/app/third_party/dart_cast`
2. Restore the pub.dev dependency in `frontend/app/pubspec.yaml`:
   `dart_cast: ^0.7.3` (or the new fixed version)
3. From `frontend/app`: `rm -f pubspec.lock && flutter pub get`
4. Verify `.dart_tool/package_config.json` resolves `dart_cast` back to
   `~/.pub-cache/hosted/pub.dev/dart_cast-<version>/`.

## Example app — first-time setup

The `example/` subtree is upstream's demo Flutter app. MeowTV itself does
not consume it; we keep it buildable so the patched API surface (notably
`MediaProxy` and the HLS/206 rewrite gate above) stays exercised by
`flutter analyze` on every fresh checkout.

After a fresh clone, or after re-syncing upstream into this directory:

```bash
cd frontend/app/third_party/dart_cast/example
flutter pub get    # one-time per checkout; idempotent afterwards
```

Platform shells (`android/`, `ios/`, `linux/`, `macos/`, `windows/`) are
already present — no `flutter create .` needed. Re-syncing upstream will
overwrite `example/pubspec.lock` semantics; re-run `flutter pub get` in
`example/` if so.

## Verifying the fork is clean

Confirm only the intended files differ from upstream:

```bash
diff -r ~/.pub-cache/hosted/pub.dev/dart_cast-0.7.3/lib third_party/dart_cast/lib
# Expect differences ONLY in:
#   lib/src/core/media_proxy.dart              (HLS/subtitle 206 rewrite gate + force 200 + onError)
#   lib/src/core/media_transformer.dart       (.m3u8 pathExtension for HLS)
#   lib/src/protocols/dlna/dlna_discovery_provider.dart
#                                             (bind concrete IPv4 + try/catch SSDP sends
#                                              + surface double-send failure via addError)
#   lib/src/utils/mdns_discovery.dart          (iOS Local Network pre-warm + try/catch PTR lookup)
```