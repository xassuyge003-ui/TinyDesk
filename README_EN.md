# TinyDesk

> Lightweight, free, local-first desktop cards for notes, important dates, and tasks on macOS.

[![CI](https://github.com/xassuyge003-ui/TinyDesk/actions/workflows/ci.yml/badge.svg)](https://github.com/xassuyge003-ui/TinyDesk/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

[中文](./README.md) · [Changelog](./CHANGELOG.md) · [Contributing](./CONTRIBUTING.md)

TinyDesk renders its interface with SwiftUI and hosts each card in an AppKit `NSPanel`. Unlike a
WidgetKit widget, it supports real text input, todo interactions, and date editing directly on the
desktop. It does not require App Groups, iCloud, or a paid Apple Developer Program membership.

Cards stay above desktop icons but below regular application windows. Content, appearance, size,
and position are saved automatically in the app sandbox.

## Features

| Area | Capabilities |
|---|---|
| Notes | Multiple cards, direct editing, text colors, bold, italic, underline, strikethrough, and autosave |
| Important dates | Calendar/list views, lunar birthdays and leap-month rules, system Calendar import/linking, recurrence, age/year counts, local notifications |
| Todos | Editing, completion strikethrough, completed items sorted last, status filters, yesterday and overdue labels |
| Appearance | Five color themes plus frosted, transparent, and opaque surfaces per card |
| Layout | Small square, medium wide, and large square presets with free edge resizing |
| Desktop workflow | All Spaces, show/hide, reset position, position lock, launch at login, global quick-note shortcut |
| Library | Three-pane long-document library with folders, tags, favorites, recents, trash, full-text search, rich text, and twelve Chinese paper themes |
| Import/export | RTF, RTFD, TXT, and Markdown import; RTF, RTFD, TXT, Markdown, and PDF export; complete ZIP backups |
| Privacy | App Sandbox, local JSON + SQLite, no account, telemetry, analytics, or network requests |

## Project status

- Current version: `2.5.0` (build 25)
- Minimum system: macOS 14
- Stage: usable early release with a versioned workspace format and legacy migration
- Automated checks: 76 core model/persistence checks plus ZIP/RTFD backup round-trip coverage; GitHub Actions builds a universal DMG for every release tag
- Key flows covered: direct editing, window layering, size presets, themes, position locks, todo filters, both important-date views, and lunar conversion

Memory and storage depend on macOS, card count, and rich-text content. The workspace remains local to the app sandbox.

## Requirements

- macOS 14 Sonoma or later
- Xcode 15 or later
- Swift 5.9 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Generated `.xcodeproj` files are intentionally not committed. `project.yml` is the source of truth.

## Run from source

```bash
git clone https://github.com/xassuyge003-ui/TinyDesk.git
cd TinyDesk

# If Homebrew is available
brew install xcodegen

xcodegen generate
open TinyDesk.xcodeproj
```

In Xcode:

1. Select the `TinyDesk` scheme and `My Mac`.
2. Open the target's **Signing & Capabilities** settings.
3. Select your Personal Team. If the bundle identifier conflicts, change it in `project.yml` and regenerate the project.
4. Press `⌘R`.

A free personal Apple ID is sufficient for local development; no paid entitlement is required.

## Install the DMG

Every tag matching the `Info.plist` version publishes a universal `TinyDesk-x.y.z.dmg` and its SHA-256 file on
[GitHub Releases](https://github.com/xassuyge003-ui/TinyDesk/releases).

### Version downloads

| Version | Highlights | Download |
|---|---|---|
| V2.5.0 | Latest: desktop cards plus the document library, full-text search, import/export, and Chinese paper themes | [Release notes and DMG](https://github.com/xassuyge003-ui/TinyDesk/releases/tag/v2.5.0) |
| V2.0.0 | Lunar birthdays, system Calendar integration, launch at login, and quick notes | [Release](https://github.com/xassuyge003-ui/TinyDesk/releases/tag/v2.0.0) · [DMG](https://github.com/xassuyge003-ui/TinyDesk/releases/download/v2.0.0/TinyDesk-2.0.0.dmg) |
| V1.1.1 | Stable rich-text note release | [Release](https://github.com/xassuyge003-ui/TinyDesk/releases/tag/v1.1.1) · [ZIP](https://github.com/xassuyge003-ui/TinyDesk/releases/download/v1.1.1/TinyDesk-v1.1.1-macOS-universal.zip) |
| V1.0.0 | First public baseline | [Release](https://github.com/xassuyge003-ui/TinyDesk/releases/tag/v1.0.0) · [ZIP](https://github.com/xassuyge003-ui/TinyDesk/releases/download/v1.0.0/TinyDesk-v1.0.0-macOS-universal.zip) |

Previous releases, binaries, source snapshots, and release notes remain available and are not replaced by newer versions. Back up local data before downgrading.

1. Open the DMG and drag `TinyDesk.app` to Applications.
2. For the first launch, Control-click `TinyDesk.app`, choose **Open**, and confirm the macOS prompt.
3. The free build is ad-hoc signed, not Developer ID-notarized. The prompt reflects that signing boundary; no card data is uploaded.

To build and verify your own image:

```bash
./scripts/build-dmg.sh
```

Artifacts are written to `dist/`; the script verifies the universal executable and its signature and writes a SHA-256 file.

### Command-line verification

```bash
cd TinyDeskCore
swift run TinyDeskSelfTests
cd ..

xcodegen generate
xcodebuild \
  -project TinyDesk.xcodeproj \
  -scheme TinyDesk \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Usage

The first launch creates one note, important-date, and todo card and opens the control center. After
closing the control center, TinyDesk remains available from the menu bar. From there you can create,
locate, show, hide, resize, recolor, lock, reset, or delete cards.

- Click note and todo text directly to edit it.
- Select note text and use the formatting bar for color, bold, italic, underline, strikethrough, or clearing styles.
- Drag an unlocked card's header to move it, or drag an edge to resize it.
- The important-date header provides calendar/list switching, category filtering, and event creation.
- Use the lock icon or a card/control-center menu to prevent accidental movement. Locking does not disable editing or resizing.
- Cards remain below normal application windows while they have editing focus.
- Use the menu-bar **Quick Note** action or the configurable global shortcut (default `⌥⌘N`) to create a note at the top center of the active screen. Its header can unpin it; regular cards remain on the desktop layer.
- The control center's top-right **Settings** button controls launch at login and the quick-note shortcut locally.

Important dates support one-time or yearly recurrence, start years for ages and anniversaries, and
notifications on the date or 1, 3, or 7 days beforehand. They can use Gregorian or Chinese lunar dates.
For a leap-month birthday, the default celebrates the same regular lunar month in years without that
leap month; strict mode skips those years. Notification permission is requested only after a reminder is enabled.

The important-date card's Calendar button opens system Calendar integration. After the user grants Calendar
permission, selected calendars can be imported. Imported events keep Calendar as the source for title, date,
and recurrence while TinyDesk keeps local category, pin, and reminder choices. A local event can instead be
exported to a writable calendar and then written back on sync. Unlinking stops sync without deleting either copy.
To avoid silently changing event semantics, import accepts only one-time and yearly system events; Calendar continues to manage weekly, monthly, and other rules.

Completed todos receive a strikethrough and move below pending items. Filters show all, pending, or
completed tasks; unfinished tasks scheduled for yesterday or earlier receive overdue labels.

### Document library

Open **Library** from the control center or menu bar. Its left pane contains folders, tags, favorites,
recents, and trash; the middle pane lists matching documents; the right pane is a rich-text editor.
Use `⌘N` to create a document, `⌘⇧O` to import, `⌘⇧E` to export, and `⌘F` to search titles,
body text, tags, and folders. Twelve paper themes apply consistently to all three panes and the
formatting toolbar. Documents are stored as RTFD packages, while metadata and FTS5 indexes use SQLite.

## Data and privacy

TinyDesk contains no account system, analytics SDK, ads, cloud sync, or network content. Plain note
text, rich-text formatting, important dates, todos, and layout data are stored at:

```text
~/Library/Containers/com.kai.tinydesk/Data/Library/Application Support/TinyDesk/workspace.json
```

The control center can reveal this directory in Finder. Saves use atomic replacement; an unreadable
workspace is preserved as a timestamped corrupt backup before defaults are created. Back up
`workspace.json` before removing the app container.

Library metadata, full-text indexes, and RTFD documents are stored separately at:

```text
~/Library/Containers/com.kai.tinydesk/Data/Library/Application Support/TinyDesk/Library/library.db
~/Library/Containers/com.kai.tinydesk/Data/Library/Application Support/TinyDesk/Library/documents/
```

Notifications are scheduled locally with `UNUserNotificationCenter`; date content is not sent to a
third party. Calendar permission is requested only for a user-initiated import, link, or sync and is used through local EventKit. See [SECURITY.md](./SECURITY.md) for the security policy.

## Known limitations

- TinyDesk does not appear in the macOS WidgetKit gallery; this enables true direct editing.
- There is no iCloud sync, general workspace import/export, or multi-user collaboration yet; selected system Calendar linking is the exception.
- The DMG is ad-hoc signed, not Developer ID-notarized; Finder confirmation is required on the first launch.
- Cards do not cover exclusive full-screen apps or float above normal applications.
- Calendar account sharing and conflict resolution remain managed by macOS Calendar; TinyDesk does not merge cloud conflicts.
- v1.0.0, v1.1.1, and v2.0.0 remain downloadable. Older versions do not understand later data fields, so back up the workspace and library before downgrading.

## Architecture

```text
Menu bar / Control center / Desktop cards (SwiftUI)
                         │
              DesktopWindowManager (AppKit)
                         │
              DesktopWorkspaceStore (JSON)
                         │
              TinyDeskCore (Foundation only)
```

`TinyDeskCore` owns models, date rules, todo ordering, and workspace migration without depending on
SwiftUI or AppKit. The app target owns windows, input, persistence, and local notifications. See
[Architecture](./docs/ARCHITECTURE.md) and the [desktop card guide](./docs/DESKTOP_CARD_GUIDE.md).

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](./CONTRIBUTING.md), the
[Code of Conduct](./CODE_OF_CONDUCT.md), and [SECURITY.md](./SECURITY.md) before participating.

## License

TinyDesk is available under the [MIT License](./LICENSE).
