import CryptoKit
import Foundation

public enum SourceIdentityPolicy: String, Codable, CaseIterable, Sendable {
    case sha256
    case fast
}

public struct SourceIdentity: Codable, Sendable, Equatable {
    public var policy: SourceIdentityPolicy
    public var sha256: String

    public init(policy: SourceIdentityPolicy, sha256: String) {
        self.policy = policy
        self.sha256 = sha256
    }
}

public enum SourceIdentityCalculator {
    private static let chunkSize = 4 * 1024 * 1024
    private static let streamingChunkSize = 1024 * 1024

    public static func compute(
        for url: URL,
        policy: SourceIdentityPolicy,
        fileManager: FileManager = .default
    ) throws -> SourceIdentity {
        switch policy {
        case .sha256:
            return SourceIdentity(policy: .sha256, sha256: try fullFileDigest(for: url))
        case .fast:
            return SourceIdentity(policy: .fast, sha256: try fastDigest(for: url, fileManager: fileManager))
        }
    }

    private static func fullFileDigest(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            guard let chunk = try handle.read(upToCount: streamingChunkSize), !chunk.isEmpty else {
                break
            }
            hasher.update(data: chunk)
        }
        return hexString(hasher.finalize())
    }

    private static func fastDigest(for url: URL, fileManager: FileManager) throws -> String {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let size = fileSize(from: attributes)
        let modifiedAt = modificationDate(from: attributes)
        let first = try digestForRange(in: url, offset: 0, length: min(Int64(chunkSize), size))
        let lastOffset = max(Int64(0), size - Int64(chunkSize))
        let last = try digestForRange(in: url, offset: lastOffset, length: min(Int64(chunkSize), size))

        var hasher = SHA256()
        update(&hasher, "aisidecar-source-identity-fast-v1\n")
        update(&hasher, "size:\(size)\n")
        update(&hasher, "modified_at_ns:\(nanosecondsSinceEpoch(modifiedAt))\n")
        update(&hasher, "first_4m_sha256:\(first)\n")
        update(&hasher, "last_4m_sha256:\(last)\n")
        return hexString(hasher.finalize())
    }

    private static func digestForRange(in url: URL, offset: Int64, length: Int64) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: Int(length)) ?? Data()
        return hexString(SHA256.hash(data: data))
    }

    private static func update(_ hasher: inout SHA256, _ string: String) {
        hasher.update(data: Data(string.utf8))
    }

    private static func fileSize(from attributes: [FileAttributeKey: Any]) -> Int64 {
        if let size = attributes[.size] as? NSNumber {
            return size.int64Value
        }
        return 0
    }

    private static func modificationDate(from attributes: [FileAttributeKey: Any]) -> Date {
        attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
    }

    private static func nanosecondsSinceEpoch(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000_000_000).rounded(.towardZero))
    }

    private static func hexString<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
