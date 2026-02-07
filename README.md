# omfg - Org Mode File Gossip

Minimal iOS app for editing daily org-mode notes with syncthing sync.

## Features

- Opens today's daily note (`daily/MM-DD.org`)
- Regex-based org-mode syntax highlighting (headers, TODO/DONE, links, bold, italic, timestamps)
- Auto-save with 500ms debounce
- External file change detection
- Syncthing sync in foreground only

## Build

### Prerequisites

- Xcode 15+ with iOS SDK
- Go 1.21+

### Setup Xcode

```bash
# Ensure full Xcode is selected (not Command Line Tools)
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### Build Go Framework (optional - app works without sync)

```bash
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest
make framework
```

### Build App

1. Open `OMFG.xcodeproj` in Xcode
2. If using syncthing: Add `Syncthing.xcframework` (Embed & Sign)
3. Build and run (Cmd+R)

## Project Structure

```
omfg/
├── go/libsyncthing/    # Go bindings (stub, ready for real syncthing)
├── OMFG/
│   ├── App/            # AppDelegate, SceneDelegate, Bootstrap
│   ├── Editor/         # OrgTextStorage, EditorViewController
│   ├── Sync/           # SyncEngine, FileWatcher
│   ├── DailyNote/      # DailyNoteManager
│   ├── Settings/       # SettingsViewController
│   └── Storage/        # ConfigStore, FileStore
└── OMFG.xcodeproj/
```

## Architecture

- **UIKit + TextKit**: NSTextStorage subclass for syntax highlighting
- **No storyboards**: Programmatic UI
- **Foreground sync**: Syncthing stops 3s after backgrounding
- **Last write wins**: Simple conflict resolution
