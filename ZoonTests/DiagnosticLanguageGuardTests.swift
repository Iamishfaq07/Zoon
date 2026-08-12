import XCTest

/// `DiagnosticLanguageGuard` is the structural backstop both
/// FoundationModelInsightEngine and CoachChat rely on to keep a model's
/// output off-screen if it slips past its own "never diagnose" instructions.
/// Locking its behavior in here matters more than most pure-logic tests in
/// this target: a regression here would let diagnostic language reach a user
/// silently, with nothing else catching it.
final class DiagnosticLanguageGuardTests: XCTestCase {

    func testCleanTextPasses() {
        XCTAssertFalse(DiagnosticLanguageGuard.containsBannedLanguage(
            "Your HRV was a bit lower than usual, likely from yesterday's workout."
        ))
    }

    func testCatchesEachBannedTerm() {
        for term in DiagnosticLanguageGuard.bannedTerms {
            let text = "This might be a sign of \(term) based on your data."
            XCTAssertTrue(
                DiagnosticLanguageGuard.containsBannedLanguage(text),
                "expected \"\(term)\" to be caught"
            )
        }
    }

    func testCaseInsensitive() {
        XCTAssertTrue(DiagnosticLanguageGuard.containsBannedLanguage("Sounds like INSOMNIA to me."))
    }

    func testMatchesAsSubstringWithinALongerWord() {
        // "diagnos" is a stem match by design (diagnose/diagnosis/diagnostic).
        XCTAssertTrue(DiagnosticLanguageGuard.containsBannedLanguage("I can't diagnose that."))
    }
}
