import SwiftUI
import AppKit
import Foundation

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            Divider().overlay(Color.white.opacity(0.06))
            VStack(spacing: 0) {
                WindowBar()
                Group {
                    switch model.section {
                    case .overview: OverviewView()
                    case .clean: CleanView()
                    case .uninstall: UninstallView()
                    case .trash: TrashView()
                    case .analyze: AnalyzeView()
                    case .optimize: OptimizeView()
                    case .protected: ProtectedView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Color.cmmBackground)
        .preferredColorScheme(.dark)
        .alert("清理已选文件？", isPresented: $model.showCleanConfirmation) {
            Button("取消", role: .cancel) { }
            Button("移入废纸篓", role: .destructive) { model.cleanSelected() }
        } message: {
            Text("将把已选的 \(model.selectedItems) 个项目移入 macOS 废纸篓（可恢复），预计释放 \(String(format: "%.2f GB", model.selectedSize))。保护路径始终会被排除。")
        }
        .alert("文件位置说明", isPresented: Binding(
            get: { model.pathNotice != nil },
            set: { if !$0 { model.pathNotice = nil } }
        )) {
            Button("知道了", role: .cancel) { model.pathNotice = nil }
        } message: {
            Text(model.pathNotice ?? "")
        }
        .alert("移入废纸篓？", isPresented: $model.showAnalyzerTrashConfirmation) {
            Button("取消", role: .cancel) { model.pendingAnalyzerTrash = nil }
            Button("移入废纸篓", role: .destructive) { model.movePendingAnalyzerEntryToTrash() }
        } message: {
            Text("将把“\(model.pendingAnalyzerTrash?.name ?? "该项目")”移入 macOS 废纸篓，可从废纸篓恢复。系统目录和保护路径不会被处理。")
        }
        .alert("永久删除废纸篓项目？", isPresented: $model.showEmptyTrashConfirmation) {
            Button("取消", role: .cancel) { }
            Button("永久删除", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("将永久删除已选的 \(model.trashEntries.filter(\.isSelected).count) 个项目，无法从废纸篓恢复。请确认其中没有需要找回的文件。")
        }
        .alert("移除已选应用？", isPresented: $model.showUninstallConfirmation) {
            Button("取消", role: .cancel) { }
            Button("移入废纸篓", role: .destructive) { model.uninstallSelected() }
        } message: {
            Text("将把 \(model.selectedUninstallCount) 个项目移入 macOS 废纸篓，预计 \(String(format: "%.2f GB", model.selectedUninstallSize))。应用本体和残留均可从废纸篓恢复；系统应用和无法确认归属的项目不会处理。")
        }
        .alert("恢复默认设置？", isPresented: $model.showResetPreferencesConfirmation) {
            Button("取消", role: .cancel) { }
            Button("恢复默认", role: .destructive) { model.resetPreferences() }
        } message: {
            Text("将清空保护列表、将项目产物推荐天数恢复为 7 天，并关闭启动时自动扫描。扫描结果、报告文件和已移入废纸篓的项目不会受到影响。")
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.mint.gradient)
                    Image(systemName: "sparkles").font(.system(size: 17, weight: .bold)).foregroundStyle(.black.opacity(0.78))
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ProductIdentity.displayName).font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("原生 macOS 版").font(.system(size: 8, weight: .bold, design: .rounded)).tracking(1.5).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 28)

            Text("工作区").sectionLabel().padding(.horizontal, 18).padding(.bottom, 10)
            VStack(spacing: 4) {
                ForEach(AppSection.allCases) { item in
                    SidebarItem(section: item, selected: model.section == item) { model.section = item }
                }
            }
            .padding(.horizontal, 10)
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Circle().fill(Color.mint).frame(width: 7, height: 7)
                    Text("保护已启用").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Text(model.systemSummary).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
            }
            .padding(18)
        }
        .frame(width: 225)
        .background(Color.cmmSidebar)
    }
}

struct SidebarItem: View {
    let section: AppSection
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.symbol).font(.system(size: 14, weight: .semibold)).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                    Text(section.subtitle).font(.system(size: 10)).foregroundStyle(selected ? .white.opacity(0.66) : .secondary)
                }
                Spacer()
            }
            .foregroundStyle(selected ? .white : .secondary)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(selected ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .leading) { if selected { Capsule().fill(Color.mint).frame(width: 3, height: 25).offset(x: -2) } }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct WindowBar: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack {
            HStack(spacing: 7) {
                Circle().fill(Color.red.opacity(0.85)).frame(width: 10, height: 10)
                Circle().fill(Color.yellow.opacity(0.85)).frame(width: 10, height: 10)
                Circle().fill(Color.green.opacity(0.85)).frame(width: 10, height: 10)
            }
            Spacer()
            if model.isScanning {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small).tint(.mint)
                    Text("正在扫描 Mac…").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Button("停止") { model.cancelScan() }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            } else if let date = model.lastScan {
                Text("上次扫描于 \(date, style: .relative)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button { model.scan() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold)).frame(width: 30, height: 30) }
                .buttonStyle(.plain).background(Color.white.opacity(0.07), in: Circle()).help("扫描 Mac")
                .accessibilityLabel("扫描 Mac")
                .disabled(model.isFilesystemBusy)
        }
        .padding(.horizontal, 20).padding(.vertical, 13)
        .background(Color.cmmBackground.opacity(0.97))
    }
}

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "MAC 健康", title: "从这里开始，让 Mac 更清爽。", description: "了解哪些内容可以安全移除，掌握空间去向，并控制每一次操作。") {
                    Button { model.scan() } label: { Label(model.isScanning ? "扫描中…" : "扫描 Mac", systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black).controlSize(.large).disabled(model.isFilesystemBusy)
                }
                HealthCard()
                PermissionCard()
                HStack(spacing: 16) {
                    MetricCard(label: "可释放空间", value: String(format: "%.2f GB", model.selectedSize), detail: model.hasScanned ? "来自本次扫描" : "扫描后统计", symbol: "arrow.down.to.line.compact", color: .mint)
                    MetricCard(label: "磁盘已用", value: model.diskUsedText, detail: model.diskTotalText, symbol: "internaldrive.fill", color: .indigo)
                    MetricCard(label: "内存占用", value: model.memoryUsedText, detail: model.memoryTotalText, symbol: "memorychip.fill", color: .orange)
                }
                QuickActions()
            }
            .padding(34)
        }
    }
}

struct PageHeader<Actions: View>: View {
    let eyebrow: String
    let title: String
    let description: String
    @ViewBuilder let actions: () -> Actions
    init(eyebrow: String, title: String, description: String, @ViewBuilder actions: @escaping () -> Actions) { self.eyebrow = eyebrow; self.title = title; self.description = description; self.actions = actions }
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow).sectionLabel().foregroundStyle(.mint)
                Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
                Text(description).font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: 560, alignment: .leading)
            }
            Spacer()
            actions()
        }
    }
}

struct HealthCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack(spacing: 26) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 12)
                Circle().trim(from: 0, to: model.isScanning ? model.scanProgress : Double(model.scanCoverageScore ?? 0) / 100).stroke(Color.mint.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90)).animation(.easeInOut(duration: 0.25), value: model.scanProgress)
                VStack(spacing: 1) { Text(model.isScanning ? "扫描中" : (model.scanCoverageScore.map { "\($0)%" } ?? "--")).font(.system(size: model.isScanning ? 17 : 28, weight: .bold, design: .rounded)).contentTransition(.numericText()); Text("权限覆盖").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(.secondary) }
            }.frame(width: 126, height: 126)
            VStack(alignment: .leading, spacing: 11) {
                Text(model.isScanning ? "正在读取本机目录…" : (model.hasScanned ? "扫描完成，结果来自本机实际目录。" : "还没有扫描结果")).font(.system(size: 19, weight: .semibold, design: .rounded))
                Text(model.isScanning ? "扫描完成前不会显示可释放空间结果。" : (model.hasScanned ? "可释放空间仅统计当前账号可读取且未被保护的路径。" : "点击“扫描 Mac”开始读取本机数据；未授权位置不会被估算。")).font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: 500, alignment: .leading)
                HStack(spacing: 15) { StatusPill(text: "保护路径已排除", color: .mint); StatusPill(text: "不处理个人文档", color: .blue); StatusPill(text: model.systemSummary, color: .indigo) }
            }
            Spacer()
        }
        .padding(24).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07)))
    }
}

struct PermissionCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("扫描权限覆盖").font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("先用基础权限开始；深度扫描前再按需授权").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isCheckingPermissions {
                    ProgressView().controlSize(.small).tint(.mint)
                } else {
                    Text("\(model.availablePermissionCount)/\(model.detectedPermissionCount) 个实际位置已覆盖")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(model.authorizationNeededCount == 0 ? Color.mint : Color.orange)
                }
            }

            VStack(spacing: 7) {
                ForEach(model.permissionScopes) { scope in
                    PermissionScopeRow(scope: scope)
                }
            }

            HStack(spacing: 9) {
                Button { model.beginDeepScan() } label: {
                    Label("开始深度扫描", systemImage: "lock.open.rotation")
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .foregroundStyle(.black)
                .controlSize(.small)

                Button { model.openSystemSettings() } label: {
                    Label("打开系统设置", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button { model.chooseScanFolder() } label: {
                    Label("选择文件夹", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button { model.checkPermissions() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("重新检测权限")
                .accessibilityLabel("重新检测权限")
            }

            if let message = model.permissionMessage {
                Label(message, systemImage: model.deepAuthorizationNeeded ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(model.deepAuthorizationNeeded ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = model.scanMessage {
                Label(message, systemImage: "scope")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.white.opacity(0.07)))
        .onAppear { model.checkPermissions() }
    }
}

struct PermissionScopeRow: View {
    let scope: PermissionScope

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: scope.state.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(scope.state.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(scope.title).font(.system(size: 11, weight: .medium))
                    if scope.requiresFullDiskAccess {
                        Text("深度扫描")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }
                Text(scope.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            Text(scope.state.title).font(.system(size: 10, weight: .medium)).foregroundStyle(scope.state.tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .help(scope.detail)
    }
}

struct StatusPill: View { let text: String; let color: Color; var body: some View { HStack(spacing: 6) { Circle().fill(color).frame(width: 6, height: 6); Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary) } } }

struct MetricCard: View { let label: String; let value: String; let detail: String; let symbol: String; let color: Color; var body: some View { VStack(alignment: .leading, spacing: 15) { HStack { Image(systemName: symbol).foregroundStyle(color).frame(width: 28, height: 28).background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 8)); Spacer(); Text(label).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(.tertiary) }; HStack(alignment: .firstTextBaseline, spacing: 7) { Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit(); Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) } }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 13)) } }

struct QuickActions: View { @EnvironmentObject var model: AppModel; var body: some View { VStack(alignment: .leading, spacing: 12) { Text("快捷操作").sectionLabel(); HStack(spacing: 12) { QuickAction(title: "审核清理", detail: "\(model.selectedItems) 个项目待处理", symbol: "wand.and.stars", color: .mint) { model.section = .clean }; QuickAction(title: "探索空间", detail: "找出占用最大的文件夹", symbol: "chart.pie.fill", color: .indigo) { model.section = .analyze }; QuickAction(title: "优化性能", detail: "\(model.optimizeTasks.filter { !$0.completed }.count) 个系统任务可执行", symbol: "gauge.with.dots.needle.67percent", color: .orange) { model.section = .optimize } } } } }
struct QuickAction: View { let title: String; let detail: String; let symbol: String; let color: Color; let action: () -> Void; var body: some View { Button(action: action) { HStack(spacing: 12) { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(color).frame(width: 33, height: 33).background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 9)); VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 13, weight: .semibold)); Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.tertiary) } .padding(13).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain).frame(maxWidth: .infinity) } }

struct CleanView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(eyebrow: "清理空间", title: "先审核，再执行。", description: "所有分类都会拆分到具体来源、产物类型和路径，展开后逐项查看占用大小、风险与清理原因；保护路径始终会被排除。") { EmptyView() }
                .padding(34).padding(.bottom, 18)
            PermissionSummaryBar()
                .padding(.horizontal, 34).padding(.bottom, 12)
            HStack {
                Text("\(model.groups.count) 个分类").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    Button { model.selectAll() } label: { Label("全选", systemImage: "checkmark.circle.fill") }
                        .buttonStyle(.bordered).controlSize(.small).disabled(model.isScanning || model.isCleaning)
                    Button { model.selectRecommended() } label: { Label("推荐选择", systemImage: "wand.and.stars") }
                        .buttonStyle(.bordered).controlSize(.small).tint(.mint).disabled(model.isScanning || model.isCleaning)
                    Text("已选择 \(String(format: "%.2f GB", model.selectedSize))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(.mint)
                }
            }
            .padding(.horizontal, 34).padding(.bottom, 10)
            ScrollView {
                VStack {
                    if model.groups.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: model.hasScanned ? "checkmark.circle" : "wand.and.stars")
                                .font(.system(size: 30)).foregroundStyle(.secondary)
                            Text(model.hasScanned ? "没有发现可清理项目" : "还没有扫描结果")
                                .font(.system(size: 16, weight: .semibold))
                            Text(model.hasScanned ? "当前授权范围内没有符合规则的实际路径。" : "点击窗口右上角的扫描按钮，读取本机真实目录。")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(50)
                    } else {
                        VStack(spacing: 8) { ForEach(model.groups) { group in CleanupRow(group: group) } }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 34).padding(.bottom, 110)
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("准备释放").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(String(format: "%.2f GB", model.selectedSize)).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                }
                Spacer()
                if let reportPath = model.lastReportPath {
                    Button { model.openPathInFinder(reportPath) } label: {
                        Label("打开最近报告", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if let message = model.cleanupMessage {
                    Label(message, systemImage: model.cleanupMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(model.cleanupMessageIsError ? Color.orange : Color.mint)
                        .lineLimit(2)
                }
                Button { model.requestClean() } label: { Label(model.isCleaning ? "清理中…" : "清理已选文件", systemImage: "trash") }
                    .buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black).disabled(model.isFilesystemBusy || model.selectedItems == 0)
            }
            .padding(.horizontal, 34).padding(.vertical, 17).background(Color.cmmSidebar)
            .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.08)) }
        }
        .onAppear { model.checkPermissions() }
    }
}

struct PermissionSummaryBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.authorizationNeededCount > 0 ? "lock.fill" : "checkmark.shield.fill")
                .foregroundStyle(model.authorizationNeededCount > 0 ? Color.orange : Color.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.authorizationNeededCount > 0 ? "当前为基础扫描" : "扫描权限已覆盖")
                    .font(.system(size: 11, weight: .semibold))
                Text(model.authorizationNeededCount > 0 ? "已覆盖 \(model.availablePermissionCount) 个位置；未授权位置不会计入结果。" : "所有已发现的扫描位置均可读取。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.beginDeepScan() } label: { Text("深度扫描") }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background((model.authorizationNeededCount > 0 ? Color.orange : Color.mint).opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
}
struct CleanupRow: View {
    @EnvironmentObject var model: AppModel
    let group: CleanupGroup
    @State private var isExpanded = true

    private var detailItems: [CleanupItem] { model.cleanupDetails[group.id] ?? [] }
    private var sourceGroups: [CleanupSourceGroup] {
        let grouped = Dictionary(grouping: detailItems) { $0.toolName ?? "未标识来源" }
        return grouped.map { sourceName, items in
            let artifacts = Dictionary(grouping: items) { $0.artifactType ?? "未分类产物" }
                .map { artifactType, artifactItems in
                    CleanupArtifactGroup(
                        id: "\(group.id)-\(sourceName)-\(artifactType)",
                        artifactType: artifactType,
                        items: artifactItems.sorted { $0.path < $1.path }
                    )
                }
                .sorted { $0.artifactType < $1.artifactType }
            return CleanupSourceGroup(
                id: "\(group.id)-\(sourceName)",
                sourceName: sourceName,
                artifactGroups: artifacts
            )
        }.sorted { $0.sourceName < $1.sourceName }
    }

    var body: some View {
        VStack(spacing: 0) {
            let selectableItems = detailItems.filter(\.canClean)
            let allSelected = !selectableItems.isEmpty && selectableItems.allSatisfy(\.isSelected)
            let partiallySelected = selectableItems.contains(where: \.isSelected) && !allSelected
            HStack(spacing: 12) {
                Button { model.toggleGroup(group) } label: {
                    Image(systemName: allSelected ? "checkmark.circle.fill" : partiallySelected ? "minus.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(allSelected ? Color.mint : partiallySelected ? Color.orange : Color.secondary)
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择清理分类 \(group.title)")
                Image(systemName: group.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(group.tint).frame(width: 38, height: 38).background(group.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                Button { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) { Text(group.title).font(.system(size: 14, weight: .semibold)); Text(group.risk).font(.system(size: 10, weight: .medium)).foregroundStyle(group.risk.hasPrefix("全部") ? .mint : .orange).padding(.horizontal, 7).padding(.vertical, 3).background((group.risk.hasPrefix("全部") ? Color.mint : Color.orange).opacity(0.12), in: Capsule()) }
                        Text(group.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("展开或收起清理分类 \(group.title)")
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "%.2f GB", group.size)).font(.system(size: 14, weight: .semibold, design: .monospaced))
                    let detailCount = model.cleanupDetails[group.id]?.count ?? group.itemCount
                    let selectedCount = model.cleanupDetails[group.id]?.filter(\.isSelected).count ?? 0
                    let reviewCount = model.cleanupDetails[group.id]?.filter { item in
                        guard let level = item.reviewLevel else { return false }
                        return level != "可重建" && level != "低风险"
                    }.count ?? 0
                    Text("\(detailCount) 条明细 · \(reviewCount) 项需确认 · 已选 \(selectedCount)")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(.tertiary).frame(width: 24)
            }
            .padding(13)
            if isExpanded {
                VStack(spacing: 0) {
                    HStack {
                        Text("分类 → 工具/项目来源 → 产物类型 → 真实路径").font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("每一级都可独立选择").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                        .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 7)
                    ForEach(sourceGroups) { sourceGroup in
                        CleanupSourceRow(groupID: group.id, sourceGroup: sourceGroup)
                    }
                }
                .background(Color.black.opacity(0.14))
            }
        }
        .background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06)))
    }
}

struct CleanupSourceRow: View {
    @EnvironmentObject var model: AppModel
    let groupID: String
    let sourceGroup: CleanupSourceGroup
    @State private var isExpanded = true

    private var selectableItems: [CleanupItem] { sourceGroup.items.filter(\.canClean) }
    private var allSelected: Bool { !selectableItems.isEmpty && selectableItems.allSatisfy(\.isSelected) }
    private var partiallySelected: Bool { selectableItems.contains(where: \.isSelected) && !allSelected }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.toggleItems(groupID: groupID, itemIDs: sourceGroup.items.map(\.id)) } label: {
                    Image(systemName: allSelected ? "checkmark.square.fill" : partiallySelected ? "minus.square.fill" : "square")
                        .font(.system(size: 16))
                        .foregroundStyle(allSelected ? Color.mint : partiallySelected ? Color.orange : Color.secondary)
                        .frame(width: 22, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择工具或项目来源 \(sourceGroup.sourceName)")
                Button { withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() } } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("展开或收起工具或项目来源 \(sourceGroup.sourceName)")
                Image(systemName: "shippingbox")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 25, height: 25)
                    .background(Color.indigo.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(sourceGroup.sourceName).font(.system(size: 11, weight: .semibold))
                        Text("工具/项目来源").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Text("\(sourceGroup.items.count) 个真实路径 · \(sourceGroup.reviewCount) 项需确认")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Spacer()
                Text(String(format: "%.2f GB", sourceGroup.size))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.035))

                    if isExpanded {
                ForEach(sourceGroup.artifactGroups) { artifactGroup in
                    CleanupArtifactRow(groupID: groupID, artifactGroup: artifactGroup)
                        .padding(.leading, 34)
                }
            }
        }
    }
}

struct CleanupArtifactRow: View {
    @EnvironmentObject var model: AppModel
    let groupID: String
    let artifactGroup: CleanupArtifactGroup
    @State private var isExpanded = true

    private var selectableItems: [CleanupItem] { artifactGroup.items.filter(\.canClean) }
    private var allSelected: Bool { !selectableItems.isEmpty && selectableItems.allSatisfy(\.isSelected) }
    private var partiallySelected: Bool { selectableItems.contains(where: \.isSelected) && !allSelected }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Button { model.toggleItems(groupID: groupID, itemIDs: artifactGroup.items.map(\.id)) } label: {
                    Image(systemName: allSelected ? "checkmark.square.fill" : partiallySelected ? "minus.square.fill" : "square")
                        .font(.system(size: 15))
                        .foregroundStyle(allSelected ? Color.mint : partiallySelected ? Color.orange : Color.secondary)
                        .frame(width: 21, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择产物类型 \(artifactGroup.artifactType)")
                Button { withAnimation(.easeInOut(duration: 0.16)) { isExpanded.toggle() } } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("展开或收起产物类型 \(artifactGroup.artifactType)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(artifactGroup.artifactType).font(.system(size: 11, weight: .semibold))
                    Text("\(artifactGroup.items.count) 个真实路径 · \(artifactGroup.reviewCount) 项需确认")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Spacer()
                Text(String(format: "%.2f GB", artifactGroup.size))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.02))

            if isExpanded {
                ForEach(artifactGroup.items) { item in
                    CleanupDetailRow(groupID: groupID, item: item)
                        .padding(.leading, 34)
                }
            }
        }
    }
}

struct CleanupDetailRow: View {
    @EnvironmentObject var model: AppModel
    let groupID: String
    let item: CleanupItem

    var body: some View {
        HStack(spacing: 10) {
            Button { model.toggleItem(groupID: groupID, itemID: item.id) } label: {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(item.isSelected ? Color.mint : Color.secondary)
                    .frame(width: 23, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!item.canClean)
            Button { model.toggleItem(groupID: groupID, itemID: item.id) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    if let toolName = item.toolName, let artifactType = item.artifactType {
                        HStack(spacing: 7) {
                            Text(toolName).font(.system(size: 11, weight: .semibold)).foregroundStyle(.pink)
                            Text(artifactType).font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
                            if let reviewLevel = item.reviewLevel {
                                Text(reviewLevel)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(reviewLevel == "可重建" || reviewLevel == "低风险" ? Color.mint : Color.orange)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background((reviewLevel == "可重建" || reviewLevel == "低风险" ? Color.mint : Color.orange).opacity(0.12), in: Capsule())
                            }
                        }
                        Text(item.name).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    } else {
                        Text(item.name).font(.system(size: 12, weight: .medium))
                    }
                    Text(item.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                    Text(item.reason).font(.system(size: 10)).foregroundStyle(.orange.opacity(0.9))
                    if item.usesAgeRecommendation,
                       let ageDescription = CleanupRecommendation.ageDescription(
                        reviewLevel: item.reviewLevel,
                        modifiedAt: item.modifiedAt,
                        ageDays: model.artifactRecommendationDays
                       ) {
                        Text(ageDescription)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(item.isSelected ? Color.mint : Color.secondary)
                    }
                    if let scanWarning = item.scanWarning {
                        Text(scanWarning).font(.system(size: 10, weight: .medium)).foregroundStyle(.red.opacity(0.9))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Text(detailStorageSize(item.size)).font(.system(size: 11, weight: .semibold, design: .monospaced))
            Button { model.openPathInFinder(item.path) } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("在访达中显示此位置")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

struct UninstallView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(eyebrow: "应用卸载", title: "连同可确认的残留一起移除。", description: "扫描真实的 Applications 目录，并按 Bundle ID 细分应用本体、缓存、支持数据和后台组件。无法确认归属的项目会单独标记，不会默认删除。") {
                Button { model.scanApplications() } label: { Label(model.isScanningApplications ? "扫描中…" : "扫描应用", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black).disabled(model.isFilesystemBusy)
            }
            .padding(34).padding(.bottom, 12)

            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("所有结果来自本机实际目录").font(.system(size: 11, weight: .semibold))
                    Text("推荐选择只包含应用本体与可重建缓存；支持数据、容器和登录项需要你逐项审核。").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.selectRecommendedUninstallCandidates() } label: { Label("推荐选择", systemImage: "wand.and.stars") }.buttonStyle(.bordered).controlSize(.small).tint(.mint)
                Button { model.selectAllUninstallCandidates() } label: { Label("全选可删除", systemImage: "checkmark.square") }.buttonStyle(.bordered).controlSize(.small)
            }
            .padding(13).background(Color.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 34).padding(.bottom, 12)

            if model.uninstallWasLimited {
                Label("应用数量较多，扫描已达到安全上限；请再次扫描继续读取。", systemImage: "info.circle.fill").font(.system(size: 11)).foregroundStyle(.orange).padding(.horizontal, 34).padding(.bottom, 8)
            }
            if model.isScanningApplications {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large).tint(.mint)
                    Text("正在读取 Applications 目录…").font(.system(size: 13)).foregroundStyle(.secondary)
                    Button("停止扫描") { model.cancelApplicationScan() }.buttonStyle(.bordered).controlSize(.small)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.installedApplications.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "app.dashed").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("还没有应用扫描结果").font(.system(size: 15, weight: .semibold))
                    Text("点击右上角“扫描应用”，读取 /Applications 与 ~/Applications 中的真实应用。").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) { ForEach(model.installedApplications) { app in InstalledApplicationRow(app: app) } }
                        .padding(.horizontal, 34).padding(.bottom, 100)
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("已选择 \(model.selectedUninstallCount) 项").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(String(format: "%.2f GB", model.selectedUninstallSize)).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                }
                Spacer()
                if let path = model.uninstallReportPath { Button { model.openPathInFinder(path) } label: { Label("打开卸载报告", systemImage: "doc.text") }.buttonStyle(.bordered).controlSize(.small) }
                if let message = model.uninstallMessage { Label(message, systemImage: model.uninstallMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(model.uninstallMessageIsError ? Color.orange : Color.mint).lineLimit(2) }
                Button { model.requestUninstall() } label: { Label(model.isUninstalling ? "处理中…" : "移入废纸篓", systemImage: "trash") }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black).disabled(model.isFilesystemBusy || model.selectedUninstallCount == 0)
            }
            .padding(.horizontal, 34).padding(.vertical, 15).background(Color.cmmSidebar)
        }
        .onAppear { if model.installedApplications.isEmpty { model.scanApplications() } }
    }
}

struct InstalledApplicationRow: View {
    @EnvironmentObject private var model: AppModel
    let app: InstalledApplication
    var body: some View {
        VStack(spacing: 0) {
            Button { model.toggleApplication(app) } label: {
                HStack(spacing: 12) {
                    if let iconPath = app.iconPath, let image = NSImage(contentsOfFile: iconPath) { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 8)) }
                    else { Image(systemName: "app.fill").font(.system(size: 22)).foregroundStyle(.mint).frame(width: 34, height: 34) }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(app.name).font(.system(size: 13, weight: .semibold))
                            Text(app.version).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            if app.isRunning { Text("正在运行").font(.system(size: 9, weight: .medium)).foregroundStyle(.orange).padding(.horizontal, 5).padding(.vertical, 2).background(Color.orange.opacity(0.12), in: Capsule()) }
                            if app.isSystemApplication { Text("系统应用").font(.system(size: 9, weight: .medium)).foregroundStyle(.red).padding(.horizontal, 5).padding(.vertical, 2).background(Color.red.opacity(0.12), in: Capsule()) }
                        }
                        Text("\(app.bundleIdentifier) · \(app.path)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) { Text(detailStorageSize(app.size)).font(.system(size: 11, weight: .semibold, design: .monospaced)); Text("\(app.candidates.count) 个关联项目").font(.system(size: 10)).foregroundStyle(.secondary) }
                    Image(systemName: app.isExpanded ? "chevron.down" : "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.tertiary)
                }.padding(14)
            }.buttonStyle(.plain)
            if app.isExpanded { VStack(spacing: 0) { ForEach(app.candidates) { candidate in UninstallCandidateRow(appID: app.id, candidate: candidate) } }.padding(.leading, 26).padding(.bottom, 8) }
        }
        .background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.07)))
    }
}

struct UninstallCandidateRow: View {
    @EnvironmentObject private var model: AppModel
    let appID: String
    let candidate: UninstallCandidate
    var body: some View {
        HStack(spacing: 10) {
            Button { model.toggleUninstallCandidate(appID: appID, candidateID: candidate.id) } label: { Image(systemName: candidate.isSelected ? "checkmark.circle.fill" : "circle").font(.system(size: 16)).foregroundStyle(candidate.isSelected ? Color.mint : Color.secondary) }.buttonStyle(.plain).accessibilityLabel(candidate.isSelected ? "取消选择 \(candidate.name)" : "选择 \(candidate.name)").disabled(!candidate.canRemove)
            Image(systemName: candidate.category.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(candidate.risk == .safe ? Color.mint : candidate.risk == .review ? Color.orange : Color.red).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) { Text(candidate.category.rawValue).font(.system(size: 11, weight: .semibold)); Text(candidate.risk.rawValue).font(.system(size: 9, weight: .medium)).foregroundStyle(candidate.risk == .safe ? Color.mint : candidate.risk == .review ? Color.orange : Color.red) }
                Text(candidate.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                Text(candidate.evidence).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                if let warning = candidate.scanWarning { Text(warning).font(.system(size: 10, weight: .medium)).foregroundStyle(.red.opacity(0.9)) }
            }
            Spacer()
            Text(detailStorageSize(candidate.size)).font(.system(size: 11, weight: .semibold, design: .monospaced))
            Button { model.openPathInFinder(candidate.path) } label: { Image(systemName: "folder") }.buttonStyle(.bordered).controlSize(.small).help("在访达中显示此位置").accessibilityLabel("在访达中显示 \(candidate.name)")
        }.padding(.horizontal, 12).padding(.vertical, 9).background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 8)).padding(.trailing, 12)
    }
}

struct TrashView: View {
    @EnvironmentObject private var model: AppModel

    private var selectedEntries: [TrashEntry] { model.trashEntries.filter(\.isSelected) }
    private var selectedSize: Double { selectedEntries.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                eyebrow: "废纸篓",
                title: "确认无用后，再永久删除。",
                description: "这里的项目已经在系统或外接磁盘废纸篓中。永久删除后无法恢复，因此不会自动执行。"
            ) {
                Button { model.scanTrash() } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(model.isScanningTrash)
            }
            .padding(34)
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                Label("不可恢复操作", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                Text("默认不选择任何项目；扫描不完整的目录不会被选中。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { model.selectAllTrash() } label: {
                    Label("选择完整项目", systemImage: "checkmark.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isScanningTrash || model.isDeletingTrash || model.trashEntries.allSatisfy { $0.isSelected || $0.isTruncated })
                Text("已选 \(selectedEntries.count) 项 · \(detailStorageSize(selectedSize))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 34).padding(.bottom, 12)

            if model.isScanningTrash {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large).tint(.orange)
                    Text("正在读取废纸篓…").font(.system(size: 13)).foregroundStyle(.secondary)
                    Button("停止扫描") { model.cancelTrashScan() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if model.trashEntries.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: model.trashAccessDenied ? "lock.trianglebadge.exclamationmark" : "trash")
                                    .font(.system(size: 32)).foregroundStyle(model.trashAccessDenied ? Color.orange : Color.secondary)
                                Text(model.trashAccessDenied ? "无法读取废纸篓" : "没有发现废纸篓项目")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(model.trashAccessDenied ? "macOS 拒绝读取当前账号的废纸篓目录；这不代表废纸篓为空。" : "当前账号的废纸篓目录为空。")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                if model.trashAccessDenied {
                                    Button { model.openSystemSettings() } label: {
                                        Label("打开完全磁盘访问权限", systemImage: "lock.open")
                                    }
                                    .buttonStyle(.borderedProminent).tint(.orange).foregroundStyle(.black).controlSize(.small)
                                }
                            }
                            .frame(maxWidth: .infinity).padding(50)
                        } else {
                            ForEach(model.trashEntries) { entry in
                                HStack(spacing: 12) {
                                    Button { model.toggleTrashEntry(entry) } label: {
                                        Image(systemName: entry.isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18)).foregroundStyle(entry.isSelected ? Color.orange : Color.secondary)
                                    }
                                    .buttonStyle(.plain).disabled(!entry.canDelete)
                                    Image(systemName: "trash.fill").foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 7) {
                                            Text(entry.name).font(.system(size: 12, weight: .semibold))
                                            Text(entry.volumeName).font(.system(size: 9)).foregroundStyle(.secondary)
                                            if entry.isTruncated { Text("部分读取，不可删除").font(.system(size: 9)).foregroundStyle(.orange) }
                                            else if entry.resourceIdentifier == nil { Text("无法确认身份，不可删除").font(.system(size: 9)).foregroundStyle(.orange) }
                                        }
                                        Text(entry.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(detailStorageSize(entry.size)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    Button { model.openPathInFinder(entry.path) } label: { Image(systemName: "folder") }
                                        .buttonStyle(.bordered).controlSize(.small).help("在访达中显示").accessibilityLabel("在访达中显示 \(entry.name)")
                                }
                                .padding(13).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.horizontal, 34).padding(.bottom, 90)
                }
            }

            HStack {
                if let message = model.trashMessage {
                    Label(message, systemImage: "info.circle.fill").font(.system(size: 11)).foregroundStyle(.orange)
                }
                Spacer()
                Button { model.requestEmptyTrash() } label: {
                    Label(model.isDeletingTrash ? "删除中…" : "永久删除已选项目", systemImage: "trash.slash.fill")
                }
                .buttonStyle(.borderedProminent).tint(.orange).foregroundStyle(.black)
                .disabled(model.isFilesystemBusy || selectedEntries.isEmpty)
            }
            .padding(.horizontal, 34).padding(.vertical, 15).background(Color.cmmSidebar)
        }
        .onAppear { model.scanTrash() }
    }
}

struct AnalyzeView: View {
    @EnvironmentObject private var model: AppModel

    private var visibleTotal: Double { model.analyzerEntries.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                eyebrow: "空间透镜",
                title: "逐层找到空间去向。",
                description: "从启动磁盘或任意文件夹开始，按真实占用排序进入子目录；分析本身只读。"
            ) {
                HStack(spacing: 8) {
                    Button { model.chooseAnalyzeFolder() } label: {
                        Label("选择文件夹", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    Button { model.analyzeDirectory() } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isAnalyzing)
                }
            }
            .padding(34)
            .padding(.bottom, 12)

            HStack(spacing: 10) {
                Button { model.analyzeParentDirectory() } label: {
                    Image(systemName: "arrow.up")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled((model.analyzerPath as NSString).expandingTildeInPath == "/")
                .help("返回上级目录")

                Image(systemName: "folder.fill").foregroundStyle(.indigo)
                Text(model.analyzerPath)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(model.analyzerEntries.count) 项 · \(detailStorageSize(visibleTotal))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 12)

            if model.isAnalyzing {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large).tint(.mint)
                    Text("正在读取目录实际占用…").font(.system(size: 13)).foregroundStyle(.secondary)
                    Button("停止分析") { model.cancelAnalysis() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if model.analyzerEntries.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "folder").font(.system(size: 32)).foregroundStyle(.secondary)
                                Text("尚未分析目录").font(.system(size: 15, weight: .semibold))
                                Text("点击“刷新”分析启动磁盘，或选择一个文件夹开始。")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity).padding(50)
                        } else {
                            ForEach(Array(model.analyzerEntries.enumerated()), id: \.element.id) { index, entry in
                                AnalyzerEntryRow(
                                    entry: entry,
                                    total: max(visibleTotal, entry.size),
                                    tint: [.indigo, .mint, .orange, .pink, .blue][index % 5]
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 34)
                    .padding(.bottom, 30)
                }
            }

            if let message = model.analyzerMessage {
                Label(message, systemImage: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cmmSidebar)
            }
        }
    }
}

struct AnalyzerEntryRow: View {
    @EnvironmentObject private var model: AppModel
    let entry: AnalyzerEntry
    let total: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 11) {
                Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundStyle(tint)
                    .frame(width: 31, height: 31)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                Button {
                    model.enterAnalyzerEntry(entry)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(entry.name).font(.system(size: 13, weight: .semibold))
                            if entry.isProtected {
                                Label("受保护", systemImage: "checkmark.shield.fill")
                                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.mint)
                            }
                            if entry.isTruncated {
                                Text("部分读取").font(.system(size: 9, weight: .medium)).foregroundStyle(.orange)
                            }
                        }
                        Text(entry.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(!entry.isDirectory)

                Text(detailStorageSize(entry.size))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))

                Button { model.openPathInFinder(entry.path) } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered).controlSize(.small).help("在访达中显示")

                Button { model.requestAnalyzerTrash(entry) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(!entry.canMoveToTrash || model.isFilesystemBusy)
                .help(entry.isProtected ? "系统或保护路径不能删除" : entry.isTruncated ? "扫描不完整，不能删除" : "移入废纸篓")
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().fill(tint.gradient)
                        .frame(width: total > 0 ? proxy.size.width * entry.size / total : 0)
                }
            }
            .frame(height: 5)
        }
        .padding(13)
        .background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 10))
    }
}
struct OptimizeView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "优化维护", title: "先看状态，再做必要维护。", description: "基于本机实时状态给出可执行操作；macOS 自动管理的能力会明确说明，不伪造成一键优化。") {
                    HStack(spacing: 8) {
                        Button { model.refreshOptimizationData() } label: { Label("刷新状态", systemImage: "arrow.clockwise") }
                            .buttonStyle(.bordered)
                            .disabled(model.isRefreshingSystemData || model.isOptimizing)
                        Button { model.runOptimizations() } label: { Label("执行已选任务", systemImage: "bolt.fill") }
                            .buttonStyle(.borderedProminent).tint(.orange).foregroundStyle(.black)
                            .disabled(model.isOptimizing || !model.optimizeTasks.contains(where: { $0.selected && !$0.completed }))
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("当前状态").sectionLabel()
                    HStack(spacing: 10) {
                        OptimizeMetricCard(
                            title: "可用内存",
                            value: model.memoryFreePercent.map { "\($0)%" } ?? "--",
                            detail: model.memoryUsed.map { String(format: "已使用 %.2f GB", $0) } ?? "等待读取",
                            symbol: "memorychip.fill",
                            tint: .mint
                        )
                        OptimizeMetricCard(
                            title: "交换空间",
                            value: model.swapUsed.map { String(format: "%.2f GB", $0) } ?? "--",
                            detail: model.swapTotal.map { String(format: "总计 %.2f GB", $0) } ?? "等待读取",
                            symbol: "arrow.left.arrow.right",
                            tint: .orange
                        )
                        OptimizeMetricCard(
                            title: "系统可调度空间",
                            value: model.purgeableEstimate.map { String(format: "%.2f GB", $0) } ?? "--",
                            detail: "空间不足时由 macOS 自动释放",
                            symbol: "internaldrive.fill",
                            tint: .indigo
                        )
                        OptimizeMetricCard(
                            title: "连续运行",
                            value: model.uptimeText,
                            detail: model.backgroundItemCount > 0 ? "发现 \(model.backgroundItemCount) 个后台启动项" : "未发现后台启动项",
                            symbol: "clock.fill",
                            tint: .pink
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("可执行维护").sectionLabel()
                        Spacer()
                        Text("选择后统一执行").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                if model.optimizeTasks.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "checkmark.circle").font(.system(size: 28)).foregroundStyle(.secondary)
                        Text("当前系统没有可用的非特权维护命令").font(.system(size: 15, weight: .semibold))
                        Text("未检测到可安全执行的 macOS 工具，因此不会显示虚构任务。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 650).padding(44).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 9) {
                        ForEach(model.optimizeTasks.indices, id: \.self) { index in
                            OptimizeRow(task: $model.optimizeTasks[index])
                        }
                    }
                }
                }

                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.badge.clock")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(.mint)
                        .frame(width: 42, height: 42).background(Color.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("启动与后台项").font(.system(size: 14, weight: .semibold))
                        Text(model.backgroundItemCount > 0 ? "检测到 \(model.backgroundItemCount) 个用户或系统级启动代理，可前往系统设置审核。" : "当前扫描范围内没有发现启动代理。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.openLoginItemsSettings() } label: { Label("管理登录项", systemImage: "arrow.up.forward.app") }
                        .buttonStyle(.bordered)
                }
                .padding(16).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 12))

                if let message = model.optimizeMessage {
                    Label(message, systemImage: "info.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.indigo)
                    Text("任务是否执行成功以 macOS 命令返回结果为准，不会用静态数据填充。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(15).background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
            }
            .padding(34)
        }
        .onAppear { model.refreshOptimizationData() }
    }
}

struct OptimizeMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol).foregroundStyle(tint)
                Spacer()
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1)
            Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(2).frame(minHeight: 25, alignment: .topLeading)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 10))
    }
}
struct OptimizeRow: View { @EnvironmentObject private var model: AppModel; @Binding var task: OptimizeTask; var body: some View { HStack(spacing: 13) { Image(systemName: task.symbol).foregroundStyle(task.tint).frame(width: 38, height: 38).background(task.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading, spacing: 4) { Text(task.title).font(.system(size: 14, weight: .semibold)); Text(task.detail).font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); if task.completed { Label("已完成", systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(.mint) } else { Toggle("", isOn: $task.selected).labelsHidden().toggleStyle(.switch).tint(.mint).disabled(model.isOptimizing) } }.padding(14).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 12)) } }

struct ProtectedView: View {
    @EnvironmentObject var model: AppModel
    @State private var newPath = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(eyebrow: "保护列表", title: "永久不触碰的路径。", description: "只有你主动加入的真实路径会显示在这里，并从清理结果中排除。") { EmptyView() }
            HStack(spacing: 10) {
                TextField("输入真实路径，例如 ~/Documents/重要项目", text: $newPath)
                    .textFieldStyle(.plain).padding(12).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 10))
                Button {
                    let trimmed = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    let expanded = (trimmed as NSString).expandingTildeInPath
                    guard !trimmed.isEmpty, FileManager.default.fileExists(atPath: expanded) else { return }
                    let canonical = CleanupPathPolicy.canonicalPath(expanded)
                    let existingCanonical = Set(model.protectedPaths.map(CleanupPathPolicy.canonicalPath))
                    guard !existingCanonical.contains(canonical) else { return }
                    let displayPath = canonical.replacingOccurrences(of: NSHomeDirectory(), with: "~", options: [.anchored])
                    model.protectedPaths.append(displayPath)
                    UserDefaults.standard.set(model.protectedPaths, forKey: "cleanmymac.protectedPaths")
                    newPath = ""
                } label: { Image(systemName: "plus").frame(width: 38, height: 38) }
                    .buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black)
                    .accessibilityLabel("添加保护路径")
                    .disabled(newPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if model.protectedPaths.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("还没有保护路径").font(.system(size: 15, weight: .semibold))
                    Text("添加后，扫描会跳过该路径及其所有子目录。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 700).padding(38).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 8) {
                    ForEach(model.protectedPaths, id: \.self) { path in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield.fill").foregroundStyle(.mint)
                            Text(path).font(.system(size: 13, design: .monospaced))
                            Spacer()
                            Text(FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath) ? "存在" : "路径已不存在")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                            Button {
                                model.protectedPaths.removeAll { $0 == path }
                                UserDefaults.standard.set(model.protectedPaths, forKey: "cleanmymac.protectedPaths")
                            } label: { Image(systemName: "trash").foregroundStyle(.secondary) }
                                .buttonStyle(.plain).help("移除保护路径").accessibilityLabel("移除保护路径 \(path)")
                        }
                        .padding(14).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 11))
                    }
                }
                .frame(maxWidth: 700, alignment: .leading)
            }
            Spacer()
        }
        .padding(34)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "设置",
                    title: "把清理流程调成你的节奏。",
                    description: "这里的选项都会立即生效，并只保存在本机。路径、文件名和扫描结果不会上传。"
                ) { EmptyView() }

                VStack(alignment: .leading, spacing: 14) {
                    Text("扫描与推荐").sectionLabel()
                    HStack(spacing: 14) {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .foregroundStyle(.mint)
                            .frame(width: 34, height: 34)
                            .background(Color.mint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("打开应用后自动扫描").font(.system(size: 13, weight: .semibold))
                            Text("关闭时不会在后台读取文件；你仍可随时手动扫描。")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("自动扫描", isOn: $model.scanOnLaunch)
                            .labelsHidden().toggleStyle(.switch).tint(.mint)
                    }
                    .padding(15).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 11))

                    HStack(spacing: 14) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(.indigo)
                            .frame(width: 34, height: 34)
                            .background(Color.indigo.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("超过多少天未更新时自动推荐").font(.system(size: 13, weight: .semibold))
                            Text("仅影响项目构建产物；共享缓存仍按风险等级推荐。")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Stepper("\(model.artifactRecommendationDays) 天", value: $model.artifactRecommendationDays, in: 1...30)
                            .labelsHidden()
                        Text("\(model.artifactRecommendationDays) 天")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 46, alignment: .trailing)
                    }
                    .padding(15)
                    .background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 11))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("权限与保护").sectionLabel()
                    HStack(spacing: 10) {
                        SettingsFact(symbol: "lock.fill", title: "完全磁盘访问权限", detail: "用于读取受 macOS 保护的目录和废纸篓。")
                        Button { model.openSystemSettings() } label: { Label("打开系统设置", systemImage: "arrow.up.forward.app") }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(13).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 10))
                    HStack(spacing: 10) {
                        SettingsFact(symbol: "checkmark.shield.fill", title: "保护列表", detail: "当前已保护 \(model.protectedPaths.count) 个路径。")
                        Button { model.section = .protected } label: { Label("管理保护路径", systemImage: "chevron.right") }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(13).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("本地数据").sectionLabel()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("清理与卸载报告").font(.system(size: 13, weight: .semibold))
                            Text("已保存 \(model.localReportCount) 份报告，仅存放在本机。")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.openReportsFolder() } label: { Label("打开报告目录", systemImage: "folder") }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(13).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 10))
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("恢复默认设置").font(.system(size: 13, weight: .semibold))
                            Text("清空保护列表、恢复推荐天数，不删除报告和扫描结果。")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("恢复默认") { model.showResetPreferencesConfirmation = true }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(13).background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("应用信息").sectionLabel()
                    Text("\(ProductIdentity.displayName) 原生 macOS 版").font(.system(size: 14, weight: .semibold))
                    Text("个人使用 · 版本 \(ProductIdentity.version) · \(model.systemSummary)")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    if let message = model.settingsMessage {
                        Label(message, systemImage: "info.circle.fill").font(.system(size: 11)).foregroundStyle(.mint)
                    }
                }
                .padding(15)
                .background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 11))
            }
            .padding(34)
        }
    }
}

struct SettingsFact: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.mint).frame(width: 25)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(13)
        .background(Color.cmmCard, in: RoundedRectangle(cornerRadius: 10))
    }
}

extension View {
    func sectionLabel() -> some View { self.font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(.tertiary) }
}

extension Color {
    static let cmmBackground = Color(red: 0.055, green: 0.067, blue: 0.086)
    static let cmmSidebar = Color(red: 0.065, green: 0.078, blue: 0.102)
    static let cmmCard = Color(red: 0.095, green: 0.114, blue: 0.145)
}
