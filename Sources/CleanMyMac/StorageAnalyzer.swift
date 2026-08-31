import Foundation

struct AnalyzerEntry: Identifiable, Hashable, Sendable {
    var id: String { canonicalPath }
    let name: String
    let path: String
    let canonicalPath: String
    let resourceIdentifier: String?
    let size: Double
    let isDirectory: Bool
    let isTruncated: Bool
    let isProtected: Bool

    var canMoveToTrash: Bool { !isTruncated && !isProtected && resourceIdentifier != nil }
}

struct AnalyzerSnapshot: Sendable {
    let path: String
    let entries: [AnalyzerEntry]
    let isTruncated: Bool
}

enum StorageAnalyzerError: LocalizedError {
    case missing
    case notDirectory
    case unreadable

    var errorDescription: String? {
        switch self {
        case .missing: "目录不存在或已经被移动"
        case .notDirectory: "所选路径不是文件夹"
        case .unreadable: "当前账号无法读取这个目录"
        }
    }
}

enum StorageAnalyzer {
    private static let maxVisitedEntries = 200_000
    private static let maxMeasurementDuration: TimeInterval = 5
    private static let maxScanDuration: TimeInterval = 30

    static func scan(path: String, protectedPaths: [String], fileManager: FileManager = .default) throws -> AnalyzerSnapshot {
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory) else { throw StorageAnalyzerError.missing }
        guard isDirectory.boolValue else { throw StorageAnalyzerError.notDirectory }
        guard fileManager.isReadableFile(atPath: expanded) else { throw StorageAnalyzerError.unreadable }

        let root = URL(fileURLWithPath: expanded).standardizedFileURL
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey,
            .fileAllocatedSizeKey, .fileSizeKey, .fileResourceIdentifierKey,
            .volumeIdentifierKey
        ]
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) else { throw StorageAnalyzerError.unreadable }

        let rootVolume = (try? root.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier
        let deadline = Date().addingTimeInterval(maxScanDuration)
        var scanTruncated = false
        var entries: [AnalyzerEntry] = []
        for url in children {
            if Task.isCancelled || Date() >= deadline {
                scanTruncated = true
                break
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                entries.append(AnalyzerEntry(
                    name: url.lastPathComponent,
                    path: displayPath(url.path),
                    canonicalPath: CleanupPathPolicy.canonicalPath(url.path),
                    resourceIdentifier: nil,
                    size: 0,
                    isDirectory: false,
                    isTruncated: true,
                    isProtected: true
                ))
                continue
            }
            guard values.isSymbolicLink != true else { continue }
            // A root scan must not recursively walk external or network volumes.
            // They can still be analyzed explicitly by selecting that volume.
            if root.path == "/", let rootVolume, let childVolume = values.volumeIdentifier,
               String(describing: childVolume) != String(describing: rootVolume) {
                continue
            }
            let measurement = measure(url: url, fileManager: fileManager)
            let canonical = CleanupPathPolicy.canonicalPath(url.path)
            let isProtected = CleanupPathPolicy.unsafeReason(for: canonical) != nil ||
                CleanupPathPolicy.protectionReason(for: canonical, protectedPaths: protectedPaths) != nil
            entries.append(AnalyzerEntry(
                name: url.lastPathComponent,
                path: displayPath(url.path),
                canonicalPath: canonical,
                resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
                size: Double(measurement.bytes) / 1_000_000_000,
                isDirectory: values.isDirectory == true,
                isTruncated: measurement.isTruncated,
                isProtected: isProtected
            ))
            if measurement.isTruncated { scanTruncated = true }
        }
        entries.sort {
            if $0.size == $1.size { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.size > $1.size
        }
        return AnalyzerSnapshot(path: displayPath(root.path), entries: entries, isTruncated: scanTruncated)
    }

    static func size(of url: URL, fileManager: FileManager = .default) -> (bytes: UInt64, isTruncated: Bool) {
        measure(url: url, fileManager: fileManager)
    }

    private static func measure(url: URL, fileManager: FileManager) -> (bytes: UInt64, isTruncated: Bool) {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileAllocatedSizeKey, .fileSizeKey]) else {
            return (0, true)
        }
        guard values.isDirectory == true else {
            return (UInt64(values.fileAllocatedSize ?? values.fileSize ?? 0), false)
        }

        var bytes: UInt64 = 0
        var visited = 0
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .fileSizeKey, .volumeIdentifierKey],
            options: []
        ) else { return (0, true) }
        let rootVolume = (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier
        let deadline = Date().addingTimeInterval(maxMeasurementDuration)
        for case let child as URL in enumerator {
            if Task.isCancelled { return (bytes, true) }
            visited += 1
            if visited > maxVisitedEntries || Date() >= deadline { return (bytes, true) }
            guard let childValues = try? child.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .fileSizeKey, .volumeIdentifierKey
            ]) else {
                return (bytes, true)
            }
            if childValues.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if let rootVolume, let childVolume = childValues.volumeIdentifier,
               String(describing: childVolume) != String(describing: rootVolume) {
                enumerator.skipDescendants()
                return (bytes, true)
            }
            guard childValues.isDirectory != true else { continue }
            bytes += UInt64(childValues.fileAllocatedSize ?? childValues.fileSize ?? 0)
        }
        return (bytes, false)
    }

    private static func displayPath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~", options: [.anchored])
    }
}
