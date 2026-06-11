#!/usr/bin/env swift

import Foundation

let scriptURL = URL(
    fileURLWithPath: CommandLine.arguments[0],
    relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
).standardizedFileURL
let repoRoot = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["swift", "run", "aisidecar", "benchmark"] + Array(CommandLine.arguments.dropFirst())
process.currentDirectoryURL = repoRoot

do {
    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
} catch {
    FileHandle.standardError.write(Data("benchmark wrapper failed: \(error)\n".utf8))
    exit(1)
}
