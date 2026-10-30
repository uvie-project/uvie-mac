// PostTonedSyllableReproTests.swift
// Reproduction tests for Telex composition state desynchronization / hybrid passthrough
// and V-C-V boundary corruption when typing after a completed toned Vietnamese syllable.
//
// Shared from cross-engine Vietnamese IME test cases in VieLotus-IM:
// https://github.com/stevedat/VieLotus-IM

import XCTest
@testable import UVieMac

final class PostTonedSyllableReproTests: XCTestCase {

    // MARK: - 1. Typing 'u' after "được" across Telex keystroke orders

    func testPostTonedDuoc_StandardOrder_PlusU() {
        let beforeU = typeString("dduowcj")
        XCTAssertEqual(beforeU, "được")

        let afterU = typeString("dduowcju")
        // Currently in libuvie v2.8.2, `render_passthrough` keeps 'đ' for `dd` while
        // unfolding `ược` into raw ASCII `uowcju`, producing the hybrid `"đuowcju"`.
        XCTAssertEqual(afterU, "đuowcju")

        XCTExpectFailure("Known bug in uvie-rs: typing 'u' after 'được' (dduowcju) produces half-converted 'đuowcju'") {
            XCTAssertTrue(
                afterU == "đượcu" || afterU == "dduowcju",
                "Expected preserved 'đượcu' or full raw 'dduowcju', got \(afterU)"
            )
        }
    }

    func testPostTonedDuoc_ToneBeforeCoda_PlusU() {
        let beforeU = typeString("dduowjc")
        XCTAssertEqual(beforeU, "được")

        let afterU = typeString("dduowjcu")
        XCTAssertEqual(afterU, "đuowjcu")

        XCTExpectFailure("Known bug in uvie-rs: typing 'u' after 'được' (dduowjcu) produces half-converted 'đuowjcu'") {
            XCTAssertTrue(
                afterU == "đượcu" || afterU == "dduowjcu",
                "Expected preserved 'đượcu' or full raw 'dduowjcu', got \(afterU)"
            )
        }
    }

    func testPostTonedDuoc_EarlyToneOnU_PlusU() {
        let beforeU = typeString("ddujowc")
        XCTAssertEqual(beforeU, "được")

        let afterU = typeString("ddujowcu")
        XCTAssertEqual(afterU, "đujowcu")

        XCTExpectFailure("Known bug in uvie-rs: typing 'u' after 'được' (ddujowcu) produces half-converted 'đujowcu'") {
            XCTAssertTrue(
                afterU == "đượcu" || afterU == "ddujowcu",
                "Expected preserved 'đượcu' or full raw 'ddujowcu', got \(afterU)"
            )
        }
    }

    func testPostTonedDuoc_ToneImmediatelyAfterDD_PlusU() {
        let beforeU = typeString("ddjuowc")
        let afterU = typeString("ddjuowcu")
        XCTAssertEqual(beforeU, "đươc")
        XCTAssertEqual(afterU, "đuowcu")

        XCTExpectFailure("Known bug in uvie-rs: tone key 'j' typed right after 'dd' is dropped (ddjuowc -> đươc)") {
            XCTAssertEqual(beforeU, "được")
            XCTAssertTrue(afterU == "đượcu" || afterU == "ddjuowcu")
        }
    }

    // MARK: - 2. `dd` ('đ') initial words bypass optimistic consonant & V-C-V splitting

    func testDDInitialWord_OptimisticConsonantAndVCVSplit() {
        // Non-dd word works via optimistic consonant append & V-C-V split:
        XCTAssertEqual(typeString("neeb"), "nêb")
        XCTAssertEqual(typeString("neebo"), "nêbo")

        // For `dd` words, `is_raw_passthrough_slice` compares `'d'` with `'đ'` and
        // returns `false`, bypassing optimistic consonant and V-C-V split:
        let ddeefb = typeString("ddeefb")
        let ddeefbo = typeString("ddeefbo")
        XCTAssertEqual(ddeefb, "đeefb")
        XCTAssertEqual(ddeefbo, "đeefbo")

        XCTExpectFailure("Known bug in uvie-rs: is_raw_passthrough_slice returns false for 'dd' words") {
            XCTAssertEqual(ddeefb, "đềb")
            XCTAssertEqual(ddeefbo, "đềbo")
        }
    }

    // MARK: - 3. V-C-V split strips post-coda tone keys ("việt" + u -> "viêtju")

    func testVCVSplit_PostCodaTonedSyllables() {
        XCTAssertEqual(typeString("vieetj"), "việt")
        XCTAssertEqual(typeString("tieengs"), "tiếng")

        let vietU = typeString("vieetju")
        let tiengU = typeString("tieengsu")
        XCTAssertEqual(vietU, "viêtju")
        XCTAssertEqual(tiengU, "tiêngsu")

        XCTExpectFailure("Known bug in uvie-rs: find_split_point splits before coda when tone key follows coda") {
            XCTAssertTrue(vietU == "việtu" || vietU == "vieetju", "Got \(vietU)")
            XCTAssertTrue(tiengU == "tiếngu" || tiengU == "tieengsu", "Got \(tiengU)")
        }
    }
}
