# Code Audit

## Executive summary

The project is technically ambitious and generally well structured. It makes strong use of actors, async/await, cancellation, cache key hashing, and dedicated media abstractions.

The project builds successfully, but the active Xcode scheme currently executes **zero tests**, which is the most important process concern.

## Strengths

- Good separation between Core, Features, and Tests.
- Strong use of actors for SMB, PhotoKit, local storage, thumbnailing, and streaming.
- Good cancellation handling in network and media operations.
- Cache keys use SHA-256 and include connection identity.
- SMB range parsing has dedicated edge-case coverage.
- Security-scoped bookmarks are handled explicitly.
- No problematic `ObservableObject`, `NavigationView`, `AnyView`, or non-private `@State` usage was detected.
- The project builds without compiler errors.

## High-priority issues

### 1. Tests are not integrated into the active target

Xcode reports:

- One application target only.
- `RunAllTests`: **0 tests discovered**.
- The repository contains test files, but they are not currently executed by the scheme.

This means regressions in SMB streaming, caching, thumbnail generation, and playback logic can go unnoticed.

Recommended improvements:

- Create or restore a unit-test target.
- Add the existing `Tests` directory to that target.
- Ensure the scheme includes the test bundle.
- Add CI execution with `xcodebuild test`.

### 2. `MediaCacheManager` is globally shared but not isolated

`MediaCacheManager` is declared as `Sendable` and used through a singleton while performing mutable filesystem operations from multiple detached tasks.

Potential problems:

- Concurrent writes and deletion can race.
- Cache migration can occur while another task reads or invalidates the same file.
- Errors are silently ignored.
- The `Sendable` guarantee is manually asserted rather than enforced through isolation.

Recommended improvements:

- Convert the manager into an `actor`, or introduce a dedicated cache actor.
- Centralize writes, migrations, eviction, and invalidation through that actor.
- Use explicit cache errors instead of silently swallowing filesystem failures.
- Keep synchronous memory-cache access separate from disk-cache access.

### 3. SMB streaming can report incomplete data as successful

In `SMBResourceLoaderDelegate`, an empty SMB chunk breaks the loading loop. The request can then call `finishLoading()` even though the requested range was not completely delivered.

This can produce corrupted playback or unexplained AVPlayer failures.

Recommended improvements:

- Track the number of bytes delivered.
- If fewer bytes than requested were received, finish with an error.
- Treat an unexpected empty chunk as an I/O failure unless the requested range is already complete.

### 4. MIME type detection is too broad

The resource loader uses `public.mpeg-4` for every extension other than MOV, despite supporting formats such as MKV and WebM.

This can cause AVFoundation to interpret media incorrectly.

Recommended improvements:

- Map extensions to accurate UTIs/content types.
- Use VLC playback for formats unsupported by AVFoundation.
- Add tests for MP4, MOV, MKV, WebM, AVI, and WMV.

### 5. Unknown file sizes are represented as one byte

If a media item has a size of zero, the resource loader reports a content length of one byte. This is not a truthful representation of the resource and can confuse AVFoundation.

Recommended improvements:

- Resolve the remote file size before creating the AVAsset.
- If the size cannot be determined, fail clearly or use a streaming engine that supports unknown lengths.
- Do not report a fabricated content length.

## Maintainability concerns

### 6. Several files are too large

Notable examples:

- `StorageLocationManager.swift` — approximately 1,339 lines.
- `VideoPlayerController.swift` — approximately 1,147 lines.
- `MediaGridView.swift` — approximately 1,146 lines.

These files likely combine state management, networking, caching, navigation, playback, and UI composition.

Recommended decomposition:

- Move loading workflows into dedicated models.
- Extract playback state into a view model/controller.
- Separate cache policy from cache I/O.
- Split large SwiftUI bodies into independent `View` types with narrow inputs.
- Keep each feature coordinator focused on one lifecycle.

This should improve compilation time, testing, and SwiftUI invalidation performance.

### 7. Too many ignored errors

There are more than 100 `try?` usages.

Some are appropriate for best-effort cleanup, but many appear in persistence, cache migration, directory creation, and media loading paths.

Recommended improvements:

- Use `try?` only for intentionally ignorable operations.
- Log failures with `AppLog`.
- Return typed errors from important operations.
- Distinguish a cache miss from a filesystem failure.
- Add diagnostics for failed migrations and writes.

### 8. Detached tasks need stricter ownership rules

The project uses multiple `Task.detached` calls, including in cache management, video playback, and SMB image processing.

Detached tasks are appropriate for isolated CPU work, but they bypass structured task inheritance and cancellation relationships.

Recommended improvements:

- Prefer child tasks or actor methods when possible.
- Use detached tasks only for clearly isolated, synchronous CPU-bound work.
- Avoid capturing large objects such as `UIImage`, manager singletons, or UI-related state unless necessary.
- Document why each detached task is safe.

## Configuration concerns

### 9. Local-network privacy configuration appears incomplete

The Info.plist contains `NSBonjourServices`, but the actual `NSLocalNetworkUsageDescription` key was not visible in the plist search. It appears in the String Catalog, but that does not guarantee it is present in the runtime Info.plist.

For SMB Bonjour discovery, verify that the built app contains `NSLocalNetworkUsageDescription`.

Without it, local network discovery may fail or produce an incomplete permission flow.

### 10. Background audio should be justified

The Info.plist declares the `audio` background mode.

That is appropriate only if the app intentionally supports background audio playback. Otherwise it can create App Store review and policy concerns.

Verify that background video/audio playback is a deliberate product requirement.

## SwiftUI observations

The project avoids several common SwiftUI problems:

- No `ObservableObject` detected.
- No `NavigationView`.
- No `AnyView`.
- `@State` declarations appear properly private.
- Most list identity appears stable.

The PDF views use page indices as identifiers. This is low risk because PDF page ranges are static, but using page numbers consistently as identity would make the intent clearer.

## Recommended order of work

1. Wire the existing tests into a real test target and CI.
2. Fix SMB streaming completion and content-length handling.
3. Make disk-cache mutation actor-isolated.
4. Replace important `try?` calls with typed errors and logging.
5. Split the three largest files.
6. Verify local-network privacy configuration and background audio justification.
7. Add integration tests for SMB playback and cache concurrency.

## Conclusion

The codebase has a good architectural direction, but its reliability is currently limited more by test integration and concurrency boundaries than by basic code quality.
