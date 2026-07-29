//
//  SettingsView.swift
//  Talkify
//

import SwiftUI
import AgentKit
import CoreKit
import DesignKit

/// Talkify 的设置中心：跨平台自适应布局。
///
/// - **iPhone (compact)**：NavigationStack — 侧栏为根视图，点击行 push 详情。
/// - **iPad / macOS (regular)**：NavigationSplitView — 侧栏 + 详情并排。
///
/// 两种布局均通过 SettingsRouter 驱动导航。
public struct SettingsView: View {
    @Environment(AgentManager.self) private var agentManager
    @Environment(UserManager.self) private var userManager
    @Environment(AuthManager.self) private var authManager
    @Environment(AppContainer.self) private var container
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private let onClose: () -> Void
    @State private var selection: SettingsSection
    @State private var searchText = ""
    
    @AppStorage("settings.defaultPermission") private var defaultPermission = true
    @AppStorage("settings.autoApproval") private var autoApproval = true
    @AppStorage("settings.fullDiskAccess") private var fullDiskAccess = false
    @AppStorage("settings.showInMenuBar") private var showInMenuBar = true
    @AppStorage("settings.showBottomPanel") private var showBottomPanel = true

    @State var router = SettingsRouter()
    
    init(
        initialSection: SettingsSection = .account,
        onClose: @escaping () -> Void = {}
    ) {
        self.onClose = onClose
        self._selection = State(initialValue: initialSection)
    }

    public var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .task {
            if authManager.isRegistered {
                agentManager.fetchUsage()
            }
        }
    }
    
    // MARK: - Compact (iPhone) — NavigationStack
    
    private var compactLayout: some View {
        NavigationStack(path: $router.path) {
            settingsSidebar(navigateWithRouter: true)
                .withSettingsNavigationDestinations(router: router, container: container)
                .toolbar {
#if os(iOS)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16))
                                .clipShape(Circle())
                        }
                        
                    }
#endif
                }
        }
        .task {
            guard router.path.isEmpty, selection != .account else { return }
            router.navigate(to: .detail(selection))
        }
        .withSettingsSheetDestinations(sheetDestinations: $router.presentedSheet, container: container)
        .withSettingsCoverDestinations(coverDestinations: $router.presentedCover)
        .environment(router)
    }
    
    // MARK: - Regular (iPad / macOS) — NavigationSplitView
    
    private var regularLayout: some View {
        NavigationSplitView {
            settingsSidebar(navigateWithRouter: false)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 350)
        } detail: {
            NavigationStack(path: $router.path) {
                SettingsDetailView(section: selection)
                    .withSettingsNavigationDestinations(router: router, container: container)
            }
            .withSettingsSheetDestinations(sheetDestinations: $router.presentedSheet, container: container)
            .withSettingsCoverDestinations(coverDestinations: $router.presentedCover)
            .environment(router)
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    // MARK: - Sidebar
    
    private func settingsSidebar(navigateWithRouter: Bool) -> some View {
        VStack(spacing: 0) {
            if horizontalSizeClass == .regular {
                Button(action: onClose) {
                    Label(TalkifyLocalized.string("settings.back"), systemImage: "arrow.left")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(TalkifyLocalized.string("settings.search_placeholder"), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
                
                ScrollView(showsIndicators: false) {
                    VStack {
                        Text(accountInitial)
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 80, height: 80)
                            .background(Color.accentColor, in: Circle())
                            .padding(.top, 30)
                        
                        Text(accountName)
                            .font(.system(size: 23, weight: .regular))
                            .padding(.top, 10)
                    }
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(SettingsSection.Group.allCases, id: \.self) { group in
                            let sections = filteredSections(in: group)
                            if !sections.isEmpty {
                                Text(group.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 16)
                                    .padding(.top, group == .personal ? 8 : 20)
                                    .padding(.bottom, 5)
                                
                                ForEach(sections) { section in
                                    Button {
                                        if navigateWithRouter {
                                            router.navigate(to: .detail(section))
                                        } else {
                                            selection = section
                                        }
                                    } label: {
                                        let isSelected: Bool = {
                                            if navigateWithRouter {
                                                if case .detail(let s) = router.path.last, s == section {
                                                    return true
                                                }
                                                return false
                                            }
                                            return selection == section
                                        }()
                                        SettingsSidebarRow(section: section, isSelected: isSelected)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if horizontalSizeClass == .compact && authManager.isRegistered {
                            Button(role: .destructive) {
                                Task { await container.disconnectGateway() }
                            } label: {
                                Label(TalkifyLocalized.string("workspace.sign_out"), systemImage: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 15, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 15)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                    }
                    .padding(.bottom, 20)
                }
            } else {
                List {
                    Section {
                        HStack {
                            Spacer()
                            VStack {
                                Text(accountInitial)
                                    .font(.system(size: 34, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(width: 80, height: 80)
                                    .background(Color.accentColor, in: Circle())
                                    .padding(.top, 30)
                                
                                Text(accountName)
                                    .font(.system(size: 23, weight: .regular))
                                    .padding(.top, 10)
                            }
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.clear) // 隐藏头像区域的白色卡片背景
                    .listRowInsets(EdgeInsets())    // 清除边距以居中
                    
                    ForEach(SettingsSection.Group.allCases, id: \.self) { group in
                        Section {
                            let sections = filteredSections(in: group)
                            if !sections.isEmpty {
                                Section(header: Text(group.title)) {
                                    ForEach(sections) { section in
                                        Button {
                                            if navigateWithRouter {
                                                router.navigate(to: .detail(section))
                                            } else {
                                                selection = section
                                            }
                                        } label: {
                                            let isSelected: Bool = {
                                                if navigateWithRouter {
                                                    if case .detail(let s) = router.path.last, s == section {
                                                        return true
                                                    }
                                                    return false
                                                }
                                                return selection == section
                                            }()
                                            
                                            // 自定义行布局（包含图标、标题、Chevron箭头等）
                                            SettingsSidebarRow(section: section, isSelected: isSelected)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        
                    }
                    // 底部退出登录按钮（针对 Compact 宽度显示）
                    if horizontalSizeClass == .compact && authManager.isRegistered {
                        Section {
                            Button(role: .destructive) {
                                Task { await container.disconnectGateway() }
                            } label: {
                                Label(TalkifyLocalized.string("workspace.sign_out"), systemImage: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
#if os(iOS)
                .listStyle(.insetGrouped)
#else
                .listStyle(.sidebar)
#endif
            }
            
        }
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Helpers
    
    private func filteredSections(in group: SettingsSection.Group) -> [SettingsSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return SettingsSection.allCases.filter {
            $0.group == group && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query))
        }
    }
    
    private var accountName: String {
        guard authManager.isRegistered else { return TalkifyLocalized.string("workspace.not_logged_in") }
        return authManager.displayNickname ?? userManager.profile?.nickname ?? "Unknow"
    }
    
    private var accountInitial: String { String(accountName.prefix(1)).uppercased() }
    
}
