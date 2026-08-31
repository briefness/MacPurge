import Foundation
import XCTest
@testable import CleanMyMac

final class CleanupRecommendationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testOldProjectArtifactIsRecommended() {
        let modifiedAt = now.addingTimeInterval(-8 * 86_400)
        XCTAssertTrue(CleanupRecommendation.shouldSelect(
            reviewLevel: "可重建",
            usesAgeRecommendation: true,
            modifiedAt: modifiedAt,
            ageDays: 7,
            now: now
        ))
    }

    func testRecentProjectArtifactIsNotRecommended() {
        let modifiedAt = now.addingTimeInterval(-2 * 86_400)
        XCTAssertFalse(CleanupRecommendation.shouldSelect(
            reviewLevel: "可重建",
            usesAgeRecommendation: true,
            modifiedAt: modifiedAt,
            ageDays: 7,
            now: now
        ))
    }

    func testSharedLowRiskCacheDoesNotRequireAge() {
        XCTAssertTrue(CleanupRecommendation.shouldSelect(
            reviewLevel: "低风险",
            usesAgeRecommendation: false,
            modifiedAt: nil,
            ageDays: 7,
            now: now
        ))
    }

    func testAgeRecommendationDoesNotSelectItemsThatRequireReview() {
        let modifiedAt = now.addingTimeInterval(-30 * 86_400)
        XCTAssertFalse(CleanupRecommendation.shouldSelect(
            reviewLevel: "建议确认",
            usesAgeRecommendation: true,
            modifiedAt: modifiedAt,
            ageDays: 7,
            now: now
        ))
        XCTAssertFalse(CleanupRecommendation.shouldSelect(
            reviewLevel: "需确认",
            usesAgeRecommendation: true,
            modifiedAt: modifiedAt,
            ageDays: 7,
            now: now
        ))
    }
}
