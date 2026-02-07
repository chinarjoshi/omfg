# OMFG Architecture

Minimal org-mode daily notes app with swipe navigation and syncthing sync.

## Structure

```
OMFG/
├── App/
│   ├── AppDelegate.swift      # App entry point
│   └── SceneDelegate.swift    # Window management, editor↔settings transitions
├── Editor/
│   ├── EditorViewController.swift  # Main editor with swipe navigation
│   ├── OrgTextStorage.swift        # Syntax highlighting for org-mode
│   ├── OrgSyntaxRules.swift        # Highlighting rules
│   └── AutoSaveController.swift    # Debounced file writes
├── Navigation/
│   ├── NavigationState.swift       # NoteLevel enum + current state
│   └── NotePathResolver.swift      # File paths, date math, titles
├── Settings/
│   └── SettingsViewController.swift
├── Sync/
│   ├── SyncEngine.swift            # Syncthing wrapper
│   └── FileWatcher.swift           # External file change detection
├── DailyNote/
│   └── DailyNoteManager.swift
└── Storage/
    └── ConfigStore.swift           # UserDefaults wrapper
```

## Navigation

**Swipe left/right** → next/previous date
**Swipe down** → daily → weekly → monthly → settings
**Swipe up** → settings → monthly → weekly → daily

Uses `UISwipeGestureRecognizer` on main view for all directions.

## Note Hierarchy

```
Documents/
├── daily/2026-02-02.org
├── weekly/2026-W05.org
└── monthly/2026-02.org
```

`NotePathResolver` handles all path generation and date arithmetic.

## Key Patterns

- **No protocols** - closures for callbacks (`onRequestSettings`)
- **No animation** - instant transitions (except settings fade)
- **Minimal state** - `NavigationState` is just level + date
- **Direct file I/O** - no database, just .org files

## Iteration Flow

Build, deploy, and launch on connected iPhone:

```bash
# Build
xcodebuild -scheme OMFG -sdk iphoneos -configuration Debug -derivedDataPath build 2>&1 | tail -5

# Find device ID
xcrun devicectl list devices

# Deploy and launch (replace DEVICE_ID with actual ID from above)
xcrun devicectl device install app --device DEVICE_ID build/Build/Products/Debug-iphoneos/OMFG.app && \
xcrun devicectl device process launch --device DEVICE_ID com.omfg.app
```

Current device ID: `4A8E1A19-36ED-5D17-91F1-1BF187CC2D1C`

One-liner for rapid iteration:
```bash
xcodebuild -scheme OMFG -sdk iphoneos -configuration Debug -derivedDataPath build 2>&1 | tail -5 && \
xcrun devicectl device install app --device 4A8E1A19-36ED-5D17-91F1-1BF187CC2D1C build/Build/Products/Debug-iphoneos/OMFG.app 2>&1 && \
xcrun devicectl device process launch --device 4A8E1A19-36ED-5D17-91F1-1BF187CC2D1C com.omfg.app 2>&1
```
