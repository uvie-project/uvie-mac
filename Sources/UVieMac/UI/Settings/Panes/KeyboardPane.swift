import SwiftUI

// MARK: - Keyboard Pane

struct KeyboardPane: View {
    @AppStorage(DefaultsKey.uppercaseFirstChar) private var uppercaseFirstChar: Bool = false
    @AppStorage(DefaultsKey.relaxedCoda) private var relaxedCoda: Bool = false
    @AppStorage(DefaultsKey.editCommittedWords) private var editCommittedWords: Bool = true
    @AppStorage(DefaultsKey.modernOrthography) private var modernOrthography: Bool = true
    @AppStorage(DefaultsKey.checkSpelling) private var checkSpelling: Bool = true
    @AppStorage(DefaultsKey.quickTelex) private var quickTelex: Bool = false
    @AppStorage(DefaultsKey.quickStart) private var quickStart: Bool = false
    @AppStorage(DefaultsKey.contextLanguageDetection) private var contextLanguageDetection: Bool = true

    var body: some View {
        PaneScroll {
            PaneSection("Dấu và chính tả") {
                SettingsCard {
                    SToggleRow("book.closed",
                                "Đặt dấu kiểu mới",
                                "Chọn vị trí dấu trong các vần oa, oe, uy. Kiểu mới viết hoà, thuý. Kiểu cũ viết hòa, thúy.",
                                $modernOrthography,
                                examples: [KeyExample(["h", "o", "a", "f"],
                                                      modernOrthography ? "hoà" : "hòa")])
                    SCardDivider()
                    SToggleRow("arrow.uturn.backward",
                                "Sửa dấu cho từ đã gõ",
                                "Gõ nhầm dấu? Bấm ← lùi về từ đó rồi gõ lại phím dấu, không cần xoá cả từ.",
                                $editCommittedWords,
                                examples: [KeyExample(["d", "o", "n", "␣", "←", "s"], "dón")])
                    SCardDivider()
                    SToggleRow("textformat",
                                "Viết hoa đầu câu",
                                "Tự viết hoa chữ đầu tiên sau dấu chấm hoặc khi xuống dòng.",
                                $uppercaseFirstChar)
                }
            }

            PaneSection("Tiếng Anh") {
                SettingsCard {
                    SToggleRow("textformat.abc",
                                "Giữ nguyên từ tiếng Anh",
                                "Gõ ghost, book hay safari thì UVie không biến thành chữ có dấu. Từ nào không phải tiếng Việt sẽ được trả lại đúng như bạn đã gõ.",
                                $checkSpelling)
                    SCardDivider()
                    SToggleRow("text.bubble",
                                "Đoán ngôn ngữ theo câu đang gõ",
                                "UVie nhìn cả câu để biết bạn đang viết tiếng Việt hay tiếng Anh. Nhờ vậy các từ dễ nhầm như nó, cả, có vẫn được bỏ dấu đúng, còn từ tiếng Anh thì giữ nguyên.",
                                $contextLanguageDetection)
                }
            }

            PaneSection("Gõ nhanh") {
                SettingsCard {
                    SToggleRow("g.circle",
                                "Viết tắt phụ âm cuối",
                                "Cho phép gõ g thay ng và h thay nh ở cuối từ. Chữ viết tắt vẫn nhận dấu.",
                                $relaxedCoda,
                                examples: [KeyExample(["d", "d", "a", "w", "j", "g"], "đặg")])
                    SCardDivider()
                    SToggleRow("bolt.fill",
                                "Gõ đôi ra phụ âm ghép",
                                "Bấm hai lần cùng một phím để ra phụ âm ghép. Áp dụng cho c, g, h, k, n, p, q, t.",
                                $quickTelex,
                                examples: [
                                    KeyExample(["c", "c"], "ch"),
                                    KeyExample(["n", "n"], "ng"),
                                    KeyExample(["t", "t"], "th"),
                                ])
                    SCardDivider()
                    SToggleRow("bolt",
                                "Một phím cho phụ âm đầu",
                                "Ở đầu từ, một phím thay cho cả phụ âm ghép.",
                                $quickStart,
                                examples: [
                                    KeyExample(["j"], "gi"),
                                    KeyExample(["f"], "ph"),
                                    KeyExample(["w"], "qu"),
                                ])
                }
            }
        }
    }
}
