import Foundation

enum CleanupRecommendation {
    static func shouldSelect(
        reviewLevel: String?,
        usesAgeRecommendation: Bool,
        modifiedAt: Date?,
        ageDays: Int,
        now: Date = .now
    ) -> Bool {
        let isSafeToRecommend = reviewLevel == "可重建" || reviewLevel == "低风险"
        guard isSafeToRecommend else { return false }
        if usesAgeRecommendation {
            guard let modifiedAt,
                  let cutoff = Calendar(identifier: .gregorian).date(
                    byAdding: .day,
                    value: -max(1, ageDays),
                    to: now
                  ) else { return false }
            return modifiedAt <= cutoff
        }
        return true
    }

    static func ageDescription(reviewLevel: String?, modifiedAt: Date?, ageDays: Int, now: Date = .now) -> String? {
        guard reviewLevel == "可重建" || reviewLevel == "低风险" else {
            return "需要人工确认，不会自动推荐"
        }
        guard let modifiedAt else { return nil }
        let days = max(0, Calendar(identifier: .gregorian).dateComponents([.day], from: modifiedAt, to: now).day ?? 0)
        return days >= ageDays ? "已闲置约 \(days) 天，符合推荐条件" : "约 \(days) 天内有更新，默认不选"
    }
}
