import Foundation
import XCTest
@testable import CleanMyMac

final class UninstallSafetyTests: XCTestCase {
    func testBlockedCandidateCannotBeRemoved() {
        let candidate = UninstallCandidate(
            id: "blocked",
            name: "Example",
            path: "/Applications/Example.app",
            canonicalPath: "/Applications/Example.app",
            category: .application,
            size: 1,
            evidence: "测试",
            risk: .blocked,
            resourceIdentifier: "id",
            isApplicationBundle: true,
            owningBundleIdentifier: nil,
            scanWarning: "应用当前正在运行",
            isSelected: false
        )

        XCTAssertFalse(candidate.canRemove)
    }

    func testOnlyAppsDirectlyInsideAllowedApplicationsRootsAreAccepted() {
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true)]
        XCTAssertTrue(UninstallPathPolicy.isApplicationBundle(URL(fileURLWithPath: "/Applications/Example.app"), allowedRoots: roots))
        XCTAssertFalse(UninstallPathPolicy.isApplicationBundle(URL(fileURLWithPath: "/Applications/Folder/Example.app"), allowedRoots: roots))
        XCTAssertFalse(UninstallPathPolicy.isApplicationBundle(URL(fileURLWithPath: "/System/Applications/Example.app"), allowedRoots: roots))
    }

    func testUserLibraryCandidateExcludesPersonalFolders() {
        XCTAssertTrue(UninstallPathPolicy.isUserLibraryCandidate(URL(fileURLWithPath: "/Users/tester/Library/Caches/com.example.app"), homeDirectory: "/Users/tester"))
        XCTAssertFalse(UninstallPathPolicy.isUserLibraryCandidate(URL(fileURLWithPath: "/Users/tester/Documents/file.txt"), homeDirectory: "/Users/tester"))
        XCTAssertFalse(UninstallPathPolicy.isUserLibraryCandidate(URL(fileURLWithPath: "/Users/other/Library/Caches/com.example.app"), homeDirectory: "/Users/tester"))
    }

    func testSymbolicLinkIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = root.appendingPathComponent("target.app", isDirectory: true)
        let link = root.appendingPathComponent("link.app", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(UninstallPathPolicy.isSymbolicLink(link))
        XCTAssertFalse(UninstallPathPolicy.isApplicationBundle(link, allowedRoots: [root]))
    }
}
