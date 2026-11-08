// PostTonedSyllableReproTests.swift
// Regression tests for Telex composition state desynchronization / hybrid
// passthrough and V-C-V boundary corruption when typing after a completed
// toned Vietnamese syllable.
//
// Shared from cross-engine Vietnamese IME test cases in VieLotus-IM:
// https://github.com/stevedat/VieLotus-IM
//
// These cases previously reproduced engine bugs in uvie-rs (hybrid
// `đuowcju` output, silently dropped tone keys after `dd`, `viêtju` /
// `tiêngsu` corruption). The engine now preserves the completed syllable
// and starts a new one; expectations below assert the fixed behavior.

import XCTest
@testable import UVieMac

final class PostTonedSyllableReproTests: XCTestCase {

    // MARK: - 1. Typing 'u' after "được" across Telex keystroke orders

    func testPostTonedDuoc_StandardOrder_PlusU() {
        XCTAssertEqual(typeString("dduowcj"), "được")
        XCTAssertEqual(typeString("dduowcju"), "đượcu")
    }

    func testPostTonedDuoc_ToneBeforeCoda_PlusU() {
        XCTAssertEqual(typeString("dduowjc"), "được")
        XCTAssertEqual(typeString("dduowjcu"), "đượcu")
    }

    func testPostTonedDuoc_EarlyToneOnU_PlusU() {
        XCTAssertEqual(typeString("ddujowc"), "được")
        XCTAssertEqual(typeString("ddujowcu"), "đượcu")
    }

    // A tone key typed before any vowel is deferred as a pending tone:
    // invisible until the first vowel adopts it, so "ddjuowc" becomes
    // "được". With no vowel ever arriving ("ddf") it stays hidden and the
    // word renders "đ" — matching the old silent-swallow contract.
    func testPostTonedDuoc_ToneImmediatelyAfterDD_PlusU() {
        XCTAssertEqual(typeString("ddjuowc"), "được")
        XCTAssertEqual(typeString("ddjuowcu"), "đượcu")
        XCTAssertEqual(typeString("ddju"), "đụ")
        XCTAssertEqual(typeString("ddf"), "đ")
        XCTAssertEqual(typeString("ddsu"), "đú")
    }

    // MARK: - 2. `dd` ('đ') initial words get the same optimistic-consonant
    //    and V-C-V treatment as every other onset

    func testDDInitialWord_OptimisticConsonantAndVCVSplit() {
        // Optimistic consonant append: "nêb" -> "nêbo" on the trailing vowel.
        XCTAssertEqual(typeString("neeb"), "nêb")
        XCTAssertEqual(typeString("neebo"), "nêbo")
        XCTAssertEqual(typeString("ddeeb"), "đêb")
        XCTAssertEqual(typeString("ddeebo"), "đêbo")

        // V-C-V split: "nề" + "bo".
        XCTAssertEqual(typeString("neefbo"), "nềbo")
        XCTAssertEqual(typeString("ddeefbo"), "đềbo")

        // "ê" + 'b' is an invalid rhyme/coda pair, so both spellings pass
        // through raw — the engine must not invent "đềb".
        XCTAssertEqual(typeString("neefb"), "neefb")
        XCTAssertEqual(typeString("ddeefb"), "đeefb")
    }

    // MARK: - 3. V-C-V split must not strip coda/tone keys from a completed
    //    toned syllable ("việt" + u used to give "viêtju")

    func testVCVSplit_PostCodaTonedSyllables() {
        XCTAssertEqual(typeString("vieetj"), "việt")
        XCTAssertEqual(typeString("vieetju"), "việtu")
        XCTAssertEqual(typeString("tieengs"), "tiếng")
        XCTAssertEqual(typeString("tieengsu"), "tiếngu")
    }
}
