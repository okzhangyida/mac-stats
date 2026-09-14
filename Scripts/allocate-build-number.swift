#!/usr/bin/env swift

import Foundation

struct PlatformMappings: Codable {
    let macOSCFBundleVersion: String
}

struct Allocation: Codable {
    let build: String
    let productVersion: String
    let allocatedAt: String
    let purpose: String
    let platformMappings: PlatformMappings
}

struct LegacyBuild: Codable {
    let build: String
    let productVersion: String
    let releasedAt: String
}

struct BuildRecord: Codable {
    let schemaVersion: Int
    let project: String
    let legacyBuilds: [LegacyBuild]
    var allocations: [Allocation]
    var current: Allocation?
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail("usage: allocate-build-number.swift <product-version> <purpose>")
}

let productVersion = CommandLine.arguments[1]
let purpose = CommandLine.arguments[2].trimmingCharacters(in: .whitespacesAndNewlines)
guard !productVersion.isEmpty, !purpose.isEmpty else {
    fail("product version and purpose must not be empty")
}

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let projectURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let buildDirectoryURL = projectURL.appendingPathComponent("Build", isDirectory: true)
let recordURL = buildDirectoryURL.appendingPathComponent("build-numbers.json")
let lockURL = buildDirectoryURL.appendingPathComponent(".build-number.lock", isDirectory: true)
let fileManager = FileManager.default

do {
    try fileManager.createDirectory(at: lockURL, withIntermediateDirectories: false)
} catch {
    fail("another build-number allocation is in progress; remove \(lockURL.path) only if it is stale")
}
defer { try? fileManager.removeItem(at: lockURL) }

let decoder = JSONDecoder()
let recordData: Data
do {
    recordData = try Data(contentsOf: recordURL)
} catch {
    fail("could not read \(recordURL.path): \(error.localizedDescription)")
}

var record: BuildRecord
do {
    record = try decoder.decode(BuildRecord.self, from: recordData)
} catch {
    fail("invalid build-number record: \(error.localizedDescription)")
}

guard record.schemaVersion == 1 else { fail("unsupported build-number schema") }

var calendar = Calendar(identifier: .gregorian)
guard let timeZone = TimeZone(identifier: "Asia/Shanghai") else { fail("Asia/Shanghai time zone is unavailable") }
calendar.timeZone = timeZone
let now = Date()
let components = calendar.dateComponents([.year, .month, .day], from: now)
guard let year = components.year, let month = components.month, let day = components.day else {
    fail("could not determine the current Beijing date")
}

let datePrefix = String(format: "%04d%02d%02d", year, month, day)
let previousSequence: Int
if let lastBuild = record.allocations.last?.build, lastBuild.hasPrefix(datePrefix + ".") {
    previousSequence = Int(lastBuild.split(separator: ".").last ?? "0") ?? 0
} else {
    previousSequence = 0
}
let sequence = previousSequence + 1
guard sequence <= 99 else { fail("build-number sequence for \(datePrefix) has reached 99") }

let build = String(format: "%@.%02d", datePrefix, sequence)
guard !record.allocations.contains(where: { $0.build == build }) else { fail("build \(build) is already allocated") }

let macOSMajor = (year % 100) * 100 + month
let macOSBuild = "\(macOSMajor).\(day).\(sequence)"
let timestampFormatter = DateFormatter()
timestampFormatter.calendar = calendar
timestampFormatter.locale = Locale(identifier: "en_US_POSIX")
timestampFormatter.timeZone = timeZone
timestampFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"

let allocation = Allocation(
    build: build,
    productVersion: productVersion,
    allocatedAt: timestampFormatter.string(from: now),
    purpose: purpose,
    platformMappings: PlatformMappings(macOSCFBundleVersion: macOSBuild)
)
record.allocations.append(allocation)
record.current = allocation

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
do {
    var output = try encoder.encode(record)
    output.append(0x0A)
    try output.write(to: recordURL, options: .atomic)
} catch {
    fail("could not update build-number record: \(error.localizedDescription)")
}

print(build)
print("macOS CFBundleVersion: \(macOSBuild)")
