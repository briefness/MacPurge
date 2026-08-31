import Foundation

enum UninstallCandidateCategory: String, CaseIterable, Sendable {
    case application = "应用本体"
    case support = "应用支持数据"
    case cache = "缓存"
    case preferences = "偏好设置"
    case state = "保存的状态"
    case logs = "日志"
    case container = "沙盒容器"
    case webData = "网页数据"
    case loginItem = "登录项与后台组件"
    case uncertain = "待确认项目"

    var symbol: String {
        switch self {
        case .application: "app.fill"
        case .support: "folder.fill"
        case .cache: "bolt.fill"
        case .preferences: "slider.horizontal.3"
        case .state: "clock.arrow.circlepath"
        case .logs: "doc.text.fill"
        case .container: "shippingbox.fill"
        case .webData: "globe"
        case .loginItem: "power"
        case .uncertain: "questionmark.folder"
        }
    }
}

enum UninstallRisk: String, Sendable {
    case safe = "安全删除"
    case review = "建议确认"
    case blocked = "无法删除"

    var tintName: String {
        switch self {
        case .safe: "mint"
        case .review: "orange"
        case .blocked: "red"
        }
    }
}

struct UninstallCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let canonicalPath: String
    let category: UninstallCandidateCategory
    let size: Double
    let evidence: String
    let risk: UninstallRisk
    let resourceIdentifier: String?
    let isApplicationBundle: Bool
    let scanWarning: String?
    var isSelected: Bool

    var canRemove: Bool { risk != .blocked && scanWarning == nil && resourceIdentifier != nil }
}

struct InstalledApplication: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let version: String
    let path: String
    let canonicalPath: String
    let size: Double
    let iconPath: String?
    let isRunning: Bool
    let isSystemApplication: Bool
    var candidates: [UninstallCandidate]
    var isExpanded: Bool

    var selectedCandidates: [UninstallCandidate] { candidates.filter(\.isSelected) }
    var selectedSize: Double { selectedCandidates.reduce(0) { $0 + $1.size } }
    var removableCount: Int { candidates.filter(\.canRemove).count }
    var reviewCount: Int { candidates.filter { $0.risk == .review }.count }
}

struct UninstallReport: Sendable {
    let reportURL: URL
    let movedCount: Int
    let movedSize: Double
    let failures: [String]
}
