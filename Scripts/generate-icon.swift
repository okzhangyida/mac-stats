#!/usr/bin/swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    fputs("usage: generate-icon.swift APP_PNG MENUBAR_PNG MENUBAR_2X_PNG\n", stderr)
    exit(2)
}

func writePNG(_ image: NSImage, to path: String) throws {
    guard let tiff = image.tiffRepresentation,
          let representation = NSBitmapImageRep(data: tiff),
          let png = representation.representation(using: .png, properties: [:])
    else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: URL(fileURLWithPath: path), options: .atomic)
}

func drawGauge(center: NSPoint, radius: CGFloat, color: NSColor, lineWidth: CGFloat) {
    let arc = NSBezierPath()
    arc.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: 20,
        endAngle: 160,
        clockwise: false
    )
    arc.lineWidth = lineWidth
    arc.lineCapStyle = .round
    color.setStroke()
    arc.stroke()

    let angle = CGFloat.pi * 0.30
    let needleEnd = NSPoint(
        x: center.x + cos(angle) * radius * 0.72,
        y: center.y + sin(angle) * radius * 0.72
    )
    let needle = NSBezierPath()
    needle.move(to: center)
    needle.line(to: needleEnd)
    needle.lineWidth = lineWidth
    needle.lineCapStyle = .round
    needle.stroke()

    let hubRadius = lineWidth * 0.72
    let hub = NSBezierPath(ovalIn: NSRect(
        x: center.x - hubRadius,
        y: center.y - hubRadius,
        width: hubRadius * 2,
        height: hubRadius * 2
    ))
    color.setFill()
    hub.fill()
}

func appIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 1024, height: 1024))
    image.lockFocus()
    NSGraphicsContext.current?.cgContext.setShouldAntialias(true)

    let background = NSBezierPath(
        roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960),
        xRadius: 220,
        yRadius: 220
    )
    NSColor(red: 0.04, green: 0.46, blue: 0.96, alpha: 1).setFill()
    background.fill()

    drawGauge(
        center: NSPoint(x: 512, y: 410),
        radius: 300,
        color: .white,
        lineWidth: 54
    )
    image.unlockFocus()
    return image
}

func menuBarIcon(scale: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: 18 * scale, height: 18 * scale))
    image.lockFocus()
    NSGraphicsContext.current?.cgContext.setShouldAntialias(true)
    drawGauge(
        center: NSPoint(x: 9 * scale, y: 6.8 * scale),
        radius: 6.2 * scale,
        color: .black,
        lineWidth: 1.65 * scale
    )
    image.unlockFocus()
    return image
}

try writePNG(appIcon(), to: CommandLine.arguments[1])
try writePNG(menuBarIcon(scale: 1), to: CommandLine.arguments[2])
try writePNG(menuBarIcon(scale: 2), to: CommandLine.arguments[3])
