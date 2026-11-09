# tvOS Media Browser: Acceptance Criteria & Test Plan

**Application:** Fichier  
**Target:** Apple TV (tvOS 18+)  
**Architecture:** Pure Swift 6 Concurrency, SwiftUI-only, `NavigationStack`, Shared `FichierKit` Package  

---

## 1. Acceptance Criteria by Specification Section

### Section 1: Platform & Stack
- [ ] App targets tvOS 18.0+ exclusively.
- [ ] UI is 100% SwiftUI (custom `UIViewRepresentable` used solely for `AVPlayerLayer` control-less video rendering).
- [ ] Root container is a `NavigationStack` supporting deep pushing without unexpected app termination.
- [ ] Video engines conform to `PlayerEngine`: `AVPlayerEngine` (hardware accelerated) and `TVVLCPlayerEngine` (extended codec support via `VLCKit`).
- [ ] Shared data models, stores, and protocols reside in `FichierKit` package; tvOS views remain strictly in `FichierTV`.
- [ ] Strict 1 Definition = 1 File across both package and app targets.
- [ ] 100% clean build in Swift 6 concurrency mode (`-swift-version 6`) with zero concurrency warnings.

### Section 2: Root Navigation
- [ ] Top navigation bar presents segmented control for **Photos** and **Shares**.
- [ ] Selecting **Photos** navigates to albums and assets (no iCloud entry in v1).
- [ ] Selecting **Shares** navigates to saved SMB servers.
- [ ] Siri Remote **Menu** button never exits the app from a child browser or media viewer; it pops the navigation stack back to the root.

### Section 3: Sources
- [ ] Both sources conform to `MediaSource` returning items categorized as `.folder`, `.image`, or `.video`.
- [ ] **Photos Source (`PhotosMediaSource`):**
  - Uses PhotoKit (`PHPhotoLibrary`, `PHAsset`, `PHAssetCollection`).
  - System albums act as top-level folders.
  - Declares preferred layout `.grid` and supported sort keys `[.date, .name]`.
- [ ] **Shares Source (`SharesMediaSource`):**
  - Wraps SMB client protocol connecting to saved SMB servers.
  - Top-level listing presents share points as folders; sub-paths list remote files and directories.
  - Declares preferred layout `.list` and supported sort keys `[.name, .date, .size, .type]`.

### Section 4: Browser Screen
- [ ] **Layout:** Photos defaults to a 4-column grid (minimum 40 pt spacing) and Shares defaults to a vertical list (110 pt rows); users can switch any browser view between Grid and List via the toolbar Layout menu (`MediaLayoutPreferenceStoreProtocol` persists per source).
- [ ] **Thumbnails:** PhotoKit photos & videos (`PhotoThumbnailLoader`), local images & videos, and SMB images (`SMBImageLoader`) & videos (`SMBVideoThumbnailLoader` over `SMBStreamingServer` using `AVAssetImageGenerator` for native formats and `VLCVideoThumbnailActor` / `VLCKit` for extended containers) render bounded in-memory cached thumbnails in both Grid and List views.
- [ ] **Sorting:**
  - Toolbar menu exposes only keys advertised by `source.supportedSortKeys`.
  - Folders are strictly sorted first regardless of chosen sort key.
  - Ascending and Descending order toggling.
- [ ] **Pagination & Performance:**
  - Lazy loading in pages of 40 items.
  - Asynchronous thumbnail loading cancelled cooperatively when scrolled away or toggled across layouts without dropping sibling cell requests.
- [ ] **Focus Management:**
  - Initial focus lands on the first item in the collection (`defaultFocus` and first-load assignment).
  - Focus returns to the originating item when dismissing an image viewer or video player.

### Section 5: Siri Remote Input Mapping
- [ ] **Image Viewer:**
  - Left / Right: Displays previous / next image.
  - Up / Down: Shows / hides HUD overlay.
  - Select: Toggles HUD overlay visibility.
  - Play/Pause: Starts / pauses automated slideshow.
  - Menu: Closes overlay if open; otherwise dismisses viewer back to browser.
- [ ] **Video Player:**
  - Directional press (overlay hidden): Reveals overlay without moving focus or changing playback.
  - Directional Up / Down (overlay visible): Moves focus between Scrubber row and Buttons row.
  - Directional Left / Right (overlay visible, buttons row): Shifts focus across Previous, Play/Pause, Next, Tracks.
  - Directional Left / Right (overlay visible, progress row): Scrubs with step acceleration on hold (10s -> 30s -> 60s).
  - Select (scrubbing): Commits seek to target timestamp.
  - Select (buttons): Triggers focused action.
  - Play/Pause: Toggles playback immediately in any state.
  - Menu: Tiered cancellation (1. Cancel scrub -> 2. Hide overlay -> 3. Pop navigation stack).

### Section 6: Video Player Custom HUD
- [ ] Dual-row unified HUD overlay for both `AVPlayer` and `VLCKit`.
- [ ] Real-time progress bar with current timestamp, total duration, and scrubbing bubble preview.
- [ ] Inactivity auto-hide timer dismisses overlay after 5 seconds of untouched playback.
- [ ] Inactivity timer is suspended while video is paused or while scrubbing.

### Section 7: Shares UI
- [ ] Horizontal scroll shelf of focusable `.card` server items showing name, host, and live reachability badge (`.online`, `.offline`, `.connecting`).
- [ ] Trailing "Add Server" card.
- [ ] Long-press or Play/Pause on a server card presents an Action Sheet with "Edit Server" and destructive "Remove Server".
- [ ] Full-screen form (`TVServerFormView`) with `TextField` and `SecureField` for name, host, username, and password.

### Section 8: Visual Design & Accessibility
- [ ] System typography throughout (no fixed point sizes); file names use `.middle` truncation.
- [ ] `.card` button style applied to grid cells and server cards; full-row highlight for list items.
- [ ] Custom overlay button style: scale (1.12x) and white fill when focused.
- [ ] Blur and gradient backdrop behind overlays for legibility in light and dark modes.
- [ ] `accessibilityReduceMotion` respected: suppresses button scaling and switches slide transitions to smooth crossfades.
- [ ] VoiceOver accessibility labels on all icon buttons and scrubber values.

### Section 9: States & Failure Handling
- [ ] **Photos Permissions:**
  - Not determined: Explanatory screen with "Grant Access" button.
  - Denied / Restricted: Guidance to navigate to Apple TV Settings > Apps > Fichier.
  - Limited: Renders allowed assets with an informative banner.
- [ ] **Empty States:** Clear message; Shares includes a dedicated "Back" button.
- [ ] **Network Errors:** Unreachable server, authentication failure, and timeouts render specific messages with a "Retry" button.
- [ ] **Playback Failures:** Automatic fallback from `AVPlayerEngine` to `TVVLCPlayerEngine`; if both fail, renders error screen with "Back" and "Retry" options.
- [ ] **Loading:** Spinner for listing pagination; buffering indicator during video stalls.

### Section 10: Settings & Persistence
- [ ] Slideshow duration (2s, 3s, 4s, 5s, 10s) and transition style (Slide, Fade) persisted in `UserDefaults` via `DefaultSlideshowSettingsStore`.
- [ ] Video resume timestamps persisted in `UserDefaults` via `DefaultVideoPlaybackStore` (ignored under 10s, cleared within 15s of completion).
- [ ] Per-source sorting choices remembered in `UserDefaults` via `DefaultMediaSortPreferenceStore`.
- [ ] Per-source browser layout choices (`grid` / `list`) remembered in `UserDefaults` via `DefaultMediaLayoutPreferenceStore`.

---

## 2. Test Execution Plan

| Test ID | Area | Action / Scenario | Expected Outcome |
|---|---|---|---|
| **NAV-01** | Navigation | Press Menu on Siri Remote from Image Viewer | Overlay hides if visible; viewer pops to browser on second press; does NOT exit app. |
| **NAV-02** | Navigation | Press Menu on Siri Remote while scrubbing video | Scrubber cancels back to original timestamp; overlay remains; does NOT pop stack. |
| **PHT-01** | Photos | Launch app with `.notDetermined` permission | Permission request screen shown; clicking Grant Access invokes PhotoKit dialog. |
| **PHT-02** | Photos | Revoke permission in Settings (`.denied`) | Settings instruction screen shown ("Apple TV Settings > Apps > Fichier"). |
| **PHT-03** | Photos | Authorize with limited selection (`.limited`) | Top notification badge shown; only selected assets displayed in 4-column grid. |
| **SMB-01** | Shares | Add new SMB server with host and credentials | Server card appears with `.connecting` badge transitioning to `.online` or `.offline`. |
| **SMB-02** | Shares | Long-press or press Play/Pause on server card | Action dialog appears offering "Edit Server" and "Remove Server". |
| **BRW-01** | Browser | Scroll 4-column Photos grid | Lazy loading loads next 40 items when reaching bottom; offscreen thumbnails cancel. |
| **BRW-02** | Browser | Select sort by Date (Descending) | Source sorts newest items first; folders remain at the very top. |
| **BRW-03** | Browser | Exit folder and re-enter | Previously chosen sort key and order for that source are restored from persistence. |
| **BRW-04** | Browser | Switch Shares or Photos layout to Grid/List | Layout updates immediately, persists per source across folders, and reuses cached video/image thumbnails. |
| **IMG-01** | Image Viewer | Press Play/Pause button | Automated slideshow begins; overlay auto-hides; advances every 4 seconds. |
| **IMG-02** | Image Viewer | Open Slideshow Settings sheet | Changing interval to 10s and style to Fade persists; slides now crossfade every 10s. |
| **VID-01** | Video Player | Play video and do not touch remote for 5s | Controls HUD smoothly fades out; video continues playing. |
| **VID-02** | Video Player | Swipe Up or Down during playback | Controls HUD appears; inactivity timer resets to 5s. |
| **VID-03** | Video Player | Hold Right on Scrubber row | Scrubber begins at 10s increments, accelerating to 30s and 60s steps with preview bubble. |
| **VID-04** | Video Player | Play 45 seconds of video, exit to browser, reopen | Video automatically resumes at 45 seconds timestamp. |
| **VID-05** | Video Player | Play video to completion (within 15s of end) | Video finishes; resume timestamp is cleared; subsequent play starts at 00:00. |
| **VID-06** | Video Player | Open unsupported container (e.g. MKV/VLC) | AVPlayer reports failure; app automatically switches to VLCKit before reporting error. |
| **A11Y-01**| Accessibility | Enable Reduce Motion in Apple TV Settings | Focus scale effects are suppressed; image transitions switch from slide to crossfade. |
| **A11Y-02**| Accessibility | Enable VoiceOver on Apple TV | All icon buttons read concise descriptive labels and hints; scrubber reads percent progress. |
