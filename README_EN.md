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
| Notes | Multiple cards, editable title and body, placeholder alignment, autosave |
| Important dates | Calendar/list views, birthdays, anniversaries, holidays, one-time events, categories, age/year counts, local notifications |
| Todos | Editing, completion strikethrough, completed items sorted last, status filters, yesterday and overdue labels |
| Appearance | Five color themes plus frosted, transparent, and opaque surfaces per card |
| Layout | Small square, medium wide, and large square presets with free edge resizing |
| Desktop workflow | All Spaces, show/hide, reset position, position lock, menu bar control center |
| Privacy | App Sandbox, local JSON, no account, telemetry, analytics, or network requests |

## Project status

- Current version: `0.3.2` (build 8)
- Minimum system: macOS 14
- Stage: usable early release with a versioned workspace format and legacy migration
- Automated checks: 38 core model/persistence checks and an unsigned Xcode Debug build
- Manually verified: direct editing, window layering, size presets, themes, position locks, todo filters, and both important-date views

One 0.3.2 Release snapshot occupied approximately `4.7 MB`; idle RSS was about `139 MB`, and the
initial workspace was about `4 KB`. Actual memory and storage depend on macOS, card count, and content.

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

A free personal Apple ID is sufficient for local development. The repository currently distributes
source code only and does not provide a generally installable Developer ID-notarized binary.

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
- Drag an unlocked card's header to move it, or drag an edge to resize it.
- The important-date header provides calendar/list switching, category filtering, and event creation.
- Use the lock icon or a card/control-center menu to prevent accidental movement. Locking does not disable editing or resizing.
- Cards remain below normal application windows while they have editing focus.

Important dates support one-time or yearly recurrence, start years for ages and anniversaries, and
notifications on the date or 1, 3, or 7 days beforehand. Notification permission is requested only
after a reminder is enabled.

Completed todos receive a strikethrough and move below pending items. Filters show all, pending, or
completed tasks; unfinished tasks scheduled for yesterday or earlier receive overdue labels.

## Data and privacy

TinyDesk contains no account system, analytics SDK, ads, cloud sync, or network content. Data is stored at:

```text
~/Library/Containers/com.kai.tinydesk/Data/Library/Application Support/TinyDesk/workspace.json
```

The control center can reveal this directory in Finder. Saves use atomic replacement; an unreadable
workspace is preserved as a timestamped corrupt backup before defaults are created. Back up
`workspace.json` before removing the app container.

Notifications are scheduled locally with `UNUserNotificationCenter`; date content is not sent to a
third party. See [SECURITY.md](./SECURITY.md) for the security policy.

## Known limitations

- TinyDesk does not appear in the macOS WidgetKit gallery; this enables true direct editing.
- There is no iCloud sync, import/export, or multi-user collaboration yet.
- No Developer ID-notarized binary is distributed; end users currently build with Xcode.
- Cards do not cover exclusive full-screen apps or float above normal applications.
- Lunar birthdays, leap-month rules, and system-calendar import are not implemented.

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
