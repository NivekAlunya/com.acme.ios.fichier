# Fichier + FichierKit: File Split Instructions and Concurrency Audit

Handoff for an implementing agent. Static analysis only: nothing here has been built or run.

- App: `/Users/kevinlaunay/source/apple/com.acme.ios.fichier`
- Package: `/Users/kevinlaunay/source/apple/library/com.acme.swift.package.FichierKit`
- Branch: `optimization/claude-review` in both repos (continue there).

## Rules
- Read `/Users/kevinlaunay/.gemini/config/skills/ios-senior-developer/SKILL.md` first.
- Follow `/Users/kevinlaunay/source/apple/AGENTS.md`.
  - **Never `git commit`, `git push` or `git add`.**
  - 1 type = 1 file.
  - Swift 6 pure concurrency.
  - No new legacy primitives.
- After each step, build iOS, tvOS and FichierKit quietly, then run the affected tests and `swiftlint`.
- Don't change behavior in a split step. Move code only.

---

# Part A: Splitting large files

## Recipe (one file per step)
1. Read the file and group members by `// MARK:` section. Each group becomes a capability.
2. Stored properties stay in the main type's file, because extensions can't add them.
   - Relax `private` to `internal` or `fileprivate` only where an extension needs access. Keep this minimal.
3. Move each group into `<Type>+<Capability>.swift` as an `extension`.
   - Use the standard Xcode header and `// MARK: -`.
4. Types that own their own state become a standalone `actor`, `struct` or `final class` in their own file.
5. Build and test. Don't move on until green.

## Targets

| File | Lines | Suggested split |
|---|---|---|
| `fichier/Core/Storage/StorageLocationManager.swift` | 955 | Saved-connection and folder persistence, lifecycle and memory observers, tree/sidebar updates, folder loading (`loadFolderTask`). Follow the existing `+Media` and `+FileOperations` naming. |
| `fichier/Core/Networking/SMBClientActor.swift` | 933 | Thumbnail and image loading, downloads with `.part` handling, metadata and range reads, each in `SMBClientActor+<Capability>.swift`. Keep connect and session management in the core file. |
| `FichierKit/Sources/TVVLCPlayerEngine.swift` | 895 | Extensions for PiP, scrub and seek throttling, track and chapter handling, and VLC delegate callbacks. Consider a small state type if there are many flags. |
| `fichier/Features/Gallery/MediaGridView.swift` | 808 | Subviews, one file each: toolbar, context-menu content, selection and drag, empty states. Keep the host view slim. |
| `FichierKit/Sources/AMSMB2Client.swift` (optional) | 766 | By operation: listing, read/write, move/delete, session. |

Follow-up (separate step): the iOS and tvOS player code duplicates seek and track logic. Move the shared parts into FichierKit behind `Sendable` protocols.

---

# Part B: Concurrency audit findings

About 150 `Task` sites and 89 `try?` sites. Most are fine: handles are stored, `[weak self]` is used, and `Task.isCancelled` is checked after sleeps.

Good patterns to preserve:
- `StorageLocationManager.selectAndLoadFolder` uses a generation token, a cancellation handler and `isLoading` cleanup on every path.
- `VideoSeekCoordinator` uses a seek generation.
- The limiters (`withPermit`) handle cancelled waiters.

## Findings (priority order)

### 1. Audio session activate and deactivate are unordered (medium)
- `VideoPlayerController.swift` (~L214 and ~L645).
- They are separate unstored `Task {}` calls. Actor execution is serialized, but arrival order isn't guaranteed.
- A fast close-then-open can leave the session deactivated during playback.
- **Fix:** store the last task and `await` it before the next, or give `VideoAudioSessionCoordinator` a monotonic request token and ignore stale requests.
- **Test:** a Swift Testing case calling activate and deactivate in quick succession through a mock.

### 2. `VLCVideoThumbnailActor` start and cancel race (medium)
- `Storage/VLCVideoThumbnailActor.swift` (~L80-106).
- `session.start` and `session.cancel` each run in their own unstructured `Task`, so cancel can run before start. The session then starts after being cancelled and leaks until the watchdog fires.
- **Fix:** track the start task and cancel or await it in `cancelSession`, or make the session ignore `start` once cancelled.

### 3. Timeout fires after a successful race (medium–low)
- `Storage/SMBVideoThumbnailLoader.swift` (~L370-385).
- The timeout child is `try? await Task.sleep(...)` then `onAbort?()`.
- When the render wins, `group.cancelAll()` cancels the sleep, `try?` swallows the error, and `onAbort()` runs anyway. It cancels SMB reads after success, and may hit other in-flight reads if the delegate is shared.
- **Fix:**
  ```swift
  do { try await Task.sleep(for: .seconds(timeoutSeconds)) } catch { return nil }
  onAbort?()
  return nil
  ```
- `Storage/MediaDetailStore.swift` (~L277-285, `delegate.cancelAll()`) has the same pattern. Fix it the same way.

### 4. Missing cancellation guard after sleep (low)
- `fichier/Features/VideoPlayer/VideoTrackManager.swift:136`: `try? await Task.sleep(50ms)` then `playerItem.select(...)` with no `Task.isCancelled` check.
- `FichierKit/Sources/AMSMB2Client.swift:516`: sleep inside a loop. Verify the loop exits on cancellation.

### 5. Untracked background work (low–medium)
- `VideoPlayerController.swift` (~L201): the folder-icon thumbnail `Task` is not cancelled on stop. An SMB download continues after the player closes.
  - **Fix:** store it and cancel it in teardown.
- `StorageLocationManager.swift` (~L266): `Task.detached` runs the cache sweep on backgrounding with no `beginBackgroundTask`. The sweep may be suspended halfway.
  - **Fix:** wrap it in a background task assertion.

### 6. Stale UI state if a task is cancelled and not replaced (low)
- `fichier/Features/Connection/MediaBrowserSplitView.swift` (~L211): `connectingLocationID` is only reset after `selectLocation` returns uncancelled.
- **Fix:** cancel `connectionTask` and clear `connectingLocationID` in `onDisappear`.

### 7. Few `deinit` or teardown cancellations (low)
- Only 4 `deinit`s exist in the code base.
- `VideoPlayerController` stores several tasks (`loadTask` and the seek and HUD tasks), and I found no `deinit` cancelling them.
- Most closures use `[weak self]`, so this leaks work, not memory.
- **Fix:** confirm `stop()` or `cleanup()` cancels them all, and add explicit teardown where it doesn't.

## `try?` triage (89 sites)
- **Benign (~60):** `try? await Task.sleep` and `try? FileManager.removeItem` cleanups. Leave them. For the sleeps, the only risk is the missing guards in findings 3 and 4.
- **Acceptable but silent:** `resourceValues`, `Data(contentsOf:)` and thumbnail generation return `nil` and the UI falls back. Optionally add a debug-level log.
- **Add a log (failure invisible today):**
  - `FichierKit/Storage/MediaCacheManager.swift:69-71` (`createDirectory` of cache directories)
  - `fichier/Features/Gallery/MediaGridViewModel.swift:553` (`fetchVideoURL`)
  - `fichier/Features/Gallery/FolderPickerSheetView.swift:315` (`fetchSubfoldersForPicker`)
  - `AMSMB2Client` `disconnectShare` calls (L174, L579, L600)
- **Style:** `Diagnostics/CrashReporting.swift:65` uses `(try? NSRegularExpression(pattern: "$^")) ?? NSRegularExpression()`. It is valid (never-matching), but clearer as a static constant.

Use the existing privacy-safe logging (Wappn). Mark paths and hosts as private.

---

# Suggested order
1. Part B findings 1 and 2 (real behavior risks), with tests.
2. Finding 3.
3. Findings 4, 5, 6 and 7 (small cleanups).
4. `try?` logging.
5. Part A splits, one file at a time (`StorageLocationManager`, then `SMBClientActor`, `TVVLCPlayerEngine`, `MediaGridView`).

# Final report must include
Files changed, build and test results (iOS, tvOS, FichierKit), any behavior changes, and findings skipped or deferred.
