import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MacStats

final class DesktopWallpaperRendererTests: XCTestCase {
    func testRoundedWallpaperCutsAllFourCorners() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacStatsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.png")
        let outputURL = directory.appendingPathComponent("output.png")
        try makeSolidImage(at: sourceURL, width: 120, height: 80)

        let request = DesktopAppearanceController.ProcessingRequest(
            sourceURL: sourceURL,
            outputURL: outputURL,
            pixelWidth: 120,
            pixelHeight: 80,
            menuBarHeight: 0,
            hideNotch: false,
            roundedCorners: true,
            cornerRadius: 16
        )
        let renderedURL = try DesktopAppearanceController.renderWallpaper(request)

        let image = try XCTUnwrap(CGImageSourceCreateWithURL(renderedURL as CFURL, nil)
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        for point in [(0, 0), (119, 0), (0, 79), (119, 79)] {
            let color = try pixel(in: image, x: point.0, y: point.1)
            XCTAssertTrue(color.red < 8 && color.green < 8 && color.blue < 8)
        }
        let center = try pixel(in: image, x: 60, y: 40)
        XCTAssertTrue(center.red > 240 && center.green > 240 && center.blue > 240)
    }

    private func makeSolidImage(at url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func pixel(in image: CGImage, x: Int, y: Int) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.translateBy(x: CGFloat(-x), y: CGFloat(y - image.height + 1))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (bytes[0], bytes[1], bytes[2])
    }
}
