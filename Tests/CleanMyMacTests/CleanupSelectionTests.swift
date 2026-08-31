import XCTest
@testable import CleanMyMac

@MainActor
final class CleanupSelectionTests: XCTestCase {
    func testSelectAllSkipsIncompleteScanResult() {
        let model = AppModel()
        model.groups = [group()]
        model.cleanupDetails = [
            "test": [
                item(id: "safe"),
                item(id: "partial", warning: "仅显示已读取部分")
            ]
        ]

        model.selectAll()

        XCTAssertTrue(model.cleanupDetails["test"]?.first(where: { $0.id == "safe" })?.isSelected == true)
        XCTAssertTrue(model.cleanupDetails["test"]?.first(where: { $0.id == "partial" })?.isSelected == false)
        XCTAssertTrue(model.groups[0].isSelected)
    }

    func testDirectToggleCannotSelectIncompleteScanResult() {
        let model = AppModel()
        model.groups = [group()]
        model.cleanupDetails = ["test": [item(id: "partial", warning: "仅显示已读取部分")]]

        model.toggleItem(groupID: "test", itemID: "partial")

        XCTAssertTrue(model.cleanupDetails["test"]?.first?.isSelected == false)
    }

    func testGroupSelectionIgnoresIncompleteItems() {
        let model = AppModel()
        model.groups = [group()]
        model.cleanupDetails = ["test": [item(id: "safe"), item(id: "partial", warning: "仅显示已读取部分")]]

        model.toggleItem(groupID: "test", itemID: "safe")

        XCTAssertTrue(model.groups[0].isSelected)
    }

    private func group() -> CleanupGroup {
        CleanupGroup(
            id: "test",
            title: "测试",
            detail: "测试",
            symbol: "folder",
            tint: .blue,
            size: 0,
            itemCount: 0,
            isSelected: false,
            risk: "安全项"
        )
    }

    private func item(id: String, warning: String? = nil) -> CleanupItem {
        CleanupItem(
            id: id,
            name: id,
            path: "~/Library/Caches/\(id)",
            size: 1,
            reason: "测试",
            reviewLevel: "低风险",
            scanWarning: warning,
            isSelected: false
        )
    }
}
