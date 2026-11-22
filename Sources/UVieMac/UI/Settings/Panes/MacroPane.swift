import SwiftUI

// MARK: - Macro Pane

struct MacroPane: View {
    @AppStorage(DefaultsKey.macroEnabled) private var macroEnabled: Bool = false
    @StateObject private var macroManager = MacroManager.shared
    @State private var showingAddSheet = false
    @State private var newAbbreviation = ""
    @State private var newExpansion = ""

    var body: some View {
        PaneScroll {
            PaneSection("Gõ tắt") {
                SettingsCard {
                    SToggleRow("wand.and.rays",
                                "Bật gõ tắt",
                                "Gõ một cụm ngắn rồi bấm Space hoặc Enter, UVie thay bằng đoạn văn bản đầy đủ.",
                                $macroEnabled,
                                examples: [KeyExample(["b", "t", "w", "␣"], "by the way")])
                }
            }

            if macroEnabled {
                PaneSection("Danh sách gõ tắt") {
                    SettingsCard {
                        // Table header
                        HStack {
                            Text("Bạn gõ")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .leading)
                            Text("UVie thay bằng")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.04))

                        if macroManager.macros.isEmpty {
                            Text("Chưa có mục nào. Bấm Thêm gõ tắt để tạo mục đầu tiên.")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 18)
                        }

                        ForEach(macroManager.macros) { macro in
                            SCardDivider()
                            HStack {
                                Text(macro.abbreviation)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(UVieTheme.accentText)
                                    .frame(width: 100, alignment: .leading)
                                Text(macro.expansion)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button {
                                    macroManager.deleteMacro(macro)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Xoá")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                        }
                    }

                    HStack {
                        Spacer()
                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("Thêm gõ tắt", systemImage: "plus.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(UVieTheme.accentText)
                        }
                        .buttonStyle(.plain)
                    }
                    .sheet(isPresented: $showingAddSheet) {
                        AddMacroSheet(abbreviation: $newAbbreviation, expansion: $newExpansion) {
                            macroManager.addMacro(abbreviation: newAbbreviation, expansion: newExpansion)
                            newAbbreviation = ""
                            newExpansion = ""
                            showingAddSheet = false
                        }
                    }
                }
            }
        }
    }
}
