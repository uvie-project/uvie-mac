import SwiftUI

// MARK: - Advanced Pane

struct AdvancedPane: View {
    @AppStorage(DefaultsKey.modernOrthography) private var modernOrthography: Bool = true
    @AppStorage(DefaultsKey.checkSpelling) private var checkSpelling: Bool = true
    @AppStorage(DefaultsKey.quickTelex) private var quickTelex: Bool = false
    @AppStorage(DefaultsKey.quickStart) private var quickStart: Bool = false
    @AppStorage(DefaultsKey.contextLanguageDetection) private var contextLanguageDetection: Bool = true
    @AppStorage(Logger.keystrokeTraceKey) private var keystrokeTrace: Bool = false
    @AppStorage(DefaultsKey.inputSourceModeEnabled) private var inputSourceModeFlag: Bool = false
    @AppStorage(DefaultsKey.inputSourceStyle) private var inputSourceStyle: String = "marked"
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
        case .off: return "Tắt"
        case .installing: return "Đang cài đặt..."
        case .active: return "Đang hoạt động"
        case .failed(let message): return message
        case .unavailable: return "Không khả dụng trong bản dev"
        }
    }

    var body: some View {
        PaneScroll {
            PaneSection("Ngôn ngữ") {
                SettingsCard {
                    SToggleRow("book.closed",
                                "Chính tả hiện đại",
                                "Bật: hoas → hoá (quy tắc mới). Tắt: hoas → hoà (chính tả truyền thống).",
                                $modernOrthography)
                }
                SettingsCard {
                    SToggleRow("textformat.abc",
                                "Khôi phục từ tiếng Anh",
                                "Giữ nguyên từ tiếng Anh (reset, after, how are you…) và trả lại đúng phím đã gõ khi từ vừa gõ không phải tiếng Việt hợp lệ (law, dawf…).",
                                $checkSpelling)
                }
                SettingsCard {
                    SToggleRow("text.bubble",
                                "Nhận diện ngôn ngữ theo ngữ cảnh",
                                "Dùng NaturalLanguage của macOS để biết câu đang viết tiếng Việt hay tiếng Anh: câu tiếng Việt giữ dấu cho từ dễ nhầm (nó, cả, có), câu tiếng Anh giữ từ tiếng Anh.",
                                $contextLanguageDetection)
                }
            }

            PaneSection("Gõ tắt Telex") {
                SettingsCard {
                    SToggleRow("bolt.fill",
                                "Quick Telex (gõ kép)",
                                "Gõ đôi phụ âm: cc→ch, gg→gi, hh→nh, kk→kh, nn→ng, qq→qu, pp→ph, tt→th.",
                                $quickTelex)
                }
                SettingsCard {
                    SToggleRow("bolt",
                                "Quick Start (gõ nhanh)",
                                "j→gi, f→ph, w→qu ở đầu từ. Tiện khi gõ nhanh.",
                                $quickStart)
                }
            }

            PaneSection("Tương thích trình duyệt") {
                SettingsCard {
                    HStack(spacing: 14) {
                        Image(systemName: "globe")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sửa lỗi Chromium / Safari")
                                .font(.system(size: 13, weight: .medium))
                            Text("Khắc phục các vấn đề khi gõ trong trình duyệt, thêm app ở tab Ứng Dụng")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                    }
                    .padding(14)
                }
            }

            PaneSection("Quyền truy cập") {
                SettingsCard {
                    Button { AccessibilityChecker.openPrivacySettings() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Cài đặt Trợ năng (Accessibility)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("Mở System Settings để quản lý quyền bàn phím")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                }
            }

            PaneSection("Input Source") {
                SettingsCard {
                    SToggleRow("keyboard.badge.ellipsis",
                                "Chế độ Input Source (thử nghiệm)",
                                "Gõ qua bộ gõ hệ thống của macOS thay vì giả lập phím. Khi bộ gõ UVie đang được chọn, chế độ giả lập phím tự tắt.",
                                inputSourceToggle)
                }
                SettingsCard {
                    HStack(spacing: 14) {
                        Image(systemName: "textformat.alt")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Kiểu hiển thị")
                                .font(.system(size: 13, weight: .medium))
                        }
                        Spacer()
                        Picker("", selection: $inputSourceStyle) {
                            Text("Gạch chân từ đang gõ (ổn định)").tag("marked")
                            Text("Thay trực tiếp (thử nghiệm)").tag("direct")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    .padding(14)
                    .disabled(!inputSourceModeFlag)
                    .opacity(inputSourceModeFlag ? 1 : 0.5)
                }
                SettingsCard {
                    HStack(spacing: 14) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text(inputSourceStatusText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Gỡ bộ gõ") {
                            inputSourceMode.uninstall()
                        }
                        .font(.system(size: 12))
                    }
                    .padding(14)
                }
            }

            PaneSection("Chẩn đoán") {
                SettingsCard {
                    SToggleRow("keyboard",
                                "Bật chẩn đoán",
                                "Ghi lại mỗi phím gõ để gửi báo cáo lỗi. Hãy tắt sau khi gửi log.",
                                $keystrokeTrace)
                }
                SettingsCard {
                    Button {
                        if let url = Logger.shared.writeDiagnosticsToTempFile() {
                            // Reveal the diagnostics file in Finder so the user
                            // can drag it into Mail / AirDrop / Messages.
                            // Avoids NSSharingServicePicker (which caused an
                            // over-release crash on macOS 26 — the picker is
                            // not retained and its blocks get freed during
                            // the CA transaction commit).
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "envelope")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Gửi log chẩn đoán")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("Tạo file .txt chứa log + thông tin hệ thống, mở trong Finder để chia sẻ")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
