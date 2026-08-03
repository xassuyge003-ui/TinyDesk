import AppKit

enum DesktopCardWindowPolicy {
    // Cards remain visible across regular desktop spaces, but must not cover another app in full screen.
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenNone,
        .stationary,
    ]
}
