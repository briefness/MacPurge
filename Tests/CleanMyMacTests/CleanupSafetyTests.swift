import Foundation
import XCTest
@testable import CleanMyMac

final class CleanupSafetyTests: XCTestCase {
    func testRejectsProtectedRootsAndSystemDirectories() {
        let home = "/Users/tester"

        XCTAssertNotNil(CleanupPathPolicy.unsafeReason(for: "/", homeDirectory: home))
        XCTAssertNotNil(CleanupPathPolicy.unsafeReason(for: home, homeDirectory: home))
        XCTAssertNotNil(CleanupPathPolicy.unsafeReason(for: "\(home)/Documents", homeDirectory: home))
        XCTAssertNotNil(CleanupPathPolicy.unsafeReason(for: "/System/Library/Caches", homeDirectory: home))
        XCTAssertNotNil(CleanupPathPolicy.unsafeReason(for: "/private/var/folders", homeDirectory: home))
    }

    func testAllowsSpecificCacheDirectoryInsideUserLibrary() {
        XCTAssertNil(
            CleanupPathPolicy.unsafeReason(
                for: "/Users/tester/Library/Caches/npm",
                homeDirectory: "/Users/tester"
            )
        )
    }

    func testRejectsCandidateInsideProtectedPath() {
        let reason = CleanupPathPolicy.protectionReason(
            for: "/Users/tester/Projects/app/.build",
            protectedPaths: ["/Users/tester/Projects/app"]
        )

        XCTAssertNotNil(reason)
    }

    func testRejectsCandidateContainingProtectedChild() {
        let reason = CleanupPathPolicy.protectionReason(
            for: "/Users/tester/Projects/app",
            protectedPaths: ["/Users/tester/Projects/app/keep"]
        )

        XCTAssertNotNil(reason)
    }

    func testRejectsOtherUserHomePaths() {
        XCTAssertNotNil(
            CleanupPathPolicy.unsafeReason(
                for: "/Users/another-user/Documents/file.txt",
                homeDirectory: "/Users/tester"
            )
        )
    }

    func testRootProtectionCoversDescendants() {
        XCTAssertNotNil(
            CleanupPathPolicy.protectionReason(
                for: "/Users/tester/Projects/app/build",
                protectedPaths: ["/"]
            )
        )
    }

    func testRejectsMissingPath() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path

        XCTAssertEqual(
            CleanupPathPolicy.validationFailure(
                for: missing,
                scannedCanonicalPath: nil,
                scannedResourceIdentifier: nil,
                protectedPaths: []
            ),
            "路径已不存在"
        )
    }

    func testRejectsSymbolicLink() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        let link = root.appendingPathComponent("link", isDirectory: true)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? fileManager.removeItem(at: root) }

        XCTAssertEqual(
            CleanupPathPolicy.validationFailure(
                for: link.path,
                scannedCanonicalPath: nil,
                scannedResourceIdentifier: nil,
                protectedPaths: []
            ),
            "路径是符号链接"
        )
    }

    func testRejectsGlobMetaInUserSuppliedPath() {
        XCTAssertTrue(CleanupPathPolicy.containsGlobMeta("/Users/tester/Work[old]"))
        XCTAssertTrue(CleanupPathPolicy.containsGlobMeta("/Users/tester/Work*"))
        XCTAssertFalse(CleanupPathPolicy.containsGlobMeta("/Users/tester/Work"))
    }

    func testRejectsResourceIdentifierMismatch() throws {
        let fileManager = FileManager.default
        let file = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/CleanMyMacTests-\(UUID().uuidString)")
        XCTAssertTrue(fileManager.createFile(atPath: file.path, contents: Data("data".utf8)))
        defer { try? fileManager.removeItem(at: file) }

        XCTAssertEqual(
            CleanupPathPolicy.validationFailure(
                for: file.path,
                scannedCanonicalPath: CleanupPathPolicy.canonicalPath(file.path),
                scannedResourceIdentifier: "不是当前文件的资源标识",
                protectedPaths: []
            ),
            "文件在扫描后已被替换"
        )
    }

    func testRejectsWhenCurrentResourceIdentifierCannotBeRead() throws {
        let fileManager = FileManager.default
        let file = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/CleanMyMacTests-\(UUID().uuidString)")
        XCTAssertTrue(fileManager.createFile(atPath: file.path, contents: Data("data".utf8)))
        defer { try? fileManager.removeItem(at: file) }

        XCTAssertEqual(
            CleanupPathPolicy.validationFailure(
                for: file.path,
                scannedCanonicalPath: CleanupPathPolicy.canonicalPath(file.path),
                scannedResourceIdentifier: "扫描时的标识",
                protectedPaths: [],
                resourceIdentifierProvider: { _ in nil }
            ),
            "无法确认文件身份，已停止清理"
        )
    }
}
