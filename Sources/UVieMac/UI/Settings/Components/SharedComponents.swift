import SwiftUI

// MARK: - Shared Components

struct PaneScroll<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            // Always fill the pane: a narrow pane's content used to be centered
            // by the ScrollView, so it shifted sideways between tabs.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct PaneSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            content
        }
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(nsColor: .controlBackgroundColor),
                         in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

struct SCardDivider: View {
    var body: some View {
        Divider().padding(.leading, 50)
    }
}

// MARK: - Keycaps

/// One "keys -> result" typing example, shown as key presses.
struct KeyExample: Identifiable {
    let id = UUID()
    let keys: [String]
    let result: String

    init(_ keys: [String], _ result: String) {
        self.keys = keys
        self.result = result
    }
}

/// One rendered key: a small cap with a border and a darker bottom edge so
/// it reads as a physical key. Not interactive.
struct KeyCap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 20, minHeight: 20)
            .padding(.horizontal, 5)
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
}

/// Lays one or more key examples out horizontally.
struct KeyExampleRow: View {
    let examples: [KeyExample]

    init(_ examples: [KeyExample]) {
        self.examples = examples
    }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(examples) { example in
                HStack(spacing: 3) {
                    ForEach(Array(example.keys.enumerated()), id: \.offset) { _, key in
                        KeyCap(key)
                    }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 2)
                    Text(example.result)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, 2)
                }
                .fixedSize()
            }
        }
    }
}

struct SToggleRow: View {
    let icon: String
    let title: String
    let description: String
    let examples: [KeyExample]
    @Binding var isOn: Bool

    init(_ icon: String, _ title: String, _ description: String, _ isOn: Binding<Bool>,
         examples: [KeyExample] = []) {
        self.icon = icon
        self.title = title
        self.description = description
        self._isOn = isOn
        self.examples = examples
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                if !examples.isEmpty {
                    KeyExampleRow(examples)
                        .padding(.top, 6)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

/// A tappable row that looks like `SToggleRow` but ends in a trailing
/// SF symbol instead of a switch (settings links, export actions).
struct SActionRow: View {
    let icon: String
    let title: String
    let description: String
    let trailing: String
    let trailingColor: Color?
    let action: (() -> Void)?

    init(_ icon: String, _ title: String, _ description: String,
         trailing: String, trailingColor: Color? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.description = description
        self.trailing = trailing
        self.trailingColor = trailingColor
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: trailing)
                .font(.system(size: 12))
                .foregroundStyle(trailingColor ?? Color.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// A card-shaped notice shown above the hero on the General pane when a
/// condition needs the user's attention (missing permission, non-Latin
/// layout, active keystroke trace).
struct StatusBanner: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(tint.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: UVieTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: UVieTheme.cardRadius)
                .strokeBorder(tint.opacity(0.30), lineWidth: 1)
        )
    }
}

struct ComingSoonBadge: View {
    var body: some View {
        Text("Sắp ra mắt")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.orange.opacity(0.1), in: Capsule())
    }
}
