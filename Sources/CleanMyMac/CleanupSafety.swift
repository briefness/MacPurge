import Foundation

enum CleanupPathPolicy {
    static func containsGlobMeta(_ path: String) -> Bool {
        path.contains("*") || path.contains("?") || path.contains("[") || path.contains("]")
    }

    static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    static func unsafeReason(for path: String, homeDirectory: String = NSHomeDirectory()) -> String? {
        let candidate = canonicalPath(path)
        let home = canonicalPath(homeDirectory)
        let forbiddenExact = Set([
            "/", home,
            "\(home)/Desktop", "\(home)/Documents", "\(home)/Downloads",
            "\(home)/Library", "\(home)/Movies", "\(home)/Music",
            "\(home)/Pictures", "\(home)/Public",
            "/Applications", "/Library", "/System", "/Users", "/Volumes",
            "/bin", "/etc", "/private", "/sbin", "/tmp", "/usr", "/var"
        ].map(canonicalPath))
        if forbiddenExact.contains(candidate) {
            return "该路径是受保护的根目录"
        }
        let forbiddenPrefixes = ["/Applications", "/Library", "/System", "/Volumes", "/bin", "/etc", "/private", "/sbin", "/tmp", "/usr", "/var"]
        if forbiddenPrefixes.contains(where: { candidate.hasPrefix($0 + "/") }) {
            return "该路径位于受保护的系统目录"
        }
        let usersRoot = canonicalPath("/Users")
        if isDescendant(candidate, of: usersRoot),
           candidate != home,
           !isDescendant(candidate, of: home) {
            return "不能处理其他用户的个人目录"
        }
        return nil
    }

    static func protectionReason(for candidatePath: String, protectedPaths: [String]) -> String? {
        let candidate = canonicalPath(candidatePath)
        for rawProtectedPath in protectedPaths {
            guard !rawProtectedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let protected = canonicalPath(rawProtectedPath)
            if candidate == protected ||
                isDescendant(candidate, of: protected) ||
                isDescendant(protected, of: candidate) {
                return "该路径与保护列表中的 \(rawProtectedPath) 重叠"
            }
        }
        return nil
    }

    private static func isDescendant(_ candidate: String, of parent: String) -> Bool {
        parent == "/" ? candidate.hasPrefix("/") && candidate != "/" : candidate.hasPrefix(parent + "/")
    }

    static func resourceIdentifier(for url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey])
        return values?.fileResourceIdentifier.map { String(describing: $0) }
    }

    static func validationFailure(
        for path: String,
        scannedCanonicalPath: String?,
        scannedResourceIdentifier: String?,
        protectedPaths: [String],
        fileManager: FileManager = .default,
        resourceIdentifierProvider: @Sendable (URL) -> String? = { resourceIdentifier(for: $0) }
    ) -> String? {
        guard !containsGlobMeta(path) else { return "路径仍包含通配符" }
        let expanded = (path as NSString).expandingTildeInPath
        guard fileManager.fileExists(atPath: expanded) else { return "路径已不存在" }
        let sourceURL = URL(fileURLWithPath: expanded)
        let values = try? sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink != true else { return "路径是符号链接" }

        let canonical = canonicalPath(expanded)
        if let reason = unsafeReason(for: canonical) { return reason }
        if let reason = protectionReason(for: canonical, protectedPaths: protectedPaths) { return reason }
        if let scannedCanonicalPath, canonical != scannedCanonicalPath {
            return "路径在扫描后发生变化"
        }
        if let scannedResourceIdentifier {
            guard let currentIdentifier = resourceIdentifierProvider(URL(fileURLWithPath: canonical)) else {
                return "无法确认文件身份，已停止清理"
            }
            if currentIdentifier != scannedResourceIdentifier {
                return "文件在扫描后已被替换"
            }
        }
        return nil
    }
}
