# Fichier Application PR Review Resolution Plan

## Objective

Resolve the valid review findings for the Fichier application while preserving iOS and tvOS compatibility, strict Swift 6 concurrency, existing dependency injection, and the workspace no-commit rule.

Some fixes require a coordinated API change in the local FichierKit package.

## Review Assessment

### 1. `activeClient()` Sendable boundary — not confirmed

The review flags:

```swift
func activeClient() -> (any SMBClientProtocol)?
```

as a possible Swift 6 actor-boundary violation.

However, the current FichierKit declaration is:

```swift
public protocol SMBClientProtocol: Sendable
```

Therefore, an existential conforming to `SMBClientProtocol` is already constrained to Sendable values. The current iOS and tvOS builds also compile successfully with Swift 6.

Resolution:

- Keep the existing return type unless a compiler diagnostic demonstrates otherwise.
- Do not add redundant `& Sendable` composition without a concrete compiler requirement.
- Add a focused compile/build verification for all current `activeClient()` consumers.
- Keep `SMBClientProtocol: Sendable` documented and enforced in FichierKit.

### 2. Concrete `AMSMB2Client` coupling — confirmed

`SMBClientActor` currently disconnects only when the stored client can be cast to `AMSMB2Client`:

```swift
if let amsmbClient = client as? AMSMB2Client {
    await amsmbClient.disconnect()
}
```

This bypasses teardown for injected test doubles and any future FichierKit client implementation.

### 3. `Int.max` directory fetches — valid scalability concern

The app passes `pageSize: Int.max` for shares and directory scans.

This is a real risk for large directories. However, the current FichierKit `SharesMediaSource` implementation calls `listDirectory` first and only applies `pageSize` after the complete directory result has already been loaded and sorted. Merely replacing `Int.max` with a smaller number would reduce the mapped result but would not fully solve network-side or package-side allocation.

The resolution must therefore address both:

- App-level result limits and incremental UI loading.
- FichierKit-level directory enumeration and pagination semantics.

### 4. Missing mock disconnect coverage — confirmed

The app already injects actor-backed `MockSMBClient) instances through `SMBClientActor`, but teardown behavior is not verified because the protocol has no disconnect requirement and the production actor uses a concrete cast.

## Resolution Plan

### Phase 1 — Add protocol-level disconnect support in FichierKit

Coordinate with the FichierKit package:

1. Add `func disconnect() async` to `SMBClientProtocol`.
2. Keep `SMBClientProtocol: Sendable`.
3. Preserve `AMSMB2Client.disconnect()` as the production implementation.
4. Update all FichierKit conformers and test doubles.
5. Keep disconnect idempotent and safe when no connection is active.
6. Avoid changing the public API beyond the required protocol requirement.

After the package API is updated, update the app dependency to the corresponding local package state.

### Phase 2 — Remove concrete-client teardown casts

File:

- `fichier/Core/Networking/SMBClientActor.swift`

Replace concrete casts in:

- `connectAndListShares`
- `disconnect`
- Failed connection cleanup

with protocol dispatch:

```swift
await client?.disconnect()
```

Required behavior:

1. Disconnect the previous client before replacing it.
2. Disconnect a newly created client when share enumeration fails.
3. Ensure cleanup occurs on cancellation and errors.
4. Clear actor state and caches consistently.
5. Preserve the existing actor isolation boundary.
6. Do not log or persist plaintext passwords.

### Phase 3 — Strengthen dependency-injection tests

Files:

- `fichierTests/Mocks/MockSMBClient.swift`
- Existing SMB connection and folder-loading test files.
- Add a dedicated test file if a separate teardown double is needed.

Add coverage proving:

1. A mock client injected through `clientFactory` receives `disconnect()` when `SMBClientActor.disconnect()` is called.
2. The previous mock client is disconnected when a new connection replaces it.
3. A failed share enumeration disconnects the newly created mock client.
4. Cancellation and failure paths clear connection state and loading state.
5. No behavior depends on `AMSMB2Client) concrete casting.
6. Existing stale-result and cancellation tests continue to pass.

The mock should use actor-isolated call tracking or another Swift 6-safe mechanism. Avoid shared mutable global state, force unwraps, and `try!`.

### Phase 4 — Establish bounded directory loading

First, define the desired UI behavior:

- Initial share/folder loads should use a bounded page size.
- Additional pages should load explicitly as the user reaches the end of a list/grid.
- Loading state, cancellation, stale requests, and sort order must remain correct.
- Folder navigation must not replace current results with stale pages.

Use stable media identities when appending pages.

For shares:

1. Replace `Int.max` with a bounded page size.
2. Consider shares a small control-plane list, but still avoid unbounded app-level mapping.
3. Preserve deterministic sorting and root-share behavior.

For directory contents:

1. Do not only replace `Int.max` in the app and assume the problem is solved.
2. Add or extend a FichierKit directory-pagination abstraction so the package does not materialize the entire directory before paging.
3. Prefer a page-oriented API that accepts:
   - share
   - path
   - page/cursor
   - page size
   - sort requirements where supported
4. If the SMB backend cannot provide server-side pagination, define a bounded streaming or incremental enumeration contract in FichierKit.
5. Keep sorting semantics explicit. If global sorting requires all items, document that limitation or move sorting into the package's incremental strategy.
6. Preserve folder-first ordering and existing media classification.

Potential implementation choices should be evaluated before coding:

- Page-based protocol method returning bounded arrays.
- Async sequence of directory entries with app-side bounded accumulation.
- Package-owned directory cache/index with incremental reads.

Choose the smallest approach that actually bounds memory rather than only bounding the final mapped array.

### Phase 5 — Migrate app call sites

Update:

- `SMBClientActor.connectAndListShares`
- `SMBClientActor.refreshShares`
- `SMBClientActor.scanFolder`
- Any `StorageLocationManager) methods that load or append folder pages.
- Any gallery views that trigger pagination.

Requirements:

1. Remove `pageSize: Int.max) from UI-facing scans.
2. Use explicit bounded page sizes.
3. Track the current page or cursor per folder identity.
4. Cancel outstanding page requests when changing folders or disconnecting.
5. Reject stale page results.
6. Keep `isLoading` and error state consistent on success, failure, and cancellation.
7. Avoid duplicate items when a page is retried.
8. Preserve stable `MediaItem.id) values across pages.
9. Keep iOS and tvOS behavior compatible.

### Phase 6 — Verify the Sendable boundary

Do not change `activeClient()` solely based on the review suggestion.

Verify:

1. FichierKit continues to declare `SMBClientProtocol: Sendable`.
2. The app builds with Swift 6 strict concurrency.
3. `activeClient()` consumers remain valid from MainActor and nonisolated helper contexts.
4. Streaming delegates receive only Sendable client values.
5. No non-Sendable state is captured by detached tasks or escaping callbacks.

If Xcode produces a concrete diagnostic, apply the narrowest fix at the diagnosed boundary.

### Phase 7 — Validation

Run without committing:

1. Fichier iOS build.
2. Fichier iOS unit tests.
3. FichierTV tvOS build.
4. FichierTV tests.
5. FichierKit package build and package tests on iOS.
6. Focused dependency-injection and disconnect tests.
7. Focused pagination, stale-result, and cancellation tests.
8. `swiftlint --strict` for the app if configured.
9. `git diff --check` in both repositories.
10. Review all changed files for:
    - actor-isolation warnings
    - Sendable violations
    - force unwraps
    - `try!`
    - plaintext credential logging
    - unbounded result accumulation
    - stale page mutation
11. Leave all changes uncommitted for user review.

## Acceptance Criteria

- The app no longer depends on concrete `AMSMB2Client` casts for cleanup.
- Injected clients receive deterministic disconnect calls.
- Failed and cancelled connections clean up correctly.
- `SMBClientProtocol) remains Sendable and all Swift 6 boundaries compile cleanly.
- No unnecessary `activeClient()` type change is introduced.
- UI-facing share and directory loads no longer request `Int.max` pages.
- FichierKit enumeration is bounded or incrementally streamed rather than only truncated after full materialization.
- Pagination preserves stable identities, ordering, cancellation, and stale-result protection.
- iOS and tvOS builds and relevant tests pass.
- No credentials are logged or stored unexpectedly.
- No commits are created.
