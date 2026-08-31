import SwiftUI
import AppKit
import Foundation
import Darwin

func detailStorageSize(_ gigabytes: Double) -> String {
    let bytes = max(0, gigabytes) * 1_000_000_000
    if bytes >= 1_000_000_000 {
        return String(format: "%.2f GB", bytes / 1_000_000_000)
    }
    if bytes >= 1_000_000 {
        return String(format: "%.2f MB", bytes / 1_000_000)
    }
    if bytes >= 1_000 {
        return String(format: "%.2f KB", bytes / 1_000)
    }
    return String(format: "%.0f B", bytes)
}

@main
struct CleanMyMacApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1040, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu(ProductIdentity.displayName) {
                Button("扫描 Mac") { model.scan() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("清理已选项目") { model.requestClean() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}

private struct StorageRecord: Sendable {
    let name: String
    let detail: String
    let size: Double
}

private struct DirectoryMeasurement: Sendable {
    let bytes: UInt64
    let isTruncated: Bool
}

private struct CatalogScanResult: Sendable {
    let details: [String: [CleanupItem]]
    let wasLimited: Bool
}

private struct TrashDeletionOutcome: Sendable {
    let removedIDs: Set<String>
    let failures: [String]
}

private struct TrashScanResult: Sendable {
    let entries: [TrashEntry]
    let wasLimited: Bool
}

private struct AnalyzerMoveOutcome: Sendable {
    let errorMessage: String?
}

struct OptimizeTask: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    var selected: Bool
    var completed: Bool
}

private struct OptimizationSnapshot: Sendable {
    let memoryFreePercent: Int?
    let swapUsed: Double?
    let swapTotal: Double?
    let purgeableEstimate: Double?
    let uptime: TimeInterval
    let backgroundItemCount: Int
}

@MainActor
final class AppModel: ObservableObject {
    private struct ReportFailure: Error, Sendable {
        let message: String
    }

    private struct CleanupOutcome: Sendable {
        let reportURL: URL
        let movedIDs: Set<String>
        let movedSize: Double
        let failed: [String]
    }

    @Published var section: AppSection = .overview
    @Published var isScanning = false
    @Published var scanProgress = 0.0
    @Published var lastScan: Date?
    @Published var showCleanConfirmation = false
    @Published var isCleaning = false
    @Published var cleanupMessage: String?
    @Published var cleanupMessageIsError = false
    @Published var lastReportPath: String?
    @Published var isCheckingPermissions = false
    @Published var permissionMessage: String?
    @Published var scanMessage: String?
    @Published var pathNotice: String?
    @Published var optimizeMessage: String?
    @Published var hasScanned = false
    @Published var permissionScopes: [PermissionScope] = [
        .init(id: "user-cache", title: "用户缓存", path: "~/Library/Caches", detail: "缓存与可重建索引，基础扫描即可覆盖", probePath: "~/Library/Caches", requiresFullDiskAccess: false),
        .init(id: "developer", title: "开发者内容", path: "~/Library/Developer", detail: "Xcode、SwiftPM 与模拟器相关数据", probePath: "~/Library/Developer", requiresFullDiskAccess: false),
        .init(id: "downloads", title: "下载目录", path: "~/Downloads", detail: "用户主动下载的安装包和归档文件", probePath: "~/Downloads", requiresFullDiskAccess: false),
        .init(id: "app-data", title: "应用数据", path: "~/Library/Application Support", detail: "Cursor、LM Studio 等工具的本地数据", probePath: "~/Library/Application Support", requiresFullDiskAccess: false),
        .init(id: "system-wide", title: "系统保护范围", path: "受 macOS 保护的目录", detail: "仅用于空间分析和废纸篓读取，不读取邮件、消息或其他个人通信内容", probePath: "~/Library/Application Support/com.apple.TCC", requiresFullDiskAccess: true)
    ]
    @Published var groups: [CleanupGroup] = []
    @Published var cleanupDetails: [String: [CleanupItem]] = [:]
    @Published var storageNodes: [StorageNode] = []
    @Published var analyzerPath = "/"
    @Published var analyzerEntries: [AnalyzerEntry] = []
    @Published var isAnalyzing = false
    @Published var analyzerMessage: String?
    @Published var pendingAnalyzerTrash: AnalyzerEntry?
    @Published var showAnalyzerTrashConfirmation = false
    @Published var trashEntries: [TrashEntry] = []
    @Published var isScanningTrash = false
    @Published var trashMessage: String?
    @Published var showEmptyTrashConfirmation = false
    @Published var isDeletingTrash = false
    @Published var isMovingAnalyzerEntry = false
    @Published var optimizeTasks: [OptimizeTask] = []
    @Published var isOptimizing = false
    @Published var installedApplications: [InstalledApplication] = []
    @Published var isScanningApplications = false
    @Published var isUninstalling = false
    @Published var uninstallMessage: String?
    @Published var uninstallMessageIsError = false
    @Published var uninstallReportPath: String?
    @Published var uninstallWasLimited = false
    @Published var showUninstallConfirmation = false
    @Published var protectedPaths: [String] = []
    @Published var artifactRecommendationDays = 7 {
        didSet { UserDefaults.standard.set(artifactRecommendationDays, forKey: artifactRecommendationDaysKey) }
    }

    private var catalogGroups: [CleanupGroup] = []
    private var catalogDetails: [String: [CleanupItem]] = [:]
    private var scanTask: Task<Void, Never>?
    private var analyzerTask: Task<Void, Never>?
    private var trashScanTask: Task<Void, Never>?
    private var uninstallTask: Task<Void, Never>?
    private let protectedPathsKey = "cleanmymac.protectedPaths"
    private let artifactRecommendationDaysKey = "cleanmymac.artifactRecommendationDays"
    @Published private(set) var isRefreshingSystemData = false

    init() {
        catalogGroups = Self.catalogDefinitions()
        catalogDetails = Self.cleanupRules()
        optimizeTasks = Self.optimizeDefinitions()
        protectedPaths = UserDefaults.standard.stringArray(forKey: protectedPathsKey) ?? []
        let savedDays = UserDefaults.standard.integer(forKey: artifactRecommendationDaysKey)
        artifactRecommendationDays = savedDays > 0 ? min(savedDays, 30) : 7
        Task { @MainActor [weak self] in
            await self?.refreshSystemData()
        }
    }

    var selectedSize: Double { cleanupDetails.values.flatMap { $0 }.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var selectedItems: Int { cleanupDetails.values.flatMap { $0 }.filter(\.isSelected).count }
    var availablePermissionCount: Int { permissionScopes.filter { $0.state == .available }.count }
    var authorizationNeededCount: Int { permissionScopes.filter { $0.state == .needsAuthorization }.count }
    var detectedPermissionCount: Int { permissionScopes.filter { $0.state != .notFound }.count }
    var deepScopes: [PermissionScope] { permissionScopes.filter(\.requiresFullDiskAccess) }
    var deepAuthorizationNeeded: Bool { deepScopes.contains { $0.state == .needsAuthorization } }
    var isFilesystemBusy: Bool {
        isScanning || isCleaning || isAnalyzing || isScanningTrash || isDeletingTrash ||
        isMovingAnalyzerEntry || isOptimizing || isScanningApplications || isUninstalling
    }
    var selectedUninstallCandidates: [UninstallCandidate] {
        installedApplications.flatMap { $0.candidates }.filter { $0.isSelected && $0.canRemove }
    }
    var selectedUninstallSize: Double { selectedUninstallCandidates.reduce(0) { $0 + $1.size } }
    var selectedUninstallCount: Int { selectedUninstallCandidates.count }
    var uninstallReviewCount: Int { installedApplications.reduce(0) { $0 + $1.reviewCount } }
    @Published private(set) var diskUsed: Double?
    @Published private(set) var diskTotal: Double?
    @Published private(set) var memoryUsed: Double?
    @Published private(set) var memoryTotal: Double?
    @Published private(set) var memoryFreePercent: Int?
    @Published private(set) var swapUsed: Double?
    @Published private(set) var swapTotal: Double?
    @Published private(set) var purgeableEstimate: Double?
    @Published private(set) var systemUptime: TimeInterval = 0
    @Published private(set) var backgroundItemCount = 0

    var diskUsedText: String { diskUsed.map { String(format: "%.2f GB", $0) } ?? "未读取" }
    var diskTotalText: String { diskTotal.map { String(format: "共 %.2f GB", $0) } ?? "容量不可用" }
    var memoryUsedText: String { memoryUsed.map { String(format: "%.2f GB", $0) } ?? "未读取" }
    var memoryTotalText: String { memoryTotal.map { String(format: "共 %.2f GB", $0) } ?? "容量不可用" }
    var uptimeText: String {
        let days = Int(systemUptime / 86_400)
        let hours = Int(systemUptime.truncatingRemainder(dividingBy: 86_400) / 3_600)
        return days > 0 ? "\(days) 天 \(hours) 小时" : "\(hours) 小时"
    }
    var systemSummary: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #if arch(arm64)
        return "\(os) · Apple Silicon"
        #elseif arch(x86_64)
        return "\(os) · Intel"
        #else
        return os
        #endif
    }
    var availableDisk: Double? {
        guard let total = diskTotal, let used = diskUsed else { return nil }
        return max(0, total - used)
    }
    /// 扫描完成后展示实际检测到的权限覆盖比例，不代表系统健康评分。
    var scanCoverageScore: Int? {
        guard hasScanned else { return nil }
        guard detectedPermissionCount > 0 else { return nil }
        let coverage = Double(availablePermissionCount) / Double(detectedPermissionCount)
        return Int((coverage * 100).rounded())
    }

    private static func catalogDefinitions() -> [CleanupGroup] {
        [
            .init(id: "dev", title: "开发者缓存", detail: "仅显示本机已发现的包缓存、索引与派生数据", symbol: "hammer.fill", tint: .mint, size: 0, itemCount: 0, isSelected: false, risk: "安全项"),
            .init(id: "artifacts", title: "项目构建产物", detail: "仅显示实际存在的项目依赖与构建目录", symbol: "shippingbox.fill", tint: .indigo, size: 0, itemCount: 0, isSelected: false, risk: "逐项确认"),
            .init(id: "system", title: "系统临时内容", detail: "仅显示本机可读取的日志、缓存和安装包", symbol: "macwindow.on.rectangle", tint: .orange, size: 0, itemCount: 0, isSelected: false, risk: "逐项确认"),
            .init(id: "ai", title: "AI 工具产物", detail: "仅显示已安装工具实际生成的索引、模型和会话文件", symbol: "brain.head.profile", tint: .pink, size: 0, itemCount: 0, isSelected: false, risk: "逐项确认")
        ]
    }

    private static func projectArtifactTemplates() -> [(String, String, String, String, String, String)] {
        [
            ("node", "项目依赖目录", "node_modules", "依赖目录", "可通过项目锁定文件重新安装", "可重建"),
            ("next", "Next.js 构建缓存", ".next", "Web 构建缓存", "可由项目构建命令重新生成", "可重建"),
            ("turbo", "Turborepo 缓存", ".turbo", "构建缓存", "可由项目构建命令重新生成", "可重建"),
            ("rust", "Rust 编译缓存", "target", "Rust 构建缓存", "可由 cargo 重新构建", "可重建"),
            ("swift", "Swift 编译缓存", ".build", "Swift 构建缓存", "可由 SwiftPM 重新构建", "可重建"),
            ("venv-hidden", "Python 虚拟环境", ".venv", "虚拟环境", "可按项目依赖重新创建", "可重建"),
            ("venv", "Python 虚拟环境", "venv", "虚拟环境", "可按项目依赖重新创建", "可重建"),
            ("pycache", "Python 字节码缓存", "__pycache__", "字节码缓存", "Python 会自动重新生成", "可重建"),
            ("pods", "CocoaPods 项目依赖", "Pods", "依赖目录", "可通过 Podfile.lock 重新安装", "可重建"),
            ("vendor", "项目 Vendor 依赖", "vendor", "依赖目录", "请确认项目依赖声明完整后再清理", "建议确认"),
            ("cmake", "CMake 构建目录", "cmake-build-*", "构建缓存", "可由 CMake 重新构建", "可重建"),
            ("dist", "项目导出目录", "dist", "静态导出", "可能包含尚未发布的交付文件", "建议确认"),
            ("derived-data", "项目派生数据", "DerivedData", "Xcode 派生数据", "可由 Xcode 重新生成", "可重建")
        ]
    }

    private static func customProjectArtifactItems(root: String, idPrefix: String) -> [CleanupItem] {
        projectArtifactTemplates().flatMap { pattern in
            ["\(root)/\(pattern.2)", "\(root)/*/\(pattern.2)"].enumerated().map { depth, path in
                CleanupItem(
                    id: "\(idPrefix)-\(pattern.0)-\(depth)",
                    name: pattern.1,
                    path: path,
                    size: 0,
                    reason: pattern.4,
                    artifactType: pattern.3,
                    reviewLevel: pattern.5,
                    usesAgeRecommendation: true,
                    isSelected: false
                )
            }
        }
    }

    private static func cleanupRules() -> [String: [CleanupItem]] {
        var rules: [(String, String, String, String?, String, String, String, String)] = [
            ("dev", "Xcode 派生数据", "~/Library/Developer/Xcode/DerivedData/*", "Xcode", "派生数据", "可由 Xcode 自动重建", "可重建", "xcode-derived"),
            ("dev", "Xcode 模块缓存", "~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex", "Xcode", "模块缓存", "可由 Xcode 重新生成", "可重建", "xcode-module-cache"),
            ("dev", "iOS 设备支持文件", "~/Library/Developer/Xcode/iOS DeviceSupport/*", "Xcode", "设备支持", "旧系统版本的调试支持，可在需要时重新生成", "建议确认", "xcode-ios-device-support"),
            ("dev", "watchOS 设备支持文件", "~/Library/Developer/Xcode/watchOS DeviceSupport/*", "Xcode", "设备支持", "旧系统版本的调试支持，可在需要时重新生成", "建议确认", "xcode-watch-device-support"),
            ("dev", "CoreSimulator 缓存", "~/Library/Developer/CoreSimulator/Caches", "Xcode", "模拟器缓存", "模拟器会在需要时重新生成", "可重建", "xcode-simulator-cache"),
            ("dev", "npm 包缓存", "~/Library/Caches/npm", "npm", "包缓存", "包管理器会在需要时重新下载", "低风险", "npm-cache"),
            ("dev", "Yarn 包缓存", "~/Library/Caches/Yarn", "Yarn", "包缓存", "包管理器会在需要时重新下载", "低风险", "yarn-cache"),
            ("dev", "pnpm 包存储", "~/Library/pnpm/store", "pnpm", "包缓存", "包管理器会在需要时重新下载", "低风险", "pnpm-store"),
            ("dev", "pip 包缓存", "~/Library/Caches/pip", "pip", "包缓存", "Python 包可按项目依赖重新下载", "低风险", "pip-cache"),
            ("dev", "Poetry 包缓存", "~/Library/Caches/pypoetry", "Poetry", "包缓存", "Python 包可按项目依赖重新下载", "低风险", "poetry-cache"),
            ("dev", "uv 包缓存", "~/.cache/uv", "uv", "包缓存", "Python 包可按项目依赖重新下载", "低风险", "uv-cache"),
            ("dev", "Cargo 下载缓存", "~/.cargo/registry/cache", "Cargo", "包缓存", "Rust 依赖可按锁定文件重新下载", "低风险", "cargo-cache"),
            ("dev", "Go 构建缓存", "~/Library/Caches/go-build", "Go", "构建缓存", "Go 工具链可重新生成", "可重建", "go-build-cache"),
            ("dev", "Gradle 缓存", "~/.gradle/caches", "Gradle", "构建缓存", "Gradle 可按项目配置重新下载和生成", "低风险", "gradle-cache"),
            ("dev", "Maven 本地仓库", "~/.m2/repository", "Maven", "依赖缓存", "Maven 可按项目配置重新下载", "低风险", "maven-cache"),
            ("dev", "Bun 安装缓存", "~/.bun/install/cache", "Bun", "包缓存", "Bun 可按项目配置重新下载", "低风险", "bun-cache"),
            ("dev", "Deno 缓存", "~/Library/Caches/deno", "Deno", "运行缓存", "Deno 可在运行时重新生成", "低风险", "deno-cache"),
            ("dev", "mise 下载缓存", "~/.local/share/mise/downloads", "mise", "下载缓存", "工具版本可在需要时重新下载", "低风险", "mise-download-cache"),
            ("dev", "mise 运行缓存", "~/.cache/mise", "mise", "运行缓存", "mise 会在需要时重新生成", "低风险", "mise-runtime-cache"),
            ("dev", "Docker Desktop 缓存", "~/Library/Caches/com.docker.docker", "Docker", "应用缓存", "不包含 Docker 镜像、容器和数据卷", "低风险", "docker-desktop-cache"),
            ("dev", "VS Code 缓存", "~/Library/Application Support/Code/Cache", "VS Code", "编辑器缓存", "编辑器会在需要时重新生成", "低风险", "vscode-cache"),
            ("dev", "JetBrains 缓存", "~/Library/Caches/JetBrains/*", "JetBrains", "编辑器缓存", "IDE 会在需要时重新生成索引缓存", "可重建", "jetbrains-cache"),
            ("dev", "Homebrew 下载缓存", "~/Library/Caches/Homebrew", "Homebrew", "下载缓存", "已安装的软件包可再次下载", "低风险", "brew-cache"),
            ("dev", "CocoaPods 索引", "~/.cocoapods/repos", "CocoaPods", "仓库索引", "仅保存规格索引，不包含项目源码", "可重建", "cocoapods-repos"),
            ("dev", "Xcode 文档缓存", "~/Library/Developer/Shared/Documentation/DocSets", "Xcode", "文档缓存", "需要时可由 Xcode 重新下载", "建议确认", "xcode-doc-cache"),
            ("system", "用户日志", "~/Library/Logs", "macOS", "日志文件", "删除不会影响应用运行，但会失去诊断记录", "建议确认", "user-logs"),
            ("system", "下载目录中的安装包", "~/Downloads/*.dmg", "下载目录", "安装包", "确认应用已安装后再删除", "需确认", "download-dmg"),
            ("system", "Safari 缓存", "~/Library/Caches/com.apple.Safari", "Safari", "浏览器缓存", "清理后首次打开网页可能稍慢", "低风险", "safari-cache"),
            ("ai", "Cursor 工作区索引", "~/Library/Application Support/Cursor/User/workspaceStorage/*", "Cursor", "项目索引", "Cursor 可在下次打开项目时重建", "可重建", "cursor-index"),
            ("ai", "Cursor 扩展缓存", "~/Library/Application Support/Cursor/CachedExtensionVSIXs", "Cursor", "扩展缓存", "不影响已安装扩展", "低风险", "cursor-extension"),
            ("ai", "Cursor 会话记录", "~/.cursor/projects/*/agent-transcripts", "Cursor", "会话记录", "可能包含需要追溯的对话与工具结果", "需确认", "cursor-transcripts"),
            ("ai", "Cursor 生成资源", "~/.cursor/projects/*/assets", "Cursor", "生成资源", "可能是项目仍在使用的图片或附件", "需确认", "cursor-assets"),
            ("ai", "Cursor 计划文件", "~/.cursor/plans/*.plan.md", "Cursor", "计划文件", "删除后会失去已保存的工作计划", "需确认", "cursor-plans"),
            ("ai", "Claude Code 工具结果", "~/.claude/projects/*/tool-results", "Claude Code", "会话附件", "可能包含需要追溯的会话文件", "需确认", "claude-results"),
            ("ai", "Claude Code 日志", "~/.claude/logs", "Claude Code", "日志文件", "删除后无法查看历史诊断记录", "建议确认", "claude-logs"),
            ("ai", "Claude Code 会话记录", "~/.claude/projects/*/*.jsonl", "Claude Code", "会话记录", "可能包含完整对话和工具调用记录", "需确认", "claude-sessions"),
            ("ai", "Claude Code 命令快照", "~/.claude/shell-snapshots", "Claude Code", "命令快照", "仅保存终端环境快照，可重新生成", "低风险", "claude-shell-snapshots"),
            ("ai", "Codex 运行缓存", "~/.codex/cache", "Codex", "运行缓存", "可由 Codex 重新生成，不包含项目源码", "可重建", "codex-cache"),
            ("ai", "Ollama 模型分片", "~/.ollama/models/blobs", "Ollama", "模型文件", "删除后需要重新下载模型", "需确认", "ollama-blobs"),
            ("ai", "Ollama 模型清单", "~/.ollama/models/manifests", "Ollama", "模型元数据", "模型文件仍在时可重新生成", "可重建", "ollama-manifests"),
            ("ai", "LM Studio 元数据", "~/Library/Application Support/LM Studio/metadata", "LM Studio", "模型索引", "可重新扫描本地模型", "可重建", "lmstudio-metadata")
        ]
        let projectRoots = ["~/Projects", "~/Developer", "~/Code", "~/dev", "~/GitHub", "~/Workspace", "~/Documents", "~/Desktop"]
        let artifactPatterns = projectArtifactTemplates()
        for (index, root) in projectRoots.enumerated() {
            let expanded = (root as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else { continue }
            for pattern in artifactPatterns {
                rules.append(("artifacts", pattern.1, "\(root)/*/\(pattern.2)", nil, pattern.3, pattern.4, pattern.5, "project-\(pattern.0)-\(index)"))
            }
        }
        return Dictionary(grouping: rules.map { group, name, path, tool, type, reason, level, id in
            CleanupItem(id: id, name: name, path: path, size: 0, reason: reason, toolName: tool, artifactType: type, reviewLevel: level, usesAgeRecommendation: group == "artifacts", isSelected: false)
        }, by: { item in
            rules.first { $0.7 == item.id }?.0 ?? "system"
        })
    }

    private static func optimizeDefinitions() -> [OptimizeTask] {
        var tasks: [OptimizeTask] = []
        if ["/opt/homebrew/bin/cleanmymac", "/usr/local/bin/cleanmymac"].contains(where: FileManager.default.isExecutableFile(atPath:)) {
            tasks.append(.init(id: "ram", title: "释放非活跃内存", detail: "调用本机 CleanMyMac CLI 的 optimize ram", symbol: "memorychip.fill", tint: .mint, selected: false, completed: false))
            tasks.append(.init(id: "purgeable", title: "释放可清理空间", detail: "调用本机 CleanMyMac CLI 的 optimize purgeable", symbol: "internaldrive.fill", tint: .indigo, selected: false, completed: false))
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/dscacheutil") {
            tasks.append(.init(id: "dns", title: "刷新 DNS 缓存", detail: "使用系统命令刷新本地名称解析缓存", symbol: "network", tint: .orange, selected: false, completed: false))
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/qlmanage") {
            tasks.append(.init(id: "quicklook", title: "重置快速预览缓存", detail: "修复访达缩略图或空格预览不更新的问题", symbol: "eye.fill", tint: .indigo, selected: false, completed: false))
        }
        return tasks
    }

    private nonisolated static func executeOptimization(_ id: String) -> Bool {
        switch id {
        case "ram", "purgeable":
            guard let cliPath = ["/opt/homebrew/bin/cleanmymac", "/usr/local/bin/cleanmymac"].first(where: FileManager.default.isExecutableFile(atPath:)) else { return false }
            return commandSucceeded(cliPath, arguments: ["optimize", id])
        case "dns":
            return commandSucceeded("/usr/bin/dscacheutil", arguments: ["-flushcache"])
        case "quicklook":
            return commandSucceeded("/usr/bin/qlmanage", arguments: ["-r", "cache"])
        default:
            return false
        }
    }

    private nonisolated static func systemMemorySnapshot() -> (used: Double?, total: Double?) {
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        guard totalBytes > 0 else { return (nil, nil) }
        guard let output = commandOutput("/usr/bin/vm_stat", arguments: []) else {
            return (nil, totalBytes / 1_000_000_000)
        }
        let pageSize = output.split(separator: "\n").first(where: { $0.contains("page size") })
            .flatMap { $0.split(whereSeparator: { !$0.isNumber }).last }
            .flatMap { Double($0) } ?? 4096
        let labels = ["Pages active", "Pages wired down", "Pages occupied by compressor"]
        let pages = labels.reduce(0.0) { total, label in
            guard let line = output.split(separator: "\n").first(where: { $0.hasPrefix(label) }) else { return total }
            let value = line.split(whereSeparator: { !$0.isNumber }).last.flatMap { Double($0) } ?? 0
            return total + value
        }
        return (pages * pageSize / 1_000_000_000, totalBytes / 1_000_000_000)
    }

    private nonisolated static func commandOutput(_ path: String, arguments: [String], timeout: TimeInterval = 15) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            guard waitForProcess(process, timeout: timeout) else { return nil }
            guard process.terminationStatus == 0 else { return nil }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        } catch {
            return nil
        }
    }

    private nonisolated static func commandSucceeded(_ path: String, arguments: [String], timeout: TimeInterval = 15) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return waitForProcess(process, timeout: timeout) && process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private nonisolated static func waitForProcess(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard process.isRunning else { return true }

        process.terminate()
        let terminationDeadline = Date().addingTimeInterval(0.5)
        while process.isRunning && Date() < terminationDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        return false
    }

    private nonisolated static func optimizationSnapshot() -> OptimizationSnapshot {
        let pressure = commandOutput("/usr/bin/memory_pressure", arguments: ["-Q"])
        let freePercent = pressure?
            .split(separator: "\n")
            .first(where: { $0.contains("memory free percentage") })?
            .split(whereSeparator: { !$0.isNumber })
            .last
            .flatMap { Int($0) }

        let swap = commandOutput("/usr/sbin/sysctl", arguments: ["vm.swapusage"])
        func swapValue(after label: String) -> Double? {
            guard let range = swap?.range(of: label) else { return nil }
            let suffix = swap?[range.upperBound...].trimmingCharacters(in: .whitespaces) ?? ""
            guard let token = suffix.split(separator: " ").first else { return nil }
            return Double(token.trimmingCharacters(in: CharacterSet(charactersIn: "M"))).map { $0 / 1_000 }
        }

        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey
        ])
        let important = values?.volumeAvailableCapacityForImportantUsage.map(Double.init)
        let opportunistic = values?.volumeAvailableCapacityForOpportunisticUsage.map(Double.init)
        let purgeable: Double? = if let important, let opportunistic {
            max(0, important - opportunistic) / 1_000_000_000
        } else { nil }

        let fileManager = FileManager.default
        let backgroundItems = ["~/Library/LaunchAgents", "/Library/LaunchAgents"].reduce(0) { total, path in
            let expanded = (path as NSString).expandingTildeInPath
            let count = (try? fileManager.contentsOfDirectory(atPath: expanded).filter { $0.hasSuffix(".plist") }.count) ?? 0
            return total + count
        }
        return OptimizationSnapshot(
            memoryFreePercent: freePercent,
            swapUsed: swapValue(after: "used ="),
            swapTotal: swapValue(after: "total ="),
            purgeableEstimate: purgeable,
            uptime: ProcessInfo.processInfo.systemUptime,
            backgroundItemCount: backgroundItems
        )
    }

    private nonisolated static func storageSnapshot() -> (used: Double?, total: Double?, records: [StorageRecord]) {
        let fileManager = FileManager.default
        let attributes = try? fileManager.attributesOfFileSystem(forPath: "/")
        let total = (attributes?[.systemSize] as? NSNumber).map { $0.doubleValue / 1_000_000_000 }
        let free = (attributes?[.systemFreeSize] as? NSNumber).map { $0.doubleValue / 1_000_000_000 }
        let used: Double? = if let total, let free { max(0, total - free) } else { nil }
        return (used, total, [])
    }

    private func refreshSystemData(includeStorage: Bool = true) async {
        guard !isRefreshingSystemData else { return }
        isRefreshingSystemData = true
        defer { isRefreshingSystemData = false }
        let snapshot = await Task.detached(priority: .utility) {
            let storage: (used: Double?, total: Double?, records: [StorageRecord]) = includeStorage
                ? Self.storageSnapshot()
                : (nil, nil, [])
            return (storage, Self.systemMemorySnapshot(), Self.optimizationSnapshot())
        }.value
        if includeStorage {
            diskUsed = snapshot.0.used
            diskTotal = snapshot.0.total
        }
        memoryUsed = snapshot.1.used
        memoryTotal = snapshot.1.total
        memoryFreePercent = snapshot.2.memoryFreePercent
        swapUsed = snapshot.2.swapUsed
        swapTotal = snapshot.2.swapTotal
        purgeableEstimate = snapshot.2.purgeableEstimate
        systemUptime = snapshot.2.uptime
        backgroundItemCount = snapshot.2.backgroundItemCount
        if includeStorage {
            let colors: [Color] = [.indigo, .mint, .orange, .pink, .blue, .purple]
            storageNodes = snapshot.0.records.enumerated().map { index, record in
                StorageNode(name: record.name, detail: record.detail, size: record.size, color: colors[index % colors.count])
            }
        }
    }

    func checkPermissions() {
        guard !isCheckingPermissions else { return }
        isCheckingPermissions = true
        permissionMessage = nil
        let fileManager = FileManager.default
        permissionScopes = permissionScopes.map { scope in
            var updated = scope
            updated.state = Self.permissionState(
                for: scope.probePath,
                missingRequiresAuthorization: scope.requiresFullDiskAccess,
                fileManager: fileManager
            )
            return updated
        }
        isCheckingPermissions = false
    }

    private static func permissionState(for path: String, missingRequiresAuthorization: Bool, fileManager: FileManager) -> PermissionState {
        let expandedPath = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: expandedPath, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return (try? fileManager.contentsOfDirectory(atPath: expandedPath)) != nil
                    ? .available
                    : .needsAuthorization
            }
            return fileManager.isReadableFile(atPath: expandedPath) ? .available : .needsAuthorization
        }
        if missingRequiresAuthorization { return .needsAuthorization }

        // TCC may hide an existing directory. Walk up to the nearest visible ancestor
        // so a missing optional folder is not incorrectly reported as a permission error.
        var ancestor = URL(fileURLWithPath: expandedPath)
        while ancestor.path != "/" {
            ancestor.deleteLastPathComponent()
            if fileManager.fileExists(atPath: ancestor.path) {
                return fileManager.isReadableFile(atPath: ancestor.path) ? .notFound : .needsAuthorization
            }
        }
        return .notFound
    }

    private nonisolated static func scanCatalog(_ catalog: [String: [CleanupItem]], protectedPaths: [String], artifactAgeDays: Int, now: Date = .now) -> CatalogScanResult {
        let fileManager = FileManager.default
        var result: [String: [CleanupItem]] = [:]
        var wasLimited = false
        let deadline = Date().addingTimeInterval(45)

        groupLoop: for (groupID, items) in catalog {
            for item in items {
                if Task.isCancelled || Date() >= deadline {
                    wasLimited = true
                    break groupLoop
                }
                let expandedPath = (item.path as NSString).expandingTildeInPath
                let urls = expandedPath.contains("*")
                    ? matchingURLs(for: expandedPath, fileManager: fileManager)
                    : (fileManager.fileExists(atPath: expandedPath) ? [URL(fileURLWithPath: expandedPath)] : [])
                let safeURLs = urls.filter { url in
                    if item.id == "xcode-derived", url.lastPathComponent == "ModuleCache.noindex" { return false }
                    guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink != true else { return false }
                    return fileManager.isReadableFile(atPath: url.path) &&
                    CleanupPathPolicy.unsafeReason(for: url.path) == nil &&
                    CleanupPathPolicy.protectionReason(for: url.path, protectedPaths: protectedPaths) == nil
                }
                for url in safeURLs {
                    var copy = item
                    copy.id = "\(item.id)-\(stableID(for: url.path))"
                    copy.path = displayPath(url.path)
                    copy.canonicalPath = CleanupPathPolicy.canonicalPath(url.path)
                    copy.resourceIdentifier = CleanupPathPolicy.resourceIdentifier(for: url)
                    if copy.resourceIdentifier == nil {
                        copy.scanWarning = "无法建立文件身份标识；为避免扫描后路径被替换，此项不可清理"
                    }
                    copy.modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    if let project = projectName(in: url) {
                        copy.name = "\(project) · \(item.name)"
                        if let toolName = item.toolName {
                            copy.toolName = "\(toolName) · \(project)"
                        }
                    }
                    if item.toolName == nil {
                        let project = url.deletingLastPathComponent().lastPathComponent
                        copy.name = project.isEmpty ? item.name : "\(project) · \(item.name)"
                        copy.toolName = project.isEmpty ? nil : project
                    }
                    let measurement = directorySize(url, fileManager: fileManager)
                    guard measurement.bytes > 0 || measurement.isTruncated else { continue }
                    copy.size = Double(measurement.bytes) / 1_000_000_000
                    if measurement.isTruncated {
                        copy.scanWarning = "目录读取不完整、跨越其他磁盘或达到安全上限；当前大小仅供参考，此项不可清理"
                    }
                    if let level = copy.reviewLevel {
                        copy.isSelected = copy.canClean && CleanupRecommendation.shouldSelect(
                            reviewLevel: level,
                            usesAgeRecommendation: copy.usesAgeRecommendation,
                            modifiedAt: copy.modifiedAt,
                            ageDays: artifactAgeDays,
                            now: now
                        )
                    }
                    result[groupID, default: []].append(copy)
                }
            }
        }
        return CatalogScanResult(
            details: result.mapValues { $0.sorted { $0.path < $1.path } },
            wasLimited: wasLimited
        )
    }

    private nonisolated static func projectName(in url: URL) -> String? {
        let components = url.pathComponents
        guard let projectsIndex = components.firstIndex(of: "projects"), projectsIndex + 1 < components.count else { return nil }
        let project = components[projectsIndex + 1]
        guard !project.isEmpty, project != "-" else { return nil }
        return project
    }

    private nonisolated static func stableID(for path: String) -> String {
        path.utf8.reduce(UInt64(5381)) { ($0 &* 33) ^ UInt64($1) }.description
    }

    private nonisolated static func displayPath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~", options: [.anchored])
    }

    private nonisolated static func directorySize(_ url: URL, fileManager: FileManager) -> DirectoryMeasurement {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileAllocatedSizeKey, .fileSizeKey]) else {
            return DirectoryMeasurement(bytes: 0, isTruncated: true)
        }
        if values.isDirectory != true {
            return DirectoryMeasurement(bytes: UInt64(values.fileAllocatedSize ?? values.fileSize ?? 0), isTruncated: false)
        }

        var total: UInt64 = 0
        var visited = 0
        var isTruncated = false
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .fileSizeKey, .volumeIdentifierKey], options: []) else {
            return DirectoryMeasurement(bytes: 0, isTruncated: true)
        }
        let rootVolume = (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier
        let deadline = Date().addingTimeInterval(3)
        for case let childURL as URL in enumerator {
            if Task.isCancelled {
                isTruncated = true
                break
            }
            visited += 1
            if visited > 200_000 || Date() >= deadline {
                isTruncated = true
                break
            }
            guard let childValues = try? childURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .fileSizeKey, .volumeIdentifierKey]) else {
                isTruncated = true
                break
            }
            if childValues.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if let rootVolume, let childVolume = childValues.volumeIdentifier,
               String(describing: childVolume) != String(describing: rootVolume) {
                enumerator.skipDescendants()
                isTruncated = true
                break
            }
            guard childValues.isDirectory != true else { continue }
            total += UInt64(childValues.fileAllocatedSize ?? childValues.fileSize ?? 0)
        }
        return DirectoryMeasurement(bytes: total, isTruncated: isTruncated)
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            permissionMessage = "无法打开系统设置，请手动进入“隐私与安全性 → 完全磁盘访问权限”。"
            return
        }
        if !NSWorkspace.shared.open(url) {
            permissionMessage = "无法打开系统设置，请手动进入“隐私与安全性 → 完全磁盘访问权限”。"
        }
    }

    func scanApplications() {
        guard !isFilesystemBusy else {
            uninstallMessage = "另一项文件操作正在进行，请完成后再扫描应用。"
            uninstallMessageIsError = true
            return
        }
        isScanningApplications = true
        uninstallMessage = nil
        uninstallTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let worker = Task.detached(priority: .utility) { UninstallService.scan() }
            let result = await withTaskCancellationHandler(operation: {
                await worker.value
            }, onCancel: {
                worker.cancel()
            })
            guard !Task.isCancelled else {
                self.isScanningApplications = false
                self.uninstallMessage = "已停止应用扫描，未修改任何文件。"
                return
            }
            self.installedApplications = result.applications
            self.uninstallWasLimited = result.wasLimited
            self.isScanningApplications = false
            self.uninstallMessageIsError = false
            self.uninstallMessage = result.applications.isEmpty ? "当前允许读取的 Applications 目录中没有发现应用。" : "已读取本机 Applications 目录，结果为真实数据。"
        }
    }

    func cancelApplicationScan() {
        uninstallTask?.cancel()
        uninstallTask = nil
    }

    func toggleApplication(_ app: InstalledApplication) {
        guard !isFilesystemBusy else { return }
        guard let index = installedApplications.firstIndex(where: { $0.id == app.id }) else { return }
        installedApplications[index].isExpanded.toggle()
    }

    func toggleUninstallCandidate(appID: String, candidateID: String) {
        guard !isScanningApplications && !isUninstalling,
              let appIndex = installedApplications.firstIndex(where: { $0.id == appID }),
              let candidateIndex = installedApplications[appIndex].candidates.firstIndex(where: { $0.id == candidateID }) else { return }
        guard installedApplications[appIndex].candidates[candidateIndex].canRemove else { return }
        installedApplications[appIndex].candidates[candidateIndex].isSelected.toggle()
    }

    func selectAllUninstallCandidates() {
        guard !isScanningApplications && !isUninstalling else { return }
        let selectable = installedApplications.flatMap { $0.candidates }.filter(\.canRemove)
        let nextValue = !selectable.isEmpty && !selectable.allSatisfy(\.isSelected)
        installedApplications = installedApplications.map { app in
            var copy = app
            copy.candidates = app.candidates.map { candidate in
                var item = candidate
                item.isSelected = candidate.canRemove && nextValue
                return item
            }
            return copy
        }
    }

    func selectRecommendedUninstallCandidates() {
        guard !isScanningApplications && !isUninstalling else { return }
        installedApplications = installedApplications.map { app in
            var copy = app
            copy.candidates = app.candidates.map { candidate in
                var item = candidate
                item.isSelected = candidate.canRemove && candidate.risk == .safe
                return item
            }
            return copy
        }
    }

    func requestUninstall() {
        guard selectedUninstallCount > 0 else {
            uninstallMessage = "请先选择应用本体或明确归属的残留项目。"
            uninstallMessageIsError = true
            return
        }
        showUninstallConfirmation = true
    }

    func uninstallSelected() {
        showUninstallConfirmation = false
        guard selectedUninstallCount > 0 else { return }
        let selected = selectedUninstallCandidates
        let protected = protectedPaths
        isUninstalling = true
        uninstallMessage = nil
        uninstallTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .utility) { UninstallService.remove(selected: selected, protectedPaths: protected) }.value
            self.isUninstalling = false
            switch result {
            case .success(let outcome):
                let movedIDs = outcome.movedIDs
                self.installedApplications = self.installedApplications.compactMap { app in
                    var copy = app
                    copy.candidates = app.candidates.filter { !movedIDs.contains($0.id) }
                    return copy.candidates.isEmpty ? nil : copy
                }
                self.uninstallReportPath = CleanupDisplayPath.value(for: outcome.reportURL.path)
                self.uninstallMessageIsError = !outcome.failures.isEmpty
                self.uninstallMessage = outcome.failures.isEmpty
                    ? "已将 (outcome.movedIDs.count) 个项目移入废纸篓，可随时恢复。"
                    : "已移入废纸篓 (outcome.movedIDs.count) 个项目；(outcome.failures.count) 个项目未处理，请查看报告。"
            case .failure(let error):
                self.uninstallMessageIsError = true
                self.uninstallMessage = "卸载准备失败：\(error.localizedDescription)。未修改任何文件。"
            }
        }
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"),
              NSWorkspace.shared.open(url) else {
            optimizeMessage = "无法打开登录项设置，请手动进入“系统设置 → 通用 → 登录项与扩展”。"
            return
        }
    }

    func refreshOptimizationData() {
        Task { @MainActor in await refreshSystemData(includeStorage: false) }
    }

    func chooseScanFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择要扫描的文件夹"
        panel.message = "只会读取你选择的文件夹，不需要完全磁盘访问权限。"
        panel.prompt = "加入扫描"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path
        guard !CleanupPathPolicy.containsGlobMeta(path) else {
            permissionMessage = "所选路径包含通配符字符，无法作为安全扫描根目录。"
            return
        }
        guard !permissionScopes.contains(where: { $0.path == path }) else {
            permissionMessage = "这个文件夹已经在扫描范围内。"
            return
        }
        let customID = "custom-\(UUID().uuidString)"
        permissionScopes.append(.init(
            id: customID,
            title: "自选文件夹",
            path: path,
            detail: "本次会话由你主动授权的扫描位置",
            probePath: path,
            requiresFullDiskAccess: false
        ))
        let folderName = url.lastPathComponent.isEmpty ? path : url.lastPathComponent
        catalogDetails[customID] = Self.customProjectArtifactItems(root: path, idPrefix: customID)
        catalogGroups.append(.init(
            id: customID,
            title: "自选项目范围 · \(folderName)",
            detail: "只查找该目录及其直接子项目中的已知依赖和构建产物",
            symbol: "folder.fill",
            tint: .blue,
            size: 0,
            itemCount: 0,
            isSelected: false,
            risk: "逐项确认"
        ))
        checkPermissions()
        permissionMessage = "已加入项目扫描范围：\(path)。目录本身不会成为清理目标。"
    }

    func openPathInFinder(_ path: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        let fileManager = FileManager.default
        let matches = expandedPath.contains("*")
            ? Self.matchingURLs(for: expandedPath, fileManager: fileManager)
            : (fileManager.fileExists(atPath: expandedPath) ? [URL(fileURLWithPath: expandedPath)] : [])

        if !matches.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(Array(matches.prefix(50)))
            return
        }

        guard let fallback = nearestExistingAncestor(for: expandedPath) else {
            pathNotice = "找不到这个路径，可能已经被移动、删除，或当前账号没有访问权限。\n\n扫描路径：\(path)"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([fallback])
        let shortFallback = fallback.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        pathNotice = "扫描结果生成后，这条路径已不存在或当前已无权读取：\n\(path)\n\n已打开最近存在的目录：\n\(shortFallback)"
    }

    func analyzeDirectory(_ path: String? = nil) {
        guard !isFilesystemBusy else {
            analyzerMessage = "另一项文件操作正在进行，请完成后再分析。"
            return
        }
        let requestedPath = path ?? analyzerPath
        let protected = protectedPaths
        isAnalyzing = true
        analyzerMessage = nil
        analyzerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let worker = Task.detached(priority: .utility) {
                    try StorageAnalyzer.scan(path: requestedPath, protectedPaths: protected)
                }
                let snapshot = try await withTaskCancellationHandler(operation: {
                    try await worker.value
                }, onCancel: {
                    worker.cancel()
                })
                guard !Task.isCancelled else {
                    self.isAnalyzing = false
                    self.analyzerMessage = "已停止分析，未修改任何文件。"
                    self.analyzerTask = nil
                    return
                }
                analyzerPath = snapshot.path
                analyzerEntries = snapshot.entries
                if snapshot.isTruncated {
                    analyzerMessage = "分析达到安全时间或读取上限，结果可能不完整；可缩小目录范围后重试。"
                } else if snapshot.entries.isEmpty {
                    analyzerMessage = "这个目录为空，或其中没有当前账号可读取的项目。"
                }
            } catch {
                analyzerMessage = error.localizedDescription
            }
            isAnalyzing = false
            analyzerTask = nil
        }
    }

    func cancelAnalysis() {
        guard isAnalyzing else { return }
        analyzerTask?.cancel()
    }

    func scanTrash() {
        guard !isFilesystemBusy else {
            trashMessage = "另一项文件操作正在进行，请完成后再扫描废纸篓。"
            return
        }
        isScanningTrash = true
        trashMessage = nil
        trashScanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let worker = Task.detached(priority: .utility) { Self.readTrashEntries() }
            let result = await withTaskCancellationHandler(operation: {
                await worker.value
            }, onCancel: {
                worker.cancel()
            })
            guard !Task.isCancelled else {
                self.isScanningTrash = false
                self.trashMessage = "已停止废纸篓扫描，未修改任何文件。"
                self.trashScanTask = nil
                return
            }
            trashEntries = result.entries
            isScanningTrash = false
            if result.wasLimited {
                trashMessage = "废纸篓扫描达到 30 秒安全上限，只显示已经读取的项目。"
            } else if trashEntries.isEmpty {
                trashMessage = "废纸篓为空，或当前账号没有可读取的项目。"
            }
            trashScanTask = nil
        }
    }

    func cancelTrashScan() {
        guard isScanningTrash else { return }
        trashScanTask?.cancel()
    }

    func requestEmptyTrash() {
        guard !isFilesystemBusy,
              trashEntries.contains(where: \.isSelected) else { return }
        showEmptyTrashConfirmation = true
    }

    func emptyTrash() {
        showEmptyTrashConfirmation = false
        let selected = trashEntries.filter(\.isSelected)
        guard !selected.isEmpty else { return }
        guard !isDeletingTrash else { return }
        isDeletingTrash = true
        trashMessage = nil
        Task { @MainActor in
            let outcome = await Task.detached(priority: .utility) {
                Self.deleteTrashEntries(selected)
            }.value
            trashEntries.removeAll { outcome.removedIDs.contains($0.id) }
            isDeletingTrash = false
            trashMessage = outcome.failures.isEmpty
                ? "已永久删除 \(outcome.removedIDs.count) 个废纸篓项目，无法恢复。"
                : "已永久删除 \(outcome.removedIDs.count) 个项目；\(outcome.failures.count) 个项目失败。"
        }
    }

    private nonisolated static func deleteTrashEntries(_ selected: [TrashEntry]) -> TrashDeletionOutcome {
        var failures: [String] = []
        var removed = Set<String>()
        for entry in selected {
            guard entry.canDelete else {
                failures.append("\(entry.path)：扫描结果不完整或无法确认文件身份")
                continue
            }
            guard Self.isTrashPath(entry.canonicalPath) else {
                failures.append("\(entry.path)：不是系统废纸篓路径")
                continue
            }
            let url = URL(fileURLWithPath: entry.canonicalPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                failures.append("\(entry.path)：路径已不存在")
                continue
            }
            guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink != true else {
                failures.append("\(entry.path)：无法确认路径安全性")
                continue
            }
            guard let scannedIdentifier = entry.resourceIdentifier,
                  let currentIdentifier = CleanupPathPolicy.resourceIdentifier(for: url) else {
                failures.append("\(entry.path)：无法确认文件身份")
                continue
            }
            if currentIdentifier != scannedIdentifier {
                failures.append("\(entry.path)：文件在扫描后已被替换")
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
                removed.insert(entry.id)
            } catch {
                failures.append("\(entry.path)：\(error.localizedDescription)")
            }
        }
        return TrashDeletionOutcome(removedIDs: removed, failures: failures)
    }

    func toggleTrashEntry(_ entry: TrashEntry) {
        guard !isFilesystemBusy && entry.canDelete else { return }
        guard let index = trashEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        trashEntries[index].isSelected.toggle()
    }

    func selectAllTrash() {
        guard !isFilesystemBusy else { return }
        let selectable = trashEntries.filter(\.canDelete)
        let nextValue = !selectable.isEmpty && !selectable.allSatisfy(\.isSelected)
        trashEntries = trashEntries.map { entry in
            var copy = entry
            copy.isSelected = entry.canDelete && nextValue
            return copy
        }
    }

    private nonisolated static func readTrashEntries() -> TrashScanResult {
        let fileManager = FileManager.default
        var roots: [(URL, String)] = []
        let homeTrash = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash", isDirectory: true)
        roots.append((homeTrash, "启动磁盘"))
        if let volumes = try? fileManager.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            let uid = String(getuid())
            roots.append(contentsOf: volumes.map { ($0.appendingPathComponent(".Trashes/\(uid)", isDirectory: true), $0.lastPathComponent) })
        }
        var entries: [TrashEntry] = []
        var wasLimited = false
        let deadline = Date().addingTimeInterval(30)
        rootLoop: for (root, volumeName) in roots {
            guard let urls = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileResourceIdentifierKey, .isSymbolicLinkKey], options: []) else { continue }
            for url in urls {
                if Task.isCancelled || Date() >= deadline {
                    wasLimited = true
                    break rootLoop
                }
                guard let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey, .isSymbolicLinkKey]), values.isSymbolicLink != true else { continue }
                let measurement = StorageAnalyzer.size(of: url, fileManager: fileManager)
                entries.append(TrashEntry(
                    id: CleanupStableID.value(for: url.path),
                    name: url.lastPathComponent,
                    path: CleanupDisplayPath.value(for: url.path),
                    canonicalPath: CleanupPathPolicy.canonicalPath(url.path),
                    resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
                    size: Double(measurement.bytes) / 1_000_000_000,
                    volumeName: volumeName,
                    isTruncated: measurement.isTruncated,
                    isSelected: false
                ))
            }
        }
        return TrashScanResult(entries: entries.sorted { $0.size > $1.size }, wasLimited: wasLimited)
    }

    private nonisolated static func isTrashPath(_ path: String) -> Bool {
        let canonical = CleanupPathPolicy.canonicalPath(path)
        let homeTrash = CleanupPathPolicy.canonicalPath("\(NSHomeDirectory())/.Trash")
        if canonical.hasPrefix(homeTrash + "/") { return true }
        guard canonical.hasPrefix("/Volumes/") else { return false }
        let components = canonical.split(separator: "/")
        return components.count >= 4 && components[2] == ".Trashes" && components[3] == Substring(String(getuid()))
    }

    func chooseAnalyzeFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择要分析的文件夹"
        panel.message = "只读取目录占用，不会修改其中的文件。"
        panel.prompt = "开始分析"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        analyzeDirectory(url.path)
    }

    func enterAnalyzerEntry(_ entry: AnalyzerEntry) {
        guard entry.isDirectory else { return }
        analyzeDirectory(entry.canonicalPath)
    }

    func analyzeParentDirectory() {
        let expanded = (analyzerPath as NSString).expandingTildeInPath
        let parent = URL(fileURLWithPath: expanded).deletingLastPathComponent().path
        guard parent != expanded else { return }
        analyzeDirectory(parent)
    }

    func requestAnalyzerTrash(_ entry: AnalyzerEntry) {
        guard entry.canMoveToTrash && !isFilesystemBusy else { return }
        pendingAnalyzerTrash = entry
        showAnalyzerTrashConfirmation = true
    }

    func movePendingAnalyzerEntryToTrash() {
        showAnalyzerTrashConfirmation = false
        guard let entry = pendingAnalyzerTrash else { return }
        pendingAnalyzerTrash = nil
        guard !isFilesystemBusy else { return }
        isMovingAnalyzerEntry = true
        let protected = protectedPaths
        Task { @MainActor in
            let outcome = await Task.detached(priority: .utility) {
                if let reason = CleanupPathPolicy.validationFailure(
                    for: entry.path,
                    scannedCanonicalPath: entry.canonicalPath,
                    scannedResourceIdentifier: entry.resourceIdentifier,
                    protectedPaths: protected
                ) {
                    return AnalyzerMoveOutcome(errorMessage: reason)
                }
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: entry.canonicalPath), resultingItemURL: nil)
                    return AnalyzerMoveOutcome(errorMessage: nil)
                } catch {
                    return AnalyzerMoveOutcome(errorMessage: error.localizedDescription)
                }
            }.value
            isMovingAnalyzerEntry = false
            if let reason = outcome.errorMessage {
                analyzerMessage = "无法移入废纸篓：\(reason)。"
            } else {
                analyzerMessage = "已将“\(entry.name)”移入废纸篓，可在废纸篓中恢复。"
                analyzeDirectory(analyzerPath)
            }
        }
    }

    private func nearestExistingAncestor(for path: String) -> URL? {
        let fileManager = FileManager.default
        var candidate = URL(fileURLWithPath: path)
        while !fileManager.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private nonisolated static func matchingURLs(for path: String, fileManager: FileManager) -> [URL] {
        let components = URL(fileURLWithPath: path).pathComponents
        var candidates: [URL] = [URL(fileURLWithPath: "/")]

        for component in components.dropFirst() {
            if component.contains("*") {
                var next: [URL] = []
                for candidate in candidates {
                    guard let children = try? fileManager.contentsOfDirectory(at: candidate, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { continue }
                    next.append(contentsOf: children.filter { Self.matchesGlob($0.lastPathComponent, pattern: component) })
                }
                candidates = next
            } else {
                candidates = candidates.map { $0.appendingPathComponent(component) }.filter { fileManager.fileExists(atPath: $0.path) }
            }
            if candidates.isEmpty { break }
        }
        return candidates
    }

    private nonisolated static func matchesGlob(_ value: String, pattern: String) -> Bool {
        let input = Array(value)
        let mask = Array(pattern)
        var inputIndex = 0
        var maskIndex = 0
        var starIndex = -1
        var starMatch = 0

        while inputIndex < input.count {
            if maskIndex < mask.count && (mask[maskIndex] == "?" || mask[maskIndex] == input[inputIndex]) {
                inputIndex += 1
                maskIndex += 1
            } else if maskIndex < mask.count && mask[maskIndex] == "*" {
                starIndex = maskIndex
                starMatch = inputIndex
                maskIndex += 1
            } else if starIndex >= 0 {
                maskIndex = starIndex + 1
                starMatch += 1
                inputIndex = starMatch
            } else {
                return false
            }
        }

        while maskIndex < mask.count && mask[maskIndex] == "*" { maskIndex += 1 }
        return maskIndex == mask.count
    }

    func beginDeepScan() {
        checkPermissions()
        if deepAuthorizationNeeded {
                permissionMessage = "深度扫描还缺少完全磁盘访问权限。请在系统设置中允许 \(ProductIdentity.displayName) 后重新检测。"
            openSystemSettings()
        } else {
            scan()
        }
    }

    func scan() {
        guard !isFilesystemBusy else {
            scanMessage = "另一项文件操作正在进行，请完成后再扫描。"
            return
        }
        checkPermissions()
        // Rebuild standard roots on every scan so folders created or mounted
        // after launch are discovered while preserving user-selected roots.
        let standardIDs = Set(Self.catalogDefinitions().map(\.id))
        var refreshedCatalog = Self.cleanupRules()
        for (id, items) in catalogDetails where !standardIDs.contains(id) {
            refreshedCatalog[id] = items
        }
        catalogDetails = refreshedCatalog
        let catalog = refreshedCatalog
        let artifactAgeDays = artifactRecommendationDays
        isScanning = true
        scanProgress = 0
        cleanupMessage = nil
        scanMessage = nil
        scanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let protected = self.protectedPaths
            let worker = Task.detached(priority: .utility) {
                Self.scanCatalog(catalog, protectedPaths: protected, artifactAgeDays: artifactAgeDays)
            }
            let scanResult = await withTaskCancellationHandler(operation: {
                await worker.value
            }, onCancel: {
                worker.cancel()
            })
            guard !Task.isCancelled else {
                self.isScanning = false
                self.scanMessage = "已停止扫描，未修改任何文件。"
                self.scanTask = nil
                return
            }
            let actualDetails = scanResult.details
            cleanupDetails = actualDetails
            groups = catalogGroups.compactMap { group in
                guard let items = actualDetails[group.id], !items.isEmpty else { return nil }
                var copy = group
                copy.size = items.reduce(0) { $0 + $1.size }
                copy.itemCount = items.count
                let selectableItems = items.filter(\.canClean)
                copy.isSelected = !selectableItems.isEmpty && selectableItems.allSatisfy(\.isSelected)
                let reviewCount = items.filter { item in
                    guard let level = item.reviewLevel else { return false }
                    return level != "可重建" && level != "低风险"
                }.count
                copy.risk = reviewCount > 0 ? "\(reviewCount) 项需确认" : "全部可重建"
                return copy
            }
            hasScanned = true
            lastScan = .now
            isScanning = false
            scanProgress = 1
            let permissionText = detectedPermissionCount > 0
                ? "已读取 \(availablePermissionCount)/\(detectedPermissionCount) 个实际位置；需要授权的位置未计入结果。"
                : "当前没有发现可读取的扫描位置。"
            scanMessage = scanResult.wasLimited
                ? "扫描达到安全时间上限，结果可能不完整；请缩小扫描范围后重试。\n\(permissionText)"
                : permissionText
            await refreshSystemData()
            self.scanTask = nil
        }
    }

    func cancelScan() {
        guard isScanning else { return }
        scanTask?.cancel()
    }

    func requestClean() {
        guard selectedItems > 0 && !isFilesystemBusy else { return }
        showCleanConfirmation = true
    }

    func toggleGroup(_ group: CleanupGroup) {
        guard !isScanning && !isCleaning else { return }
        let items = cleanupDetails[group.id] ?? []
        let selectableItems = items.filter(\.canClean)
        guard !selectableItems.isEmpty else { return }
        let nextValue = !selectableItems.allSatisfy(\.isSelected)
        if let index = groups.firstIndex(of: group) {
            groups[index].isSelected = nextValue
        }
        cleanupDetails[group.id] = (cleanupDetails[group.id] ?? []).map { item in
            var copy = item
            copy.isSelected = copy.canClean && nextValue
            return copy
        }
    }

    func toggleItem(groupID: String, itemID: String) {
        guard !isScanning && !isCleaning else { return }
        guard var items = cleanupDetails[groupID],
              let itemIndex = items.firstIndex(where: { $0.id == itemID }) else { return }
        guard items[itemIndex].canClean else { return }
        items[itemIndex].isSelected.toggle()
        cleanupDetails[groupID] = items
        if let groupIndex = groups.firstIndex(where: { $0.id == groupID }) {
            let selectableItems = items.filter(\.canClean)
            groups[groupIndex].isSelected = !selectableItems.isEmpty && selectableItems.allSatisfy(\.isSelected)
        }
    }

    func toggleItems(groupID: String, itemIDs: [String]) {
        guard !isScanning && !isCleaning else { return }
        guard var items = cleanupDetails[groupID] else { return }
        let ids = Set(itemIDs)
        let matching = items.filter { ids.contains($0.id) && $0.canClean }
        guard !matching.isEmpty else { return }
        let nextValue = !matching.allSatisfy(\.isSelected)
        items = items.map { item in
            guard ids.contains(item.id), item.canClean else { return item }
            var copy = item
            copy.isSelected = nextValue
            return copy
        }
        cleanupDetails[groupID] = items
        if let groupIndex = groups.firstIndex(where: { $0.id == groupID }) {
            let selectableItems = items.filter(\.canClean)
            groups[groupIndex].isSelected = !selectableItems.isEmpty && selectableItems.allSatisfy(\.isSelected)
        }
    }

    func selectAll() {
        guard !isScanning && !isCleaning else { return }
        cleanupDetails = cleanupDetails.mapValues { items in
            items.map { item in
                var copy = item
                copy.isSelected = copy.canClean
                return copy
            }
        }
        groups = groups.map { group in
            var copy = group
            let selectableItems = (cleanupDetails[group.id] ?? []).filter(\.canClean)
            copy.isSelected = !selectableItems.isEmpty && selectableItems.allSatisfy(\.isSelected)
            return copy
        }
    }

    func selectRecommended() {
        guard !isScanning && !isCleaning else { return }
        cleanupDetails = cleanupDetails.mapValues { items in
            items.map { item in
                var copy = item
                copy.isSelected = copy.canClean && CleanupRecommendation.shouldSelect(
                    reviewLevel: item.reviewLevel,
                    usesAgeRecommendation: item.usesAgeRecommendation,
                    modifiedAt: item.modifiedAt,
                    ageDays: artifactRecommendationDays
                )
                return copy
            }
        }
        groups = groups.map { group in
            var copy = group
            let items = cleanupDetails[group.id] ?? []
            let selectableItems = items.filter(\.canClean)
            copy.isSelected = !selectableItems.isEmpty && selectableItems.allSatisfy(\.isSelected)
            return copy
        }
    }

    func cleanSelected() {
        showCleanConfirmation = false
        guard selectedItems > 0 else { return }
        isCleaning = true
        cleanupMessage = nil
        cleanupMessageIsError = false
        let selected = cleanupDetails.values.flatMap { $0 }.filter(\.isSelected)
        let protected = protectedPaths
        Task { @MainActor in
            let outcome = await Task.detached(priority: .utility) {
                Self.moveItemsToTrash(selected, protectedPaths: protected)
            }.value
            switch outcome {
            case .success(let result):
                cleanupDetails = cleanupDetails.mapValues { items in
                    items.filter { !result.movedIDs.contains($0.id) }
                }
                groups = groups.compactMap { group in
                    let items = cleanupDetails[group.id] ?? []
                    var copy = group
                    copy.itemCount = items.count
                    copy.size = items.reduce(0) { $0 + $1.size }
                    let selectableItems = items.filter(\.canClean)
                    copy.isSelected = !selectableItems.isEmpty && selectableItems.allSatisfy(\.isSelected)
                    guard !items.isEmpty else { return nil }
                    return copy
                }
                lastReportPath = Self.displayPath(result.reportURL.path)
                isCleaning = false
                cleanupMessageIsError = false
                if result.failed.isEmpty {
                    cleanupMessage = String(format: "已将 %d 个项目移入废纸篓，实际处理 %.2f GB。清理记录：%@", result.movedIDs.count, result.movedSize, lastReportPath ?? result.reportURL.path)
                } else {
                    cleanupMessageIsError = true
                    cleanupMessage = "已移入废纸篓 \(result.movedIDs.count) 个项目；\(result.failed.count) 个项目失败，失败项已保留并记录原因。"
                }
            case .failure(let reason):
                isCleaning = false
                cleanupMessageIsError = true
                cleanupMessage = "清理准备失败：\(reason.message)。已保留勾选项，未修改任何文件。"
            }
        }
    }

    private nonisolated static func moveItemsToTrash(_ items: [CleanupItem], protectedPaths: [String]) -> Result<CleanupOutcome, ReportFailure> {
        let reportURL: URL
        switch writeCleanupReport(items) {
        case .success(let url): reportURL = url
        case .failure(let failure): return .failure(failure)
        }
        let fileManager = FileManager.default
        var movedIDs = Set<String>()
        var movedURLs: [URL] = []
        var movedSize = 0.0
        var failed: [String] = []
        let sortedItems = items.sorted { $0.path.count < $1.path.count }
        for item in sortedItems {
            if let warning = item.scanWarning {
                failed.append("\(item.path)：扫描未完成，不允许清理（\(warning)）")
                continue
            }
            if let reason = CleanupPathPolicy.validationFailure(
                for: item.path,
                scannedCanonicalPath: item.canonicalPath,
                scannedResourceIdentifier: item.resourceIdentifier,
                protectedPaths: protectedPaths,
                fileManager: fileManager
            ) {
                failed.append("\(item.path)：\(reason)")
                continue
            }
            let canonical = CleanupPathPolicy.canonicalPath(item.path)
            let url = URL(fileURLWithPath: canonical)
            if movedURLs.contains(where: { url.path == $0.path || url.path.hasPrefix($0.path + "/") }) {
                // 父目录移入废纸篓后，子路径也已一并处理。
                movedIDs.insert(item.id)
                continue
            }
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
                movedIDs.insert(item.id)
                movedURLs.append(url)
                movedSize += item.size
            } catch {
                failed.append("\(item.path)：\(error.localizedDescription)")
            }
        }
        appendCleanupOutcome(to: reportURL, movedIDs: movedIDs, movedSize: movedSize, failures: failed)
        return .success(CleanupOutcome(reportURL: reportURL, movedIDs: movedIDs, movedSize: movedSize, failed: failed))
    }

    private nonisolated static func appendCleanupOutcome(to reportURL: URL, movedIDs: Set<String>, movedSize: Double, failures: [String]) {
        guard let handle = try? FileHandle(forWritingTo: reportURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        var lines = [
            "",
            "执行结果",
            "成功项目：\(movedIDs.count)",
            String(format: "实际处理：%.2f GB", movedSize),
            "失败项目：\(failures.count)"
        ]
        lines.append(contentsOf: failures.map { "- \($0)" })
        if let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }

    private nonisolated static func writeCleanupReport(_ items: [CleanupItem]) -> Result<URL, ReportFailure> {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return .failure(ReportFailure(message: "找不到当前用户的应用支持目录"))
        }
            let reportsDirectory = applicationSupport.appendingPathComponent("CleanMyMac/Reports", isDirectory: true)
        do {
            try fileManager.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: reportsDirectory.path)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let uniqueSuffix = UUID().uuidString.lowercased().prefix(8)
            let reportURL = reportsDirectory.appendingPathComponent("cleanup-report-\(formatter.string(from: .now))-\(uniqueSuffix).txt")
            var lines = [
                "\(ProductIdentity.displayName) 清理审核报告",
                "生成时间：\(Date.now.formatted(date: .abbreviated, time: .standard))",
                "项目数量：\(items.count)",
                "",
                "执行方式：选中项目会被移入 macOS 废纸篓，可从废纸篓恢复。"
            ]
            for (index, item) in items.enumerated() {
                lines.append("")
                lines.append("\(index + 1). \(item.name)")
                lines.append("路径：\(item.path)")
                lines.append("大小：\(detailStorageSize(item.size))")
                lines.append("原因：\(item.reason)")
                if let toolName = item.toolName { lines.append("来源工具：\(toolName)") }
                if let artifactType = item.artifactType { lines.append("产物类型：\(artifactType)") }
                if let reviewLevel = item.reviewLevel { lines.append("审核级别：\(reviewLevel)") }
                if let scanWarning = item.scanWarning { lines.append("扫描提示：\(scanWarning)") }
            }
            try lines.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reportURL.path)
            return .success(reportURL)
        } catch {
            return .failure(ReportFailure(message: error.localizedDescription))
        }
    }

    func runOptimizations() {
        guard !isFilesystemBusy, !isOptimizing,
              optimizeTasks.contains(where: { $0.selected && !$0.completed }) else { return }
        isOptimizing = true
        optimizeMessage = nil
        Task { @MainActor in
            for index in optimizeTasks.indices where optimizeTasks[index].selected && !optimizeTasks[index].completed {
                let taskID = optimizeTasks[index].id
                let succeeded = await Task.detached(priority: .utility) {
                    Self.executeOptimization(taskID)
                }.value
                if succeeded {
                    optimizeTasks[index].completed = true
                } else {
                    optimizeMessage = "“\(optimizeTasks[index].title)”未执行：当前系统未提供可用的非特权接口，未修改任何内容。"
                }
            }
            isOptimizing = false
        }
    }
}
