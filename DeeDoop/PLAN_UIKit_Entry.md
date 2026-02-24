# Plan: Switch to UIKit App Entry for Full-Screen Content

## Goal
Make the app use the **entire screen** (no black bars) by controlling the window and root view controller from UIKit. The root view will report **zero safe area**, so the SwiftUI content receives the full window frame.

## Current state
- **Entry**: SwiftUI `@main struct DeeDoopApp: App` with `WindowGroup { ContentView() }`
- **Problem**: The system creates a `UIHostingController` and gives its view a frame respecting safe area, so content is inset and black bars appear.
- **Existing code**: `FullScreenHostingViewController` (zero safe-area container + embedded SwiftUI) and `SceneDelegate` (unused after revert) are already in the project.

## Approach: Legacy UIKit lifecycle (no scenes)

Use the **legacy app delegate lifecycle** (no `UIApplicationSceneManifest`). The app delegate owns the single window and sets the root view controller. This avoids scene lifecycle and SwiftUI window creation.

---

## Step-by-step plan

### 1. App entry point
- **Add** `AppDelegate.swift` with:
  - `class AppDelegate: UIResponder, UIApplicationDelegate`
  - `@main` (replaces SwiftUI App as entry point)
  - `var window: UIWindow?` (required so the system keeps the window)
  - `application(_:didFinishLaunchingWithOptions:) -> Bool`:
    - Create `window = UIWindow(frame: UIScreen.main.bounds)`
    - `window?.rootViewController = FullScreenHostingViewController()`
    - `window?.backgroundColor = .systemBackground`
    - `window?.makeKeyAndVisible()`
    - Move **UINavigationBar appearance** setup here (from `DeeDoopApp.init()`)
    - Return `true`

### 2. Remove SwiftUI App
- **Remove** `@main` from `DeeDoopApp` and **delete** the entire `DeeDoopApp.swift` file (or replace its contents with a minimal stub if something else references it; nothing does).
- No other code references `DeeDoopApp`; all UI is reached via `ContentView` from `FullScreenHostingViewController`.

### 3. Info.plist
- **Leave as-is**: no `UIApplicationSceneManifest`. The app will use the legacy lifecycle and call `AppDelegate.application(didFinishLaunchingWithOptions:)`.

### 4. FullScreenHostingViewController
- **Keep** as-is. It already:
  - Uses `ZeroSafeAreaView` (reports `safeAreaInsets == .zero`)
  - Embeds `UIHostingController(rootView: RootSwiftUIView())`
  - Pins the hosting view to the container’s edges (full bounds)
  - `RootSwiftUIView` wraps `ContentView()` with background and `onAppear` (window background)
- **Remove** the `FullScreenHostingView` SwiftUI wrapper (no longer needed; we don’t use `WindowGroup`).

### 5. SceneDelegate
- **Delete** `SceneDelegate.swift` (not used in legacy lifecycle) and remove it from the Xcode project.

### 6. Xcode project (project.pbxproj)
- **Add** `AppDelegate.swift` to the DeeDoop target (Sources + file reference in DeeDoop group).
- **Remove** `DeeDoopApp.swift` from the target and from the project (or delete the file and remove references).
- **Remove** `SceneDelegate.swift` from the target and from the project.

### 7. What stays the same
- All SwiftUI views: `ContentView`, `PhotosFlowView`, `DocumentsFlowView`, `AppHeaderView`, etc. **Unchanged.**
- `ContentView` and the rest of the app logic are still used from `RootSwiftUIView` inside `FullScreenHostingViewController`.
- Navigation, sheets, and existing behavior remain the same.

### 8. Edge cases
- **Status bar**: Content draws under the status bar (full screen). If text/buttons are too close to the notch, we can add safe-area padding inside SwiftUI later.
- **Orientation**: Window and root VC rotate normally.
- **Single window**: Legacy lifecycle gives one window; sufficient for this app.

---

## File summary

| Action   | File |
|----------|------|
| **Create** | `AppDelegate.swift` (@main, window, didFinishLaunching, nav bar setup) |
| **Delete** | `DeeDoopApp.swift` |
| **Delete** | `SceneDelegate.swift` |
| **Edit**   | `FullScreenHostingViewController.swift` (remove `FullScreenHostingView` if desired; optional) |
| **Edit**   | `project.pbxproj` (add AppDelegate, remove DeeDoopApp, remove SceneDelegate) |
| **No change** | `Info.plist`, all other Swift files |

---

## Execution order
1. Create `AppDelegate.swift`.
2. Update `project.pbxproj`: add AppDelegate, remove DeeDoopApp and SceneDelegate.
3. Delete `DeeDoopApp.swift` and `SceneDelegate.swift`.
4. Optionally clean up `FullScreenHostingViewController.swift` (remove `FullScreenHostingView`).
5. Build and run.
