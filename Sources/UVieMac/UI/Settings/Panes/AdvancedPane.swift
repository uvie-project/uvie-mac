import SwiftUI

// MARK: - Advanced Pane

struct AdvancedPane: View {
    @AppStorage(DefaultsKey.autoDisableOnNonLatinLayout) private var autoDisableOnNonLatinLayout: Bool = false
    @AppStorage(DefaultsKey.inputSourceModeEnabled) private var inputSourceModeFlag: Bool = false
    @AppStorage(DefaultsKey.inputSourceStyle) private var inputSourceStyle: String = "plain"
    @StateObject private var launchAtLogin = LaunchAtLoginManager.shared
    @ObservedObject private var inputSourceMode = InputSourceModeController.shared

    /// The toggle writes through the controller: enabling installs and
    /// selects the UVieIM input method, disabling deselects it.
    private var inputSourceToggle: Binding<Bool> {
        Binding(
            get: { inputSourceModeFlag },
            set: { inputSourceMode.setEnabled($0) }
        )
    }

    private var inputSourceStatusText: String {
        switch inputSourceMode.state {
        case .off: return "Đang tắt"
        case .installing: return "Đang cài đặt…"
        case .active: return "Đang hoạt động"
        case .failed(let message): return message
        case .unavailable: return "Không dùng được trong bản dev"
        }
    }

    var body: some View {
        PaneScroll {
            PaneSection("Khởi động") {
                SettingsCard {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "power")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .center)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Mở UVie khi đăng nhập")
                                .font(.system(size: 13, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(launchAtLogin.isAvailable
                                 ? "UVie tự chạy mỗi khi bạn bật máy."
                                 : "Chỉ dùng được với bản cài đặt chính thức.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: $launchAtLogin.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!launchAtLogin.isAvailable)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if launchAtLogin.isAvailable {
                            launchAtLogin.isEnabled.toggle()
                        }
                    }
                }
            }

            PaneSection("Bàn phím khác") {
                SettingsCard {
                    SToggleRow("globe",
                                "Tạm nghỉ khi dùng bàn phím không phải chữ Latin",
                                "Khi bạn chuyển sang bàn phím tiếng Nhật, Hàn, Nga..., UVie tự tắt để không làm sai chữ.",
                                $autoDisableOnNonLatinLayout)
                }
            }

            PaneSection("Quyền truy cập") {
                SettingsCard {
                    SActionRow("lock.shield",
                               "Quyền Trợ năng",
                               "Mở Cài đặt hệ thống để xem hoặc cấp lại quyền cho UVie.",
                               trailing: "arrow.up.right.square") {
                        AccessibilityChecker.openPrivacySettings()
                    }
                }
            }

            PaneSection("Bộ gõ hệ thống (thử nghiệm)") {
                SettingsCard {
                    SToggleRow("keyboard.badge.ellipsis",
                                "Gõ qua bộ gõ của macOS",
                                "UVie hoạt động như một bộ gõ chính thức của macOS thay vì giả lập phím bấm. Tính năng đang thử nghiệm, có thể chưa ổn định.",
                                inputSourceToggle)
                    SCardDivider()
                    HStack(spacing: 12) {
                        Image(systemName: "textformat.alt")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Kiểu hiển thị")
                                .font(.system(size: 13, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Picker("", selection: $inputSourceStyle) {
                            Text("Không gạch chân").tag("plain")
                            Text("Có gạch chân").tag("marked")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 170)
                        .onAppear {
                            // The old "replace text directly" option was
                            // unreliable; move its users to the plain style.
                            if inputSourceStyle == "direct" { inputSourceStyle = "plain" }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .disabled(!inputSourceModeFlag)
                    .opacity(inputSourceModeFlag ? 1 : 0.5)
                    SCardDivider()
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text(inputSourceStatusText)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Gỡ bộ gõ") {
                            inputSourceMode.uninstall()
                        }
                        .font(.system(size: 12))
                        .fixedSize()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
            }
        }
    }
}
