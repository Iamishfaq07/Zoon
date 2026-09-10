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

    func testRejectsMedicationAndSleepRestrictionAdvice() {
        for phrase in DiagnosticLanguageGuard.unsafeGuidanceTerms {
            XCTAssertTrue(
                DiagnosticLanguageGuard.rejects("Tonight, \(phrase) before bed."),
                "expected unsafe guidance \"\(phrase)\" to be rejected"
            )
        }
    }

    // MARK: - Causal overclaiming

    /// Every entry here was a real string in `RuleBasedInsightEngine` or
    /// `WeeklyReport`. The list exists so they cannot come back, and so the
    /// model-backed engines are held to the same standard as the rule-based
    /// one.
    func testCatchesEachCausalOverclaimTerm() {
        for term in DiagnosticLanguageGuard.causalOverclaimTerms {
            let text = "Last night was short, and \(term) something."
            XCTAssertTrue(
                DiagnosticLanguageGuard.overclaimsCausation(text),
                "expected \"\(term)\" to be caught"
            )
        }
    }

    func testCausalOverclaimingIsCaseInsensitive() {
        XCTAssertTrue(DiagnosticLanguageGuard.overclaimsCausation("This TRACES TO alcohol."))
    }

    /// Association language is exactly what Zoon should be using, so it must
    /// pass. A guard that rejects the correct phrasing would push copy back
    /// toward the wrong phrasing.
    func testAssociationLanguagePasses() {
        let allowed = [
            "Your HRV was lower than usual, alongside a late workout.",
            "These two signals moved together last night.",
            "Nights you logged alcohol averaged 8% lower recovery.",
            "This occurred near your latest bedtime of the week.",
            "An association in your data, not proof of cause.",
            "Worth watching over the next few nights.",
        ]
        for text in allowed {
            XCTAssertFalse(DiagnosticLanguageGuard.overclaimsCausation(text), text)
            XCTAssertFalse(DiagnosticLanguageGuard.containsBannedLanguage(text), text)
        }
    }

    /// Model output is refused for causal overclaiming the same way it is for
    /// naming a condition. Both callers fail closed, so a stricter guard costs
    /// an occasional good answer rather than showing a bad one.
    func testRejectsCausalOverclaimingInModelOutput() {
        XCTAssertTrue(DiagnosticLanguageGuard.rejects("Your poor sleep was caused by late caffeine."))
        XCTAssertTrue(DiagnosticLanguageGuard.rejects("Deep sleep is the first thing to suffer here."))
    }

    /// The connectives a model reaches for once it has been told not to say
    /// "caused". Each is an ordinary sentence, not a list entry pasted into
    /// a template.
    func testCatchesPlainCausalConnectives() {
        let overclaims = [
            "Your recovery dropped because of the late workout.",
            "Lower HRV due to alcohol.",
            "Late caffeine led to the extra awakenings.",
            "Screen time leads to lighter sleep.",
            "The early bedtime resulted in more deep sleep.",
            "Skipping the nap results in a longer night.",
            "Alcohol is the reason your REM fell.",
            "The flight was the reason you woke early.",
            "This explains why you felt groggy.",
            "The late meal made your night restless.",
            "Stress caused the short night.",
        ]
        for text in overclaims {
            XCTAssertTrue(DiagnosticLanguageGuard.overclaimsCausation(text), text)
        }
    }

    /// Whole words only. An honest reason for withholding a claim, and a
    /// word that merely contains a connective, must both keep passing --
    /// a guard that rejected them would push copy toward vaguer phrasing,
    /// not safer phrasing.
    func testHonestReasonsAndWordsContainingAConnectivePass() {
        let allowed = [
            "Zoon can't say yet because your history is short.",
            "Not enough nights resembled tomorrow for a forecast.",
            "The two moved together; nothing here says which came first.",
            "Your bedtime was later, alongside a lower recovery.",
        ]
        for text in allowed {
            XCTAssertFalse(DiagnosticLanguageGuard.overclaimsCausation(text), text)
        }
    }
}
