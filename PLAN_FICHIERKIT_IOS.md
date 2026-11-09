# FichierKit Integration Plan for iOS

## Objective

Update the iOS app to use the existing `FichierKit` package while preserving current behavior, the existing architecture, and tvOS compatibility.

The tvOS target already imports and uses `FichierKit extensively. The iOS target currently has no `import FichierKit` references, so the migration should reuse the package abstractions already proven by the tvOS implementation.

## Constraints

- Limit changes to the iOS package integration.
- Preserve the current tvOS implementation and target behavior.
- Use Swift concurrency with async/await.
- Preserve actor isolation and MainActor correctness.
- Avoid unnecessary Combine usage, force unwraps, global mutable state, and unrelated refactors.
- Preserve stable identities for SwiftUI collections and navigation.
- Keep iOS-specific UI and playback adapters where FichierKit does not provide platform-specific behavior.

## Implementation Phases

### 1. Audit the Existing Integration

Inspect the public FichierKit API and the tvOS call sites to identify:

- Media models and identifiers.
- Media source and storage protocols.
- SMB connection and discovery abstractions.
- Thumbnail and media-loading services.
- Caching and persistence interfaces.
- Video and photo playback abstractions.
- Platform availability and conditional compilation requirements.

Map the corresponding iOS implementations and call sites before editing.

### 2. Verify Package and Target Configuration

Confirm that:

- FichierKit is declared as an Xcode package dependency.
- The FichierKit product is linked to the iOS app target.
- Package platform requirements are compatible with the iOS deployment target.
- Required transitive dependencies are available to iOS.
- tvOS target membership and package linkage remain unchanged.

### 3. Establish the Migration Boundary

Migrate shared domain and service abstractions first:

- Media item and media source models.
- Storage location models.
- SMB connection protocols and services.
- Media loading and thumbnail interfaces.
- Cache and persistence protocols where applicable.

Keep iOS-only view adapters, UIKit bridges, AVFoundation integration, and other platform-specific code in the app unless FichierKit explicitly provides a compatible replacement.

### 4. Migrate the iOS Data Flow

For each migration area:

1. Add `import FichierKit` only where required.
2. Replace duplicate iOS models or services with FichierKit equivalents.
3. Adapt existing dependency injection and constructors.
4. Preserve actor boundaries and MainActor ownership.
5. Preserve cancellation behavior and loading-state cleanup.
6. Prevent stale asynchronous requests from updating current UI state.
7. Preserve existing error mapping and user-facing behavior.

Avoid broad rewrites of working architecture.

### 5. Integrate iOS Media Presentation

Connect the existing iOS features to FichierKit types and services:

- Gallery browsing.
- Media grids and lists.
- Thumbnail loading.
- Photo viewing.
- Video detail and playback flows.
- Navigation destinations.
- Favorites and persistence, if represented by FichierKit.

Retain iOS-specific presentation and playback implementations where necessary. Do not introduce tvOS focus or remote-control behavior into iOS-only code.

### 6. Handle iOS and tvOS Differences

Use conditional compilation only when the platform APIs genuinely differ.

Verify:

- Availability annotations.
- Deployment-target compatibility.
- Actor isolation across targets.
- Swift concurrency annotations.
- Media playback differences.
- SwiftUI navigation and focus behavior.
- tvOS package consumers remain source-compatible.

### 7. Add or Update Tests

Use Swift Testing for unit tests and XCUIAutomation for UI tests.

Add focused coverage for:

- Conversion between existing app types and FichierKit types.
- Media source loading.
- SMB connection and failure handling.
- Thumbnail loading and cancellation.
- Cache hits, misses, and invalidation.
- Persistence behavior.
- Stale request protection.
- Loading-state cleanup after success, failure, and cancellation.
- iOS gallery, photo viewer, and video-player flows where behavior changes.

Reuse protocol-based test doubles where possible.

### 8. Validate Incrementally

After each migration area:

- Refresh focused Xcode diagnostics.
- Build the relevant iOS target.
- Run affected unit tests.
- Review compiler warnings and concurrency diagnostics.

After all changes:

- Build the iOS scheme.
- Build the tvOS scheme.
- Run affected iOS unit and UI tests.
- Run affected tvOS tests.
- Review the final diff for unrelated changes.
- Verify package resolution and target linkage in Xcode.

## Recommended Migration Order

1. Package and target configuration.
2. Shared models and protocols.
3. Storage and SMB networking.
4. Thumbnail and media loading.
5. Gallery and navigation.
6. Photo viewer.
7. Video playback.
8. Persistence and favorites.
9. Tests, diagnostics, and cleanup.

## Risks to Monitor

- FichierKit APIs may have stricter Sendable or actor-isolation requirements than the existing iOS code.
- Existing iOS models may not have stable identity semantics required by FichierKit or SwiftUI.
- Package platform availability may differ between iOS and tvOS.
- Migrating cache or persistence ownership could cause duplicate loads or stale data.
- Async tasks tied to view lifecycle may outlive the view unless cancellation is preserved.
- Video playback may require an iOS-specific adapter even if the media model is shared.
- Changes to shared package types may affect tvOS compilation even when only iOS files are edited.

## Completion Criteria

The migration is complete when:

- The iOS target successfully links and imports FichierKit where needed.
- iOS uses FichierKit shared models and services instead of duplicate implementations.
- Existing iOS browsing, thumbnail, photo, video, networking, and persistence behavior remains functional.
- tvOS builds without regressions.
- Focused iOS and tvOS tests pass.
- Cancellation, stale-result protection, actor isolation, and loading-state cleanup are verified.
- The final diff contains no unrelated refactors.
