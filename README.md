# DeeDoop

Find duplicates on your iPhone — photos, videos, and (coming soon) files and contacts.

## Overview

DeeDoop scans your photo library for duplicate photos and videos based on **file size** and **creation date**. When duplicates are found, you choose which to keep and which to remove.

## Technology

- **SwiftUI** — Modern declarative UI
- **PhotoKit** — Photo library access and metadata
- **Combine** — Reactive state management
- **iOS 16+**

## Flow

1. **Select asset type** — Photos & Videos (Files and Contacts coming soon)
2. **Select date range** — Limit the scan to a specific period
3. **Scan** — The app finds duplicates by matching file size + creation date
4. **Review & remove** — For each group of duplicates:
   - **Remove duplicates** — Select one to keep, delete the rest
   - **Keep all** — Do nothing and move on

## Project Structure

```
DeeDoop/
├── DeeDoopApp.swift          # App entry point
├── ContentView.swift         # Asset type selection
├── Models/
│   ├── AssetType.swift       # Photos, Files, Contacts
│   └── DuplicateGroup.swift  # Group of duplicate assets
├── Services/
│   └── PhotoLibraryService.swift  # PhotoKit, scan, delete
├── Views/
│   ├── PhotosFlowView.swift       # Photos flow container
│   ├── DateRangeStepView.swift    # Date range picker
│   ├── ScanResultsView.swift      # Results list / scanning / empty
│   ├── DuplicateGroupDetailView.swift  # Pick which to keep
│   └── AssetThumbnailView.swift   # PHAsset thumbnail
├── Assets.xcassets
└── Info.plist
```

## Requirements

- Xcode 15+
- iOS 16+
- Device or Simulator with photo library access

## Setup

1. Open `DeeDoop.xcodeproj` in Xcode
2. **Set your development team:** Select the **DeeDoop** project in the navigator (blue icon), select the **DeeDoop** target, open the **Signing & Capabilities** tab, enable **Automatically manage signing**, then choose your **Team** from the dropdown.  
   If no team appears, add your Apple ID: **Xcode → Settings → Accounts → + → Apple ID**.
3. Select your device or simulator
4. Build and run (⌘R)

## Permissions

The app needs **Photo Library** access (read and write) to scan for duplicates and remove them when you choose. The usage description is in `Info.plist`.

## License

MIT
