import SwiftUI
import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case overview, clean, uninstall, trash, analyze, optimize, protected, settings

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "总览"
        case .clean: "清理空间"
        case .uninstall: "应用卸载"
        case .trash: "废纸篓"
        case .analyze: "空间透镜"
        case .optimize: "优化维护"
        case .protected: "保护列表"
        case .settings: "设置"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: "一眼了解 Mac 状态"
        case .clean: "审核并释放空间"
        case .uninstall: "完整移除应用与残留"
        case .trash: "永久删除已丢弃项目"
        case .analyze: "查看空间都去哪了"
        case .optimize: "轻量系统维护"
        case .protected: "永不触碰的路径"
        case .settings: "扫描与应用偏好"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "sparkles"
        case .clean: "wand.and.stars"
        case .uninstall: "app.dashed"
        case .trash: "trash.fill"
        case .analyze: "chart.pie.fill"
        case .optimize: "gauge.with.dots.needle.67percent"
        case .protected: "checkmark.shield.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct CleanupGroup: Identifiable, Hashable {
    var id: String
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    var size: Double
    var itemCount: Int
    var isSelected: Bool
    var risk: String
}

struct CleanupItem: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var path: String
    var size: Double
    let reason: String
    var toolName: String?
    let artifactType: String?
    let reviewLevel: String?
    var canonicalPath: String?
    var resourceIdentifier: String?
    var scanWarning: String?
    var modifiedAt: Date?
    var usesAgeRecommendation: Bool
    var isSelected: Bool

    var canClean: Bool { scanWarning == nil }

    init(id: String, name: String, path: String, size: Double, reason: String, toolName: String? = nil, artifactType: String? = nil, reviewLevel: String? = nil, canonicalPath: String? = nil, resourceIdentifier: String? = nil, scanWarning: String? = nil, modifiedAt: Date? = nil, usesAgeRecommendation: Bool = false, isSelected: Bool) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
        self.reason = reason
        self.toolName = toolName
        self.artifactType = artifactType
        self.reviewLevel = reviewLevel
        self.canonicalPath = canonicalPath
        self.resourceIdentifier = resourceIdentifier
        self.scanWarning = scanWarning
        self.modifiedAt = modifiedAt
        self.usesAgeRecommendation = usesAgeRecommendation
        self.isSelected = isSelected
    }
}

struct CleanupSourceGroup: Identifiable {
    let id: String
    let sourceName: String
    let artifactGroups: [CleanupArtifactGroup]

    var items: [CleanupItem] { artifactGroups.flatMap(\.items) }
    var size: Double { items.reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter(\.isSelected).count }
    var reviewCount: Int {
        items.filter { item in
            guard let level = item.reviewLevel else { return false }
            return level != "可重建" && level != "低风险"
        }.count
    }
}

struct CleanupArtifactGroup: Identifiable {
    let id: String
    let artifactType: String
    let items: [CleanupItem]

    var size: Double { items.reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter(\.isSelected).count }
    var reviewCount: Int {
        items.filter { item in
            guard let level = item.reviewLevel else { return false }
            return level != "可重建" && level != "低风险"
        }.count
    }
}

struct StorageNode: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let size: Double
    let color: Color
}

struct TrashEntry: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let canonicalPath: String
    let resourceIdentifier: String?
    let size: Double
    let volumeName: String
    let isTruncated: Bool
    var isSelected: Bool

    var canDelete: Bool { !isTruncated && resourceIdentifier != nil }
}


enum PermissionState: String, Hashable {
    case available
    case needsAuthorization
    case notFound

    var title: String {
        switch self {
        case .available: "已覆盖"
        case .needsAuthorization: "需要授权"
        case .notFound: "未发现/不适用"
        }
    }

    var symbol: String {
        switch self {
        case .available: "checkmark.circle.fill"
        case .needsAuthorization: "lock.fill"
        case .notFound: "minus.circle"
        }
    }

    var tint: Color {
        switch self {
        case .available: .mint
        case .needsAuthorization: .orange
        case .notFound: .secondary
        }
    }
}

struct PermissionScope: Identifiable, Hashable {
    let id: String
    let title: String
    let path: String
    let detail: String
    let probePath: String
    let requiresFullDiskAccess: Bool
    var state: PermissionState = .notFound
}
