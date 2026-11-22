import SwiftUI

// MARK: - Language Button

struct PopoverLangButton: View {
    let label: String
    let flag: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Small keycap for the language flag
                Text(flag).font(.system(size: 10, weight: .bold, design: .rounded))
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, 3)
                    .background {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(active ? Color.white.opacity(0.35) : Color.primary.opacity(0.22))
                                .offset(y: 1)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(active ? Color.white.opacity(0.22) : Color(nsColor: .controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(active ? Color.white.opacity(0.4) : Color.primary.opacity(0.16), lineWidth: 1)
                                )
                        }
                    }
                Text(label)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(active ? UVieTheme.accent : .primary.opacity(0.06),
                         in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
