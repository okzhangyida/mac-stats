import AppKit
import SwiftUI
import XCTest
@testable import MacStats

final class SettingsWindowTests: XCTestCase {
    @MainActor
    func testSettingsEntryReusesWindowAndRecreatesContentAfterClosing() throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let title = L10n.string("settings.window_title", fallback: "Mac Stats Settings")
        delegate.showSettingsWindow(nil)
        let first = try XCTUnwrap(NSApplication.shared.windows.first { $0.title == title && $0.isVisible })
        XCTAssertTrue(first.contentViewController is NSHostingController<SettingsView>)
        XCTAssertFalse(first.isRestorable)
        delegate.showSettingsWindow(nil)
        XCTAssertEqual(NSApplication.shared.windows.filter { $0.title == title && $0.isVisible }.count, 1)
        first.close()
        delegate.showSettingsWindow(nil)
        let reopened = try XCTUnwrap(NSApplication.shared.windows.first { $0.title == title && $0.isVisible })
        defer { reopened.close() }
        XCTAssertFalse(first === reopened)
        XCTAssertTrue(reopened.contentViewController is NSHostingController<SettingsView>)
    }
}
