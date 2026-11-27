# Fichier + FichierKit: Code Review Fix Plan

Handoff plan for an implementing agent. Source: static review (no build/tests run).

## Projects
- App: `/Users/kevinlaunay/source/apple/com.acme.ios.fichier` (targets `fichier`, `FichierTV`, tests `fichierTests`, `FichierTVTests`)
- Package: `/Users/kevinlaunay/source/apple/library/com.acme.swift.package.FichierKit` (`Sources/FichierKit`, `Tests/FichierKitTests`)

## Rules (must follow)
- Read `/Users/kevinlaunay/.gemini/config/skills/ios-senior-developer/SKILL.md` first.
- Follow `/Users/kevinlaunay/source/apple/AGENTS.md`.
  - **Never `git commit`, `git push` or `git add`.** Leave changes in the working tree.
  - Strict 1 type = 1 file.
  - Swift 6 pure concurrency. No `DispatchQueue`, locks or `nonisolated(unsafe)`, except in the documented bridging cases already present.
- Smallest safe change. Don't touch unrelated files. Preserve public APIs unless a phase says otherwise.
- User-facing text: `lower_snake_case` key in `strings.xcstrings` first (`extractionState: "manual"`, comment, all project locales), then use `.Strings.<camelCase>` symbols. Use positional specifiers (`%1$lld`, `%2$@`).
- After each phase:
  - Build iOS and tvOS schemes quietly (verbose only on failure).
  - Run the affected tests.
  - Run `swiftlint` where configured.
  - Report changes, validation and remaining risks.
- Confirm with the user before Phase 5 (large refactor) and before reverting anything.

## Phase 1: Log privacy (FichierKit) — low risk
**Problem:** `os.Logger` interpolations lack explicit privacy. Examples: `SMBImageLoader` (paths, `share`, `url.path`, `error.localizedDescription`), `VideoPlaybackStore`, `SavedSMBConnection`.

**Tasks**
1. `grep -rnE "logger\.(error|warning|info|debug)\(" Sources` and list every call.
2. Mark paths, hosts, shares, filenames and usernames as `privacy: .private`.
3. Mark errors as `privacy: .public` only when they can't contain paths. Otherwise use `.private`.
4. Optional: add a shared `FichierKitLog` enum (own file) with category loggers, and migrate the ad hoc `Logger(...)` declarations.

**Done when:** no unannotated interpolation of path-like values remains. The package builds.

## Phase 2: Localize debug and stray literals (app) — low risk
**Problem:** string-literal keys remain.
- `VideoPlayerTopBarView.swift` (~L339): `"Simulate Crash (SIGABRT)"` and `"Debug Diagnostics"`.
- `MediaGridView.swift` (~L780): `"Invalidate Folder Thumbnails"` and `"Debug"`.
- `Text("PDF")` in `MediaThumbnailView.swift`.
- `Text("\(Int(progress * 100))% • ...")` in `PDFDetailView.swift`.
- The slideshow interval and other interpolated `Text("\(...)")` calls.

**Tasks**
1. Add keys to `fichier/strings.xcstrings` (and the tvOS catalog if used).
2. Replace the literals with `.Strings.*` symbols.
3. Optionally extract the DEBUG menu items into a `DebugMenuView` file (1 type = 1 file).

**Done when:** `grep -rnE 'Text\("|Label\("|Section\("' fichier FichierTV` shows only non-localizable glyphs, such as `"•"`, or interpolation-only values.

## Phase 3: Password store failure handling (FichierKit) — needs a small design decision
**File:** `Storage/SMBPasswordStore.swift`

**Problem:** if `SecItemAdd` or `SecItemUpdate` fails on a real device, the password is kept only in memory. It is lost on relaunch and no error is surfaced.

**Proposal (simplest first)**
1. Make `savePassword` return a discardable `Bool` or throw a typed `SMBPasswordStoreError`.
2. Restrict the in-memory fallback to simulator and tests, via `#if targetEnvironment(simulator)` or an injected flag.
3. Update call sites (`StorageLocationPersistenceStore`, `DefaultSMBServerStore`) to log failures and surface a sanitized message.
4. Add Swift Testing cases that use a mock and don't touch the real Keychain.

If this changes public API, ask the user first.

## Phase 4: Tooling and lint
1. Add `.swiftlint.yml` to the FichierKit package. Mirror the app config with `included: [Sources]`.
2. In the app config, re-enable `file_length`, `type_body_length` and `function_body_length` as **warnings** only, with generous thresholds (for example file 800). Do not make the build fail.
3. Verify the `no_legacy_dispatch_queue` custom rule exists. The code uses `swiftlint:disable:next no_legacy_dispatch_queue`, so it should be defined in the config.

## Phase 5: Concurrency and lifecycle audit — audit first, then fix findings
Report before editing.

**A. Unstructured tasks:** 128 `Task {}` and 10 `Task.detached` sites.
- Check each for these things:
  - a stored handle and `cancel()` on disappear or deinit;
  - a generation token or `Task.isCancelled` check before mutating state;
  - `isLoading` or transient flags reset on every exit path (success, error, cancel).
- Detached tasks to review:
  - `StorageLocationManager.swift:266`
  - `VideoAudioSessionCoordinator.swift:13, 26`
  - `TVSystemRemoteCommandBridge.swift:96`
  - `SMBClientActor.swift:608, 865`
  - `MediaCacheManager+FolderIcon.swift:141`
  - `MediaDetailStore.swift:216, 251`
  - `SMBResourceLoadingTaskTracker.swift:35`
- Keep detached only for CPU-bound decoding.

**B. `@unchecked Sendable` (9 types).** Add a one-line invariant comment to each: why it's safe, and what state is mutable.
- FichierKit:
  - `ThreadSafeMemoryCache`
  - `AMSMB2SessionAdapter`
  - `VLCPictureInPictureMediaController`
  - `PhotoExportSessionBox`
  - `SendablePiPWindowControllerBox`
  - `SendableNSValue`
- App: `SlideImageCache`.
- Scrutinize `VLCPictureInPictureMediaController` and `AMSMB2SessionAdapter` for mutable state. If found, convert to an actor or `@MainActor`, or protect the state properly.

**C. Swallowed errors:** about 51 `try?` / empty-catch sites. Classify each as intentionally benign or hiding a failure. Add logging (Phase 1 conventions) where a failure matters, especially in persistence and network code.

**D. Duplicated resource-loader queues.** Centralize in FichierKit one shared constant for the `AVAssetResourceLoader` delegate queue. Replace `smbResourceLoaderQueue` in `VideoPlayerController` and `TVVideoPlayerViewModel`, and the queues in `MediaDetailStore` and `SMBVideoThumbnailLoader`. Keep the documented `swiftlint:disable`.

## Phase 6: Large-file decomposition — ASK USER BEFORE STARTING
Candidates:

| File | Lines |
|---|---|
| `VideoPlayerController.swift` | 1243 |
| `TVVideoPlayerViewModel.swift` | 1237 |
| `StorageLocationManager.swift` | 950 |
| `SMBClientActor.swift` | 933 |
| `TVVLCPlayerEngine.swift` | 895 |
| `MediaGridView.swift` | 808 |

**Approach:** extract by capability into `Type+Capability.swift` files or single-purpose types. Examples: seek, tracks, PiP, resource loading, persistence.
- Move logic shared by the iOS and tvOS player models into FichierKit behind `Sendable` protocols.
- Do one file per PR-sized step, with the build and tests green between steps.
- Present a short proposal and trade-offs to the user first.

## Phase 7: Tests
- FichierKit has about 21 test files for about 11k lines. Add Swift Testing suites (`@Suite`, `@Test`, `#expect`) with standalone `Mocks/` for:
  - `MediaCacheManager`
  - `MediaDiskCacheActor`
  - `SMBAVAssetResourceLoaderDelegate`
  - `SMBResourceLoadingTaskTracker`
  - the engines' state transitions, via protocols
  - the Phase 3 password store behavior
- Cover cancellation and stale-result cases.

## Other notes (no action unless asked)
- VLCKit is pinned `exact: "4.0.0-a25"` (alpha). Wappn is a relative path dependency. Mention both in the final report only.
- Trim marketing-style doc comments ("high-performance") to state invariants when touching a file anyway.

## Final report must include
Files changed, build and test results for iOS, tvOS and FichierKit, new risks, and which phases were skipped or deferred.
