import AppKit
import SwiftUI
import XCTest
@testable import MacStats

final class ViewRenderingTests: XCTestCase {
    @MainActor
    func testDashboardAndSettingsRenderInLightAndDarkModes() throws {
        let store = MonitorStore()

        try render(
            DashboardView(store: store, openSettingsAction: {}, openProcessesAction: {})
                .frame(width: 390, height: 590)
                .preferredColorScheme(.light),
            size: NSSize(width: 390, height: 590),
            name: "dashboard-light"
        )
        try render(
            DashboardView(store: store, openSettingsAction: {}, openProcessesAction: {})
                .frame(width: 390, height: 590)
                .preferredColorScheme(.dark),
            size: NSSize(width: 390, height: 590),
            name: "dashboard-dark"
        )
        try render(
            SettingsView(store: store)
                .frame(width: 500, height: 650)
                .preferredColorScheme(.light),
            size: NSSize(width: 500, height: 650),
            name: "settings-light"
        )
        try render(
            SettingsView(store: store)
                .frame(width: 500, height: 650)
                .preferredColorScheme(.dark),
            size: NSSize(width: 500, height: 650),
            name: "settings-dark"
        )
    }

    private func render<Content: View>(
        _ content: Content,
        size: NSSize,
        name: String
    ) throws {
        let view = NSHostingView(rootView: content)
        view.appearance = NSAppearance(named: name.hasSuffix("-dark") ? .darkAqua : .aqua)
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()

        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        XCTAssertGreaterThanOrEqual(representation.pixelsWide, Int(size.width))
        XCTAssertGreaterThanOrEqual(representation.pixelsHigh, Int(size.height))

        guard let directoryPath = ProcessInfo.processInfo.environment["MAC_STATS_SNAPSHOT_DIR"] else {
            return
        }
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("\(name).png")
        let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try png.write(to: outputURL, options: .atomic)
    }
}
