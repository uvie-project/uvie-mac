import SwiftUI

// MARK: - General Pane

struct GeneralPane: View {
    @AppStorage(DefaultsKey.inputMethod)    private var inputMethod: String = "telex"
    @AppStorage(DefaultsKey.engineEnabled)  private var engineEnabled: Bool = true
    @AppStorage(DefaultsKey.autoDisableOnNonLatinLayout) private var autoDisableOnNonLatinLayout: Bool = false
    @AppStorage(DefaultsKey.inputMethodHotkeyEnabled) private var hotkeyEnabled: Bool = true
    @AppStorage(DefaultsKey.customToggleEnabled) private var customToggleEnabled: Bool = false
    @AppStorage(Logger.keystrokeTraceKey) private var keystrokeTrace: Bool = false
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared
    @StateObject private var layoutMonitor = KeyboardLayoutMonitor.shared
    @State private var accessibilityTrusted = false
    @State private var inputMonitoringTrusted = false
    @State private var tryText = ""

    /// True when at least one status banner condition holds, so the banner
    /// stack leaves no empty gap above the hero when all are hidden.
    private var hasBanner: Bool {
        !accessibilityTrusted
            || (accessibilityTrusted && !inputMonitoringTrusted)
            || (autoDisableOnNonLatinLayout && layoutMonitor.isNonLatinLayout)
            || keystrokeTrace
    }

    private var isVietnameseMode: Binding<Bool> {
        Binding(
            get: { engineEnabled },
            set: { engineEnabled = $0 }
        )
    }

    var body: some View {
        PaneScroll {
            // Status banners: shown only while a condition holds
            if hasBanner {
                VStack(spacing: 8) {
                    if !accessibilityTrusted {
                        StatusBanner(
                            icon: "exclamationmark.triangle.fill",
                            tint: .orange,
                            title: "UVie chưa có quyền Trợ năng",
                            message: "Thiếu quyền này UVie không đọc được phím bạn bấm, nên chưa gõ được tiếng Việt.",
                            actionTitle: "Mở cài đặt Trợ năng",
                            action: { AccessibilityChecker.openPrivacySettings() }
                        )
                    }
                    if accessibilityTrusted && !inputMonitoringTrusted {
                        StatusBanner(
                            icon: "exclamationmark.triangle.fill",
                            tint: .orange,
                            title: "UVie chưa có quyền Input Monitoring",
                            message: "Từ macOS 15, UVie cần thêm quyền này để đọc phím bạn bấm.",
                            actionTitle: "Mở cài đặt Input Monitoring",
                            action: { AccessibilityChecker.openInputMonitoringSettings() }
                        )
                    }
                    if autoDisableOnNonLatinLayout && layoutMonitor.isNonLatinLayout {
                        StatusBanner(
                            icon: "globe",
                            tint: .orange,
                            title: "Đang dùng bàn phím không phải chữ Latin",
                            message: "UVie tạm nghỉ cho tới khi bạn chuyển về bàn phím Latin."
                        )
                    }
                    if keystrokeTrace {
                        StatusBanner(
                            icon: "record.circle",
                            tint: .orange,
                            title: "Đang ghi lại phím gõ",
                            message: "Chỉ nên bật khi báo lỗi. Tắt đi khi bạn đã gửi xong.",
                            actionTitle: "Tắt",
                            action: { keystrokeTrace = false }
                        )
                    }
                }
            }

            // Engine master toggle
            SettingsCard {
                HStack(spacing: 14) {
                    ZStack {
                        if isVietnameseMode.wrappedValue {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(UVieTheme.accent)
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                                )
                        }
                        Text(isVietnameseMode.wrappedValue ? "V" : "E")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(isVietnameseMode.wrappedValue ? .white : .secondary)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(isVietnameseMode.wrappedValue ? "Đang gõ tiếng Việt" : "Đang gõ tiếng Anh")
                            .font(.system(size: 14, weight: .semibold))
                        Text(isVietnameseMode.wrappedValue
                             ? "UVie thêm dấu khi bạn gõ."
                             : "UVie tạm nghỉ. Phím bạn bấm được giữ nguyên.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: isVietnameseMode)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
                .onTapGesture { isVietnameseMode.wrappedValue.toggle() }
            }
            PaneSection("Kiểu gõ") {
                SettingsCard {
                    HStack(spacing: 8) {
                        imTile("Telex", "telex", KeyExample(["a", "a"], "â"))
                        imTile("VNI", "vni", KeyExample(["a", "6"], "â"))
                        imTile("Simple Telex", "simpleTelex", KeyExample(["a", "w"], "ă"))
                    }
                    .padding(10)
                }
            }

            PaneSection("Gõ thử") {
                SettingsCard {
                    HStack(spacing: 8) {
                        TextField("Gõ thử vào đây để xem kết quả", text: $tryText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                        if !tryText.isEmpty {
                            Button { tryText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Xoá")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }

            PaneSection("Phím tắt đổi ngôn ngữ") {
                SettingsCard {
                    // Fn toggle (existing)
                    SToggleRow("globe",
                                "Bấm Fn để đổi ngôn ngữ",
                                "Bấm rồi thả phím Fn (phím Quả địa cầu) để chuyển giữa tiếng Việt và tiếng Anh.",
                                $hotkeyEnabled)

                    SCardDivider()

                    // Custom global shortcut
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .center)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Phím tắt riêng")
                                .font(.system(size: 13, weight: .medium))
                            Text("Tự chọn tổ hợp phím, dùng được trong mọi ứng dụng.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $customToggleEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .onTapGesture { customToggleEnabled.toggle() }

                    if customToggleEnabled {
                        SCardDivider()
                        HStack(spacing: 12) {
                            Image(systemName: "record.circle")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .center)
                            Text("Tổ hợp phím")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            ShortcutRecorder()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                    }
                }
                .onChange(of: customToggleEnabled) { newValue in
                    hotkeyManager.setEnabled(newValue)
                }
            }
        }
        .onAppear { refreshPermissionState() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionState()
        }
    }

    private func refreshPermissionState() {
        accessibilityTrusted = AccessibilityChecker.isTrusted
        inputMonitoringTrusted = AccessibilityChecker.isInputMonitoringTrusted
    }

    private func imTile(_ name: String, _ tag: String, _ example: KeyExample) -> some View {
        let active = inputMethod == tag
        return Button { inputMethod = tag } label: {
            VStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                KeyExampleRow([example])
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                active ? UVieTheme.accentSoft : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: UVieTheme.controlRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UVieTheme.controlRadius)
                    .strokeBorder(active ? UVieTheme.accent : .clear, lineWidth: 1.5)
            )
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}
