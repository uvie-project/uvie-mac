import SwiftUI

// MARK: - Step 1: Permission

struct PermissionStep: View {
    @Binding var isTrusted: Bool
    let onRequest: () -> Void

    private var needsInputMonitoring: Bool { AccessibilityChecker.requiresInputMonitoring }
    private var inputMonitoringTrusted: Bool { AccessibilityChecker.isInputMonitoringTrusted }

    var body: some View {
        VStack(spacing: 22) {
            // Icon
            Image(systemName: isTrusted ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(isTrusted ? UVieTheme.accentText : .secondary)
                .frame(width: 92, height: 92)

            VStack(spacing: 6) {
                Text("Cấp quyền Trợ năng")
                    .font(.system(size: 22, weight: .bold))
                Text("UVie cần quyền này để đọc phím bạn bấm và thêm dấu tiếng Việt. Phím gõ được xử lý ngay trên máy của bạn.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 360)
            }

            // Accessibility status card
            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(isTrusted ? UVieTheme.accentText : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isTrusted ? "Đã có quyền Trợ năng" : "Chưa có quyền Trợ năng")
                            .font(.system(size: 13, weight: .semibold))
                        Text(isTrusted
                             ? "Bạn có thể tiếp tục."
                             : "Bấm nút bên dưới, rồi bật UVie trong danh sách.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if !isTrusted {
                    SCardDivider()
                    Button(action: onRequest) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.open")
                            Text("Mở cài đặt Trợ năng")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(UVieTheme.accentText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 380)

            // Input Monitoring (macOS 15+ only)
            if needsInputMonitoring {
                SettingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: inputMonitoringTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(inputMonitoringTrusted ? UVieTheme.accentText : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(inputMonitoringTrusted ? "Đã có quyền Input Monitoring" : "Chưa có quyền Input Monitoring")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Từ macOS 15, UVie cần thêm quyền này để đọc phím bạn bấm.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    if !inputMonitoringTrusted {
                        SCardDivider()
                        Button {
                            AccessibilityChecker.openInputMonitoringSettings()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.open")
                                Text("Mở cài đặt Input Monitoring")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .foregroundStyle(UVieTheme.accentText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 380)
            }
        }
        .padding(.horizontal, 48)
    }
}
