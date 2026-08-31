import Foundation

enum CleanupStableID {
    static func value(for path: String) -> String {
        path.utf8.reduce(UInt64(5381)) { ($0 &* 33) ^ UInt64($1) }.description
    }
}

enum CleanupDisplayPath {
    static func value(for path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~", options: [.anchored])
    }
}
