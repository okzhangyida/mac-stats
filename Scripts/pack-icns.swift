#!/usr/bin/swift
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: pack-icns.swift ICONSET_DIR OUTPUT_ICNS\n", stderr)
    exit(2)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let entries: [(String, String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png")
]

func bigEndianBytes(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}

var chunks = Data()
for (type, filename) in entries {
    let png = try Data(contentsOf: iconset.appendingPathComponent(filename))
    chunks.append(type.data(using: .ascii)!)
    chunks.append(bigEndianBytes(UInt32(png.count + 8)))
    chunks.append(png)
}

var result = Data("icns".utf8)
result.append(bigEndianBytes(UInt32(chunks.count + 8)))
result.append(chunks)
try result.write(to: output, options: .atomic)
