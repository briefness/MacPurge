import Foundation
import AppKit

enum UninstallPathPolicy {
    static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    static func isApplicationBundle(_ url: URL, allowedRoots: [URL]) -> Bool {
        guard url.pathExtension.lowercased() == "app", !isSymbolicLink(url) else { return false }
        let canonical = canonicalPath(url.path)
        return allowedRoots.contains { root in
            let rootPath = canonicalPath(root.path)
            return canonical.hasPrefix(rootPath + "/") && canonical.dropFirst(rootPath.count + 1).contains("/") == false
        }
    }

    static func isUserLibraryCandidate(_ url: URL, homeDirectory: String = NSHomeDirectory()) -> Bool {
        guard !isSymbolicLink(url) else { return false }
        let candidate = canonicalPath(url.path)
        let library = canonicalPath((homeDirectory as NSString).appendingPathComponent("Library"))
        guard candidate.hasPrefix(library + "/"), candidate != library else { return false }
        let forbidden = ["/Documents", "/Desktop", "/Downloads", "/Movies", "/Music", "/Pictures", "/Public"]
        return !forbidden.contains { candidate.hasPrefix(canonicalPath(homeDirectory) + $0) }
    }
}

enum UninstallService {
    struct ScanResult: Sendable {
        let applications: [InstalledApplication]
        let wasLimited: Bool
    }

    struct RemovalResult: Sendable {
        let movedIDs: Set<String>
        let movedSize: Double
        let failures: [String]
        let reportURL: URL
    }

    private static let maxApplications = 300
    private static let maxCandidatesPerApp = 80

    static func scan() -> ScanResult {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true), home.appendingPathComponent("Applications", isDirectory: true)]
        let allowedRoots = roots.filter { fileManager.isReadableFile(atPath: $0.path) }
        let deadline = Date().addingTimeInterval(30)
        var wasLimited = false
        var seen = Set<String>()
        var applications: [InstalledApplication] = []

        for root in allowedRoots {
            guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else { continue }
            for name in names.sorted() {
                if Task.isCancelled || Date() >= deadline || applications.count >= maxApplications {
                    wasLimited = true
                    break
                }
                let url = root.appendingPathComponent(name, isDirectory: true)
                guard url.pathExtension.lowercased() == "app",
                      UninstallPathPolicy.isApplicationBundle(url, allowedRoots: allowedRoots) else { continue }
                let canonical = UninstallPathPolicy.canonicalPath(url.path)
                guard seen.insert(canonical).inserted,
                      let bundle = Bundle(url: url),
                      let bundleIdentifier = bundle.bundleIdentifier,
                      !bundleIdentifier.isEmpty else { continue }
                let appName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
                    ?? "未知版本"
                let isSystem = bundleIdentifier.hasPrefix("com.apple.") || canonical.hasPrefix("/System/")
                let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
                let size = bytesToGB(directorySize(url, deadline: deadline).bytes)
                let candidates = isSystem ? [blockedApplicationCandidate(url: url, canonical: canonical, size: size, bundleIdentifier: bundleIdentifier)] :
                    residualCandidates(for: url, canonical: canonical, bundleIdentifier: bundleIdentifier, applicationSize: size, deadline: deadline)
                applications.append(InstalledApplication(
                    id: canonical,
                    name: appName,
                    bundleIdentifier: bundleIdentifier,
                    version: version,
                    path: CleanupDisplayPath.value(for: canonical),
                    canonicalPath: canonical,
                    size: size,
                    iconPath: url.path,
                    isRunning: running,
                    isSystemApplication: isSystem,
                    candidates: candidates,
                    isExpanded: false
                ))
            }
        }
        return ScanResult(applications: applications.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, wasLimited: wasLimited)
    }

    static func remove(selected: [UninstallCandidate], protectedPaths: [String]) -> Result<RemovalResult, NSError> {
        let reportURL: URL
        do { reportURL = try writeReport(selected) }
        catch { return .failure(error as NSError) }

        let fileManager = FileManager.default
        var movedIDs = Set<String>()
        var movedSize = 0.0
        var failures: [String] = []
        var movedURLs: [URL] = []
        for candidate in selected.sorted(by: { $0.path.count < $1.path.count }) {
            guard candidate.canRemove else {
                failures.append("(candidate.path)：该项目未通过安全检查")
                continue
            }
            let expanded = (candidate.path as NSString).expandingTildeInPath
            guard fileManager.fileExists(atPath: expanded) else {
                failures.append("(candidate.path)：路径已不存在")
                continue
            }
            let url = URL(fileURLWithPath: expanded)
            guard !UninstallPathPolicy.isSymbolicLink(url) else {
                failures.append("(candidate.path)：符号链接不允许卸载")
                continue
            }
            let canonical = UninstallPathPolicy.canonicalPath(expanded)
            guard canonical == candidate.canonicalPath else {
                failures.append("(candidate.path)：扫描后路径发生变化")
                continue
            }
            if let reason = CleanupPathPolicy.protectionReason(for: canonical, protectedPaths: protectedPaths) {
                failures.append("(candidate.path)：(reason)")
                continue
            }
            if let identifier = candidate.resourceIdentifier,
               UninstallPathPolicyResource.identifier(for: url) != identifier {
                failures.append("(candidate.path)：文件在扫描后已被替换")
                continue
            }
            if movedURLs.contains(where: { canonical == $0.path || canonical.hasPrefix($0.path + "/") }) {
                movedIDs.insert(candidate.id)
                continue
            }
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
                movedIDs.insert(candidate.id)
                movedSize += candidate.size
                movedURLs.append(URL(fileURLWithPath: canonical))
            } catch { failures.append("(candidate.path)：(error.localizedDescription)") }
        }
        appendResult(to: reportURL, movedCount: movedIDs.count, movedSize: movedSize, failures: failures)
        return .success(RemovalResult(movedIDs: movedIDs, movedSize: movedSize, failures: failures, reportURL: reportURL))
    }

    private static func residualCandidates(for appURL: URL, canonical: String, bundleIdentifier: String, applicationSize: Double, deadline: Date) -> [UninstallCandidate] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let entries: [(String, UninstallCandidateCategory, String, UninstallRisk)] = [
            ("Application Support/\(bundleIdentifier)", .support, "目录名称与应用 Bundle ID 完全一致", .review),
            ("Caches/\(bundleIdentifier)", .cache, "目录名称与应用 Bundle ID 完全一致，内容可重建", .safe),
            ("Preferences/\(bundleIdentifier).plist", .preferences, "文件名与应用 Bundle ID 完全一致", .safe),
            ("Saved Application State/\(bundleIdentifier).savedState", .state, "状态目录名称与应用 Bundle ID 完全一致", .safe),
            ("Logs/\(bundleIdentifier)", .logs, "日志目录名称与应用 Bundle ID 完全一致", .safe),
            ("Containers/\(bundleIdentifier)", .container, "沙盒容器名称与应用 Bundle ID 完全一致", .review),
            ("WebKit/\(bundleIdentifier)", .webData, "网页数据目录名称与应用 Bundle ID 完全一致", .review),
            ("HTTPStorages/\(bundleIdentifier)", .webData, "HTTP 存储目录名称与应用 Bundle ID 完全一致", .review),
            ("LaunchAgents/\(bundleIdentifier).plist", .loginItem, "登录项文件名与应用 Bundle ID 完全一致，可能影响开机启动", .review)
        ]
        var candidates = [UninstallCandidate(id: "app-\(canonical)", name: appURL.deletingPathExtension().lastPathComponent, path: CleanupDisplayPath.value(for: canonical), canonicalPath: canonical, category: .application, size: applicationSize, evidence: "扫描到的应用本体；路径位于允许的 Applications 目录", risk: .safe, resourceIdentifier: UninstallPathPolicyResource.identifier(for: appURL), isApplicationBundle: true, scanWarning: nil, isSelected: true)]
        for (relative, category, evidence, risk) in entries {
            guard candidates.count < maxCandidatesPerApp else { break }
            let url = library.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path), UninstallPathPolicy.isUserLibraryCandidate(url) else { continue }
            let path = UninstallPathPolicy.canonicalPath(url.path)
            let measurement = directorySize(url, deadline: deadline)
            let warning = measurement.isTruncated ? "目录读取不完整，无法安全评估" : nil
            candidates.append(UninstallCandidate(id: "residual-\(path)", name: url.lastPathComponent, path: CleanupDisplayPath.value(for: path), canonicalPath: path, category: category, size: bytesToGB(measurement.bytes), evidence: evidence, risk: warning == nil ? risk : .blocked, resourceIdentifier: UninstallPathPolicyResource.identifier(for: url), isApplicationBundle: false, scanWarning: warning, isSelected: warning == nil && risk == .safe))
        }
        return candidates
    }

    private static func blockedApplicationCandidate(url: URL, canonical: String, size: Double, bundleIdentifier: String) -> UninstallCandidate {
        UninstallCandidate(id: "blocked-\(canonical)", name: url.deletingPathExtension().lastPathComponent, path: CleanupDisplayPath.value(for: canonical), canonicalPath: canonical, category: .application, size: size, evidence: "系统应用（\(bundleIdentifier)），为避免破坏 macOS 已禁用卸载", risk: .blocked, resourceIdentifier: UninstallPathPolicyResource.identifier(for: url), isApplicationBundle: true, scanWarning: "系统应用不可卸载", isSelected: false)
    }

    private static func directorySize(_ url: URL, deadline: Date) -> (bytes: UInt64, isTruncated: Bool) {
        let fm = FileManager.default
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileAllocatedSizeKey, .fileSizeKey]), values.isDirectory != true {
            return (UInt64(values.fileAllocatedSize ?? values.fileSize ?? 0), false)
        }
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .fileSizeKey], options: [.skipsPackageDescendants]) else { return (0, true) }
        var total: UInt64 = 0
        var count = 0
        for case let child as URL in enumerator {
            if Task.isCancelled || Date() >= deadline || count > 100_000 { return (total, true) }
            count += 1
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .fileSizeKey]) else { return (total, true) }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isDirectory != true { total += UInt64(values.fileAllocatedSize ?? values.fileSize ?? 0) }
        }
        return (total, false)
    }

    private static func bytesToGB(_ bytes: UInt64) -> Double { Double(bytes) / 1_000_000_000 }

    private static func writeReport(_ candidates: [UninstallCandidate]) throws -> URL {
        let fm = FileManager.default
        let directory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CleanMyMac/Reports", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = directory.appendingPathComponent("uninstall-report-\(formatter.string(from: .now))-\(UUID().uuidString.prefix(8)).txt")
        var lines = ["\(ProductIdentity.displayName) 应用卸载审核报告", "生成时间：\(Date.now.formatted(date: .abbreviated, time: .standard))", "", "执行方式：选中项目会被移入 macOS 废纸篓，可恢复。"]
        for (index, candidate) in candidates.enumerated() { lines += ["", "\(index + 1). \(candidate.name)", "分类：\(candidate.category.rawValue)", "路径：\(candidate.path)", "占用：\(String(format: "%.2f GB", candidate.size))", "归属依据：\(candidate.evidence)", "风险：\(candidate.risk.rawValue)"] }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    private static func appendResult(to url: URL, movedCount: Int, movedSize: Double, failures: [String]) {
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }; try? handle.seekToEnd()
        let lines = ["", "执行结果", "成功移入废纸篓：\(movedCount)", String(format: "实际处理：%.2f GB", movedSize), "失败项目：\(failures.count)"] + failures.map { "- \($0)" }
        try? handle.write(contentsOf: (lines.joined(separator: "\n") + "\n").data(using: .utf8) ?? Data())
    }
}

private enum UninstallPathPolicyResource {
    static func identifier(for url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier).map(String.init(describing:))
    }
}
