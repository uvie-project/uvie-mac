import SwiftUI

// MARK: - Window Controller

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    private override init() {}

    func show() {
        // Ensure we're on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.show()
            }
            return
        }

        // Recreate window if it was closed or invalidated
        if window == nil || window?.isVisible == false {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "UVie for Mac"
            w.titlebarAppearsTransparent = true
            // Default: only the title bar can move the window. Setting this to
            // true lets the user drag from anywhere inside the window background.
            w.isMovableByWindowBackground = false
            w.isReleasedWhenClosed = false
            w.delegate = self

            // Use NSHostingController for better memory management
            let controller = NSHostingController(rootView: SettingsView())
            // Do not let the hosting controller resize the window to each
            // pane's ideal size - that made the window jump on tab changes.
            controller.sizingOptions = []
            w.contentViewController = controller
            w.setContentSize(NSSize(width: 760, height: 560))
            w.contentMinSize = NSSize(width: 640, height: 480)

            window = w

            // Center on screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let windowFrame = w.frame
                let x = screenFrame.midX - windowFrame.width / 2
                let y = screenFrame.midY - windowFrame.height / 2
                w.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        guard let w = window else { return }
        w.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Cleanup window and its content to prevent memory leaks
        if let w = notification.object as? NSWindow, w === window {
            window?.contentViewController = nil
            window?.delegate = nil
            window = nil
        }
    }
}

// MARK: - Tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case general    = "Tổng quan"
    case keyboard   = "Gõ phím"
    case macro      = "Gõ tắt"
    case apps       = "Ứng dụng"
    case advanced   = "Hệ thống"
    case about      = "Giới thiệu"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:   return "slider.horizontal.3"
        case .keyboard:  return "keyboard"
        case .macro:     return "text.insert"
        case .apps:      return "square.grid.2x2"
        case .advanced:  return "gearshape"
        case .about:     return "info.circle"
        }
    }
}

// MARK: - Root View  (named SettingsView to match UVieMacApp.swift)

struct SettingsView: View {
    @State private var tab: SettingsTab = .general
    @StateObject private var updateChecker = UpdateChecker.shared

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 2) {
                Spacer().frame(height: 20)  // below titlebar
                ForEach(SettingsTab.allCases) { t in
                    SidebarRow(
                        tab: t,
                        selected: tab == t,
                        showUpdateBadge: t == .about && updateChecker.hasUpdate,
                        onSelect: { tab = t }
                    )
                }
                Spacer()
            }
            .frame(width: 186)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Detail pane
            Group {
                switch tab {
                case .general:   GeneralPane()
                case .keyboard:  KeyboardPane()
                case .macro:     MacroPane()
                case .apps:      AppsPane()
                case .advanced:  AdvancedPane()
                case .about:     AboutPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(UVieTheme.accent)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSettingsTab)) { note in
            if let t = note.userInfo?["tab"] as? SettingsTab {
                tab = t
            }
        }
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let tab: SettingsTab
    let selected: Bool
    var showUpdateBadge: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? UVieTheme.accentText : .secondary)
                    .frame(width: 18)
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showUpdateBadge {
                    Circle()
                        .fill(UVieTheme.accent)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                selected ? UVieTheme.accentSoft : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }
}
