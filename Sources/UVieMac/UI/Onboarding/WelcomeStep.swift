import SwiftUI

// MARK: - Step 0: Welcome

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 22) {
            // App icon
            Image(nsImage: appIconImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 92, height: 92)

            VStack(spacing: 6) {
                Text("Chào bạn, đây là UVie")
                    .font(.system(size: 24, weight: .bold))
                Text("Bộ gõ tiếng Việt nhanh, nhẹ cho macOS.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            // One keycap example at a larger scale
            HStack(spacing: 3) {
                ForEach(["v", "i", "e", "e", "j", "t"], id: \.self) { key in
                    Text(key)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .frame(width: 26, height: 26)
                        .background {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: UVieTheme.keycapRadius)
                                    .fill(Color.primary.opacity(0.22))
                                    .offset(y: 1)
                                RoundedRectangle(cornerRadius: UVieTheme.keycapRadius)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: UVieTheme.keycapRadius)
                                            .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                                    )
                            }
                        }
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
                Text("việt")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.leading, 4)
            }

            // Feature highlights
            SettingsCard {
                infoRow("bolt",           "Nhanh",               "Chữ hiện ra ngay khi bạn bấm phím.")
                SCardDivider()
                infoRow("keyboard",       "Gõ theo cách bạn quen", "Telex, VNI hay Simple Telex, đổi lúc nào cũng được.")
                SCardDivider()
                infoRow("memorychip",     "Nhẹ máy",             "Chạy nền trên thanh menu, gần như không tốn pin hay bộ nhớ.")
            }
            .frame(maxWidth: 380)
        }
        .padding(.horizontal, 48)
    }

    private func infoRow(_ icon: String, _ title: String, _ description: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func appIconImage() -> NSImage {
        // 1) Try the app bundle's icon (used in packaged .app builds)
        if let bundleIcon = NSImage(named: "AppIcon") {
            return bundleIcon
        }
        // 2) Fall back to the source repo path (used during `swift build` / Xcode run)
        let sourceFile = URL(fileURLWithPath: #file)
        let repoIcon = sourceFile
            .deletingLastPathComponent() // Onboarding
            .deletingLastPathComponent() // UI
            .deletingLastPathComponent() // UVieMac
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // UVieMac
            .appendingPathComponent("AppIcon.icns")
        if let repoIconImage = NSImage(contentsOf: repoIcon) {
            return repoIconImage
        }
        // 3) Last resort blank image
        return NSImage(size: NSSize(width: 92, height: 92))
    }
}
