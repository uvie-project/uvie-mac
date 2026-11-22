import SwiftUI

// MARK: - Step 2: Ready

struct ReadyStep: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(UVieTheme.accentText)
                .frame(width: 92, height: 92)

            VStack(spacing: 6) {
                Text("Xong rồi, gõ thử nhé")
                    .font(.system(size: 26, weight: .bold))
                Text("UVie đang chạy trên thanh menu.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            // Restart hint — macOS requires a process restart to fully
            // activate the Accessibility grant in some cases (especially
            // 14+ and 26). We prompt the user here so they don't end up
            // with a "running but not typing" state (Bug #6).
            SettingsCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(UVieTheme.accentText)
                        .frame(width: 24, alignment: .center)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chưa gõ được tiếng Việt?")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Thoát UVie rồi mở lại để macOS áp dụng quyền vừa cấp.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: 380)

            // Quick tips
            SettingsCard {
                tipRow("keyboard",                     "Bấm biểu tượng V/E trên thanh menu hoặc phím Fn để đổi ngôn ngữ.")
                SCardDivider()
                tipRow("gearshape",                    "Mở Cài đặt để chọn kiểu gõ và bật thêm tính năng.")
                SCardDivider()
                tipRow("arrow.triangle.2.circlepath",  "Bật Nhớ ngôn ngữ để UVie tự chuyển theo từng ứng dụng.")
            }
            .frame(maxWidth: 380)
        }
        .padding(.horizontal, 48)
    }

    private func tipRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
