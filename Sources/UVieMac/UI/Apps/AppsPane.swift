import SwiftUI
import AppKit

// MARK: - Apps Pane

struct AppsPane: View {
    @State private var excludedApps: [AppEntry] = []
    @State private var compoundApps: [AppEntry] = []
    @State private var chromiumApps: [AppEntry] = []
    @State private var bypassApps: [AppEntry] = []
    @State private var showingAppPicker = false
    @State private var pickerMode: PickerMode = .excluded
    @State private var availableApps: [RunningApp] = []
    @AppStorage(DefaultsKey.smartSwitchKey) private var smartSwitchKey: Bool = false
    @State private var showingResetConfirm = false

    private let defaultExcludedApps: [String] = []

    // Shared with EventTap.swift via AppDefaults — single source of truth.
    private let defaultCompoundApps: [String] = Array(AppDefaults.compoundApps).sorted()

    private let defaultChromiumApps: [String] = Array(AppDefaults.chromiumBrowsers).sorted()

    private let defaultBypassApps: [String] = Array(AppDefaults.bypassApps).sorted()

    enum PickerMode: CaseIterable {
        case excluded
        case compound
        case chromium
        case bypass

        /// Menu/checkmark label shown in the unified list row.
        var label: String {
            switch self {
            case .excluded: return "Không gõ tiếng Việt"
            case .compound: return "Sửa lỗi gợi ý tự động"
            case .chromium: return "Trình duyệt Chromium"
            case .bypass:   return "Để phím đi thẳng"
            }
        }

        /// "Thêm ứng dụng" menu item: why the user would add an app here.
        var addLabel: String {
            switch self {
            case .excluded: return "Không muốn gõ tiếng Việt ở đó"
            case .compound: return "Chữ bị lặp hoặc mất dấu khi có gợi ý"
            case .chromium: return "Trình duyệt Chromium bị lặp chữ"
            case .bypass:   return "Không gõ được gì trong đó"
            }
        }

        /// Plain-language explanation shown in the "Các cách xử lý" footer.
        var helpText: String {
            switch self {
            case .excluded: return "UVie tắt hẳn trong ứng dụng đó. Hợp với game hoặc ứng dụng bạn chỉ gõ tiếng Anh."
            case .compound: return "Dùng khi gõ ở ô địa chỉ hay ô tìm kiếm mà chữ bị lặp hoặc mất dấu vì ứng dụng tự gợi ý."
            case .chromium: return "Chrome, Edge, Brave, Arc... cần cách sửa chữ riêng. Thêm trình duyệt Chromium khác nếu bị lặp chữ ở thanh địa chỉ."
            case .bypass:   return "Dùng khi bạn không gõ được gì trong ứng dụng (máy ảo, giả lập, điều khiển từ xa, game). Ở đó bạn sẽ không gõ được tiếng Việt."
            }
        }
    }

    struct AppEntry: Identifiable {
        let id = UUID()
        let bundleID: String
        let icon: NSImage?
    }

    var body: some View {
        PaneScroll {
            PaneSection("Theo ứng dụng") {
                SettingsCard {
                    SToggleRow("arrow.triangle.2.circlepath",
                                "Nhớ ngôn ngữ cho từng ứng dụng",
                                "Bạn gõ tiếng Việt ở Zalo, tiếng Anh ở Terminal? UVie nhớ và tự chuyển mỗi khi bạn đổi ứng dụng.",
                                $smartSwitchKey)
                }
            }

            PaneSection("Xử lý riêng cho từng ứng dụng") {
                SettingsCard {
                    Text("Ứng dụng nào gõ bị lỗi thì thêm vào đây rồi chọn cách xử lý. Một ứng dụng có thể dùng nhiều cách cùng lúc.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    if unifiedEntries.isEmpty {
                        Text("Chưa có ứng dụng nào")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(unifiedEntries.enumerated()), id: \.element.id) { idx, entry in
                                AppRow(bundleID: entry.bundleID,
                                       name: Self.displayName(for: entry.bundleID),
                                       icon: entry.icon) {
                                    modeMenu(for: entry.bundleID)
                                }
                                if idx < unifiedEntries.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Menu {
                            ForEach(PickerMode.allCases, id: \.self) { mode in
                                Button(mode.addLabel) {
                                    pickerMode = mode
                                    showingAppPicker = true
                                }
                            }
                        } label: {
                            Label("Thêm ứng dụng", systemImage: "plus")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .foregroundStyle(UVieTheme.accentText)

                        Spacer()

                        Button {
                            showingResetConfirm = true
                        } label: {
                            Text("Về mặc định")
                                .font(.system(size: 11.5))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .confirmationDialog("Đưa danh sách ứng dụng về mặc định?",
                                    isPresented: $showingResetConfirm,
                                    titleVisibility: .visible) {
                    Button("Về mặc định", role: .destructive) {
                        resetExcludedToDefaults()
                        resetCompoundToDefaults()
                        resetChromiumToDefaults()
                        resetBypassToDefaults()
                    }
                    Button("Huỷ", role: .cancel) {}
                } message: {
                    Text("Các ứng dụng bạn tự thêm sẽ bị xoá khỏi danh sách.")
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(PickerMode.allCases, id: \.self) { mode in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.label)
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text(mode.helpText)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Các cách xử lý nghĩa là gì?")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet(availableApps: availableApps) { selectedBundleID in
                switch pickerMode {
                case .excluded:
                    addExcludedApp(selectedBundleID)
                case .compound:
                    addCompoundApp(selectedBundleID)
                case .chromium:
                    addChromiumApp(selectedBundleID)
                case .bypass:
                    addBypassApp(selectedBundleID)
                }
            }
        }
        .onChange(of: showingAppPicker) { isShowing in
            if isShowing {
                loadAvailableApps()
            }
        }
        .onAppear {
            loadExcludedApps()
            loadCompoundApps()
            loadChromiumApps()
            loadBypassApps()
        }
    }

    // MARK: - Unified List

    /// Union of the four mode lists, de-duplicated by bundle ID and sorted by
    /// display name (case-insensitive, ties by bundle ID). The icon comes from
    /// whichever list already resolved one, else the shared icon cache.
    private var unifiedEntries: [AppEntry] {
        var byID: [String: NSImage?] = [:]
        for entry in excludedApps + compoundApps + chromiumApps + bypassApps {
            if byID[entry.bundleID] == nil || byID[entry.bundleID]! == nil {
                byID[entry.bundleID] = entry.icon
            }
        }
        return allBundleIDs.map { bundleID in
            AppEntry(bundleID: bundleID,
                     icon: byID[bundleID] ?? AppIconCache.shared.icon(for: bundleID))
        }
    }

    /// Every bundle ID present in at least one mode list, sorted by display
    /// name (case-insensitive), ties by bundle ID.
    private var allBundleIDs: [String] {
        var ids = Set<String>()
        for entry in excludedApps + compoundApps + chromiumApps + bypassApps {
            ids.insert(entry.bundleID)
        }
        return ids.sorted {
            let an = Self.displayName(for: $0).localizedCaseInsensitiveCompare(Self.displayName(for: $1))
            return an == .orderedSame ? $0 < $1 : an == .orderedAscending
        }
    }

    /// Entries of one mode list (the underlying `@State` arrays stay the
    /// single source of truth).
    private func entries(for mode: PickerMode) -> [AppEntry] {
        switch mode {
        case .excluded: return excludedApps
        case .compound: return compoundApps
        case .chromium: return chromiumApps
        case .bypass:   return bypassApps
        }
    }

    /// Modes a bundle ID currently belongs to, in `allCases` order.
    private func modes(of bundleID: String) -> [PickerMode] {
        PickerMode.allCases.filter { mode in
            entries(for: mode).contains { $0.bundleID == bundleID }
        }
    }

    /// Toggles a bundle ID in one mode list using the existing add/remove
    /// functions, so persistence logic is unchanged.
    private func setMode(_ mode: PickerMode, bundleID: String, on: Bool) {
        let list = entries(for: mode)
        if on {
            guard !list.contains(where: { $0.bundleID == bundleID }) else { return }
            switch mode {
            case .excluded: addExcludedApp(bundleID)
            case .compound: addCompoundApp(bundleID)
            case .chromium: addChromiumApp(bundleID)
            case .bypass:   addBypassApp(bundleID)
            }
        } else if let idx = list.firstIndex(where: { $0.bundleID == bundleID }) {
            switch mode {
            case .excluded: removeExcludedApp(at: idx)
            case .compound: removeCompoundApp(at: idx)
            case .chromium: removeChromiumApp(at: idx)
            case .bypass:   removeBypassApp(at: idx)
            }
        }
    }

    private func removeEverywhere(_ bundleID: String) {
        for mode in PickerMode.allCases {
            setMode(mode, bundleID: bundleID, on: false)
        }
    }

    /// Trailing menu on each app row: which handling modes apply, plus the
    /// destructive remove action (replaces the old per-row minus button).
    private func modeMenu(for bundleID: String) -> some View {
        let active = modes(of: bundleID)
        let text: String
        switch active.count {
        case 0: text = ""
        case 1...2: text = active.map(\.label).joined(separator: ", ")
        default: text = active.prefix(2).map(\.label).joined(separator: ", ")
                         + " +\(active.count - 2)"
        }
        return Menu {
            ForEach(PickerMode.allCases, id: \.self) { mode in
                Button {
                    setMode(mode, bundleID: bundleID,
                            on: !active.contains(mode))
                } label: {
                    Label(mode.label,
                          systemImage: active.contains(mode) ? "checkmark" : "")
                }
            }
            Divider()
            Button("Xoá khỏi danh sách", role: .destructive) {
                removeEverywhere(bundleID)
            }
        } label: {
            HStack(spacing: 4) {
                Text(text)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .tint(.secondary)
        .fixedSize()
    }

    // MARK: - Display Name

    /// Resolved display names, memoized: NSWorkspace lookup is not free and
    /// `allBundleIDs` sorts by name for every render.
    @MainActor private static var displayNameCache: [String: String] = [:]

    /// User-facing app name for a bundle ID: the .app bundle's display name
    /// with a trailing ".app" stripped, falling back to the last bundle-ID
    /// component when the app is not installed.
    @MainActor static func displayName(for bundleID: String) -> String {
        if let cached = displayNameCache[bundleID] { return cached }
        var name = bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let display = FileManager.default.displayName(atPath: url.path)
            name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
        } else if let last = bundleID.split(separator: ".").last {
            name = String(last)
        }
        displayNameCache[bundleID] = name
        return name
    }

    // MARK: - Helper Methods

    private func loadCompoundApps() {
        let custom = UserDefaults.standard.stringArray(forKey: DefaultsKey.customCompoundApps) ?? []
        let removed = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.removedCompoundApps) ?? [])
        let allBundleIDs = defaultCompoundApps.filter { !removed.contains($0) } + custom
        compoundApps = allBundleIDs.map { bundleID in
            AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID))
        }
    }

    private func saveCompoundApps() {
        let current = compoundApps.map { $0.bundleID }
        let currentSet = Set(current)
        UserDefaults.standard.set(current.filter { !defaultCompoundApps.contains($0) },
                                 forKey: DefaultsKey.customCompoundApps)
        // Remember which defaults were removed: the custom list alone cannot
        // express a deletion, so the defaults came back on the next launch.
        UserDefaults.standard.set(defaultCompoundApps.filter { !currentSet.contains($0) },
                                 forKey: DefaultsKey.removedCompoundApps)
    }

    private func addCompoundApp(_ bundleID: String) {
        compoundApps.append(AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID)))
        saveCompoundApps()
    }

    private func removeCompoundApp(at index: Int) {
        guard index < compoundApps.count else { return }
        compoundApps.remove(at: index)
        saveCompoundApps()
    }

    private func resetCompoundToDefaults() {
        compoundApps = defaultCompoundApps.map { bundleID in
            AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID))
        }
        saveCompoundApps()
    }

    // MARK: - Excluded Apps

    private func loadExcludedApps() {
        let custom = UserDefaults.standard.stringArray(forKey: DefaultsKey.customExcludedApps) ?? []
        let allBundleIDs = defaultExcludedApps + custom
        excludedApps = allBundleIDs.map { bundleID in
            AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID))
        }
    }

    private func saveExcludedApps() {
        let custom = excludedApps.map { $0.bundleID }.filter { !defaultExcludedApps.contains($0) }
        UserDefaults.standard.set(custom, forKey: DefaultsKey.customExcludedApps)
    }

    private func addExcludedApp(_ bundleID: String) {
        excludedApps.append(AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID)))
        saveExcludedApps()
    }

    private func removeExcludedApp(at index: Int) {
        guard index < excludedApps.count else { return }
        excludedApps.remove(at: index)
        saveExcludedApps()
    }

    private func resetExcludedToDefaults() {
        excludedApps = defaultExcludedApps.map { bundleID in
            AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID))
        }
        saveExcludedApps()
    }

    // MARK: - Chromium Apps

    private func loadChromiumApps() {
        let custom = UserDefaults.standard.stringArray(forKey: DefaultsKey.customChromiumApps) ?? []
        let removed = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.removedChromiumApps) ?? [])
        let allBundleIDs = defaultChromiumApps.filter { !removed.contains($0) } + custom
        chromiumApps = allBundleIDs.map { bundleID in
            AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID))
        }
    }

    private func saveChromiumApps() {
        let current = chromiumApps.map { $0.bundleID }
        let currentSet = Set(current)
        UserDefaults.standard.set(current.filter { !defaultChromiumApps.contains($0) },
                                 forKey: DefaultsKey.customChromiumApps)
        UserDefaults.standard.set(defaultChromiumApps.filter { !currentSet.contains($0) },
                                 forKey: DefaultsKey.removedChromiumApps)
    }

    private func addChromiumApp(_ bundleID: String) {
        chromiumApps.append(AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID)))
        saveChromiumApps()
    }

    private func removeChromiumApp(at index: Int) {
        guard index < chromiumApps.count else { return }
        chromiumApps.remove(at: index)
        saveChromiumApps()
    }

    private func resetChromiumToDefaults() {
        chromiumApps = defaultChromiumApps.map { bundleID in
            AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID))
        }
        saveChromiumApps()
    }

    // MARK: - Bypass Apps

    private func loadBypassApps() {
        let custom = UserDefaults.standard.stringArray(forKey: DefaultsKey.customBypassApps) ?? []
        let removed = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.removedBypassApps) ?? [])
        let allBundleIDs = defaultBypassApps.filter { !removed.contains($0) } + custom
        bypassApps = allBundleIDs.map { bundleID in
            AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID))
        }
    }

    private func saveBypassApps() {
        let current = bypassApps.map { $0.bundleID }
        let currentSet = Set(current)
        UserDefaults.standard.set(current.filter { !defaultBypassApps.contains($0) },
                                 forKey: DefaultsKey.customBypassApps)
        UserDefaults.standard.set(defaultBypassApps.filter { !currentSet.contains($0) },
                                 forKey: DefaultsKey.removedBypassApps)
    }

    private func addBypassApp(_ bundleID: String) {
        bypassApps.append(AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID)))
        saveBypassApps()
    }

    private func removeBypassApp(at index: Int) {
        guard index < bypassApps.count else { return }
        bypassApps.remove(at: index)
        saveBypassApps()
    }

    private func resetBypassToDefaults() {
        bypassApps = defaultBypassApps.map { bundleID in
            AppEntry(bundleID: bundleID, icon: AppIconCache.shared.icon(for: bundleID))
        }
        saveBypassApps()
    }

    private func loadAvailableApps() {
        let runningApps = NSWorkspace.shared.runningApplications
        let currentList: [AppEntry]
        switch pickerMode {
        case .excluded:
            currentList = excludedApps
        case .compound:
            currentList = compoundApps
        case .chromium:
            currentList = chromiumApps
        case .bypass:
            currentList = bypassApps
        }

        let currentBundleIDs = Set(currentList.map { $0.bundleID })

        availableApps = runningApps
            .filter { $0.bundleIdentifier != nil && $0.activationPolicy == .regular }
            .filter { !currentBundleIDs.contains($0.bundleIdentifier!) }
            .map { app in
                let icon = AppIconCache.shared.icon(for: app.bundleIdentifier!) ?? app.icon
                return RunningApp(bundleID: app.bundleIdentifier!, name: app.localizedName ?? "Unknown", icon: icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

}

