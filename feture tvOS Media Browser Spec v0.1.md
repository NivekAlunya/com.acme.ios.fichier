# tvOS Media Browser: Spec v0.1

## 1. Platform and stack
- tvOS 18+, SwiftUI only, root `NavigationStack`
- Players: AVPlayer and VLC (VLCKit on tvOS) behind one `PlayerEngine` protocol
- Shared Swift package for SMB logic and models (reused from the iOS app); tvOS views kept separate
- Pre-check: confirm the SMB library compiles for the tvOS target

## 2. Navigation
- **Root:** navigation bar with **Photos** and **Shares**.
  iCloud is out of v1 because `UIDocumentPickerViewController` is unavailable on tvOS.
- **Browser screen:** media and folders list, drilling down in the stack.
- **Detail:** image viewer or video player, pushed from the browser.

## 3. Sources
- Both implement a `MediaSource` protocol returning items that are a folder, an image, or a video.
  Each source declares its supported sort keys and preferred layout.
- **Photos:** PhotoKit (`PHPhotoLibrary`, `PHAsset`); albums act as folders.
- **Shares:** saved SMB servers (existing iOS feature), listed as cards; each opens into the browser.

## 4. Browser screen
- Grid for Photos, list for Shares.
- User-selectable sort (toolbar menu); folders always first; only keys the source supports.
- Lazy loading and paginated listing; thumbnails loaded on demand and cancelled when scrolled away.
- First item takes initial focus; focus is restored on return from a detail screen.

## 5. Remote mapping

| Input      | Image viewer           | Video player                                  |
|------------|------------------------|-----------------------------------------------|
| Left/right | Previous / next image  | Move focus (overlay visible)                  |
| Up/down    | Show / hide controls   | Move between progress row and buttons row     |
| Select     | Toggle overlay         | Activate focused control                      |
| Play/Pause | Start / stop slideshow | Play / pause (always works)                   |
| Menu       | Close viewer           | Cancel scrub, then hide overlay, then pop stack |

## 6. Video player interaction
- Custom overlay for both engines.
- Hidden overlay: the first directional press or Select only reveals it.
- Two rows: progress bar, and buttons (Previous, Play/Pause, Next, Tracks).
- Progress bar focused: left/right scrubs by a step with acceleration on hold;
  Select commits, Menu cancels; timestamp preview while scrubbing.
- Auto-hide after inactivity, never while paused or scrubbing.

## 7. Shares UI
- Server cards with name, host, status; trailing "Add server" card.
- Long-press or Play/Pause on a card opens Edit / Remove.
- Add/Edit as a full-screen form (`TextField`, `SecureField`), reusing the iOS form model.

## 8. Visual design
- System text styles, no fixed sizes; middle truncation for file names.
- `.card` style for grid cells and server cards; full-row highlight for list rows;
  custom focused state (scale plus fill) for overlay buttons.
- Photos grid: 4 columns, spacing of at least 40 pt. List rows about 100-120 pt tall.
- Dark and light support, blur or gradient behind the overlay, short spring animations,
  Reduce Motion respected, VoiceOver labels on all icon buttons.

## 9. States
- **Photos permission:** not determined shows an explanation screen with a request button;
  denied shows instructions to enable access in Settings;
  limited shows only the allowed assets, with a note.
- **Empty:** an empty folder or album shows a message and, in Shares, a Back action.
- **Errors:** unreachable server, bad credentials, and timeout each show a message with Retry.
  A file that fails to play shows an error in the player with Back;
  try the other engine (AVPlayer / VLC) before showing the error.
- **Loading:** skeleton or spinner for listings; buffering indicator in the player.

## 10. Open items
- Slideshow interval and transition style
- Resume-playback and subtitle/audio track menu design
- Whether to remember the last sort choice per source
- Acceptance criteria and test plan
