import Foundation
import UIKit

/// A real, exportable PDF — 30 or 90 days of sleep data laid out for a
/// clinician to skim, not the app's own dark-mode screens.
///
/// Deliberately light-background and print-friendly: screenshotting the
/// dark-mode app UI and calling it a report is the wrong instinct for a
/// document meant to be printed or read on a clinic's monitor. This draws
/// its own plain, high-contrast layout independent of the app's theme.
enum ClinicianReportGenerator {

    enum Section: String, CaseIterable, Identifiable {
        case sleepTiming = "Sleep Timing"
        case sleepDuration = "Sleep Duration"
        case sleepStages = "Sleep Stages"
        case awakenings = "Awakenings"
        case heartRateHRV = "Heart Rate & HRV"
        case respiration = "Respiratory Rate"
        case temperature = "Wrist Temperature"
        case breathingDisturbances = "Breathing Disturbances"
        case spO2 = "Blood Oxygen"

        var id: String { rawValue }
    }

    private static let disclaimer = """
        This report contains measurements and estimates from a consumer wearable device \
        and is intended to support discussion with a qualified healthcare professional. \
        It is not a diagnosis.
        """

    static func generate(
        nights: [SleepNightFeatures],
        sections: Set<Section>,
        rangeDays: Int,
        goalMinutes: Double,
        age: Int? = nil,
        biologicalSex: DemographicBaseline.Sex = .unspecified,
        bodyMassIndex: Double? = nil
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter, 72dpi
        let margin: CGFloat = 44
        let contentWidth = pageRect.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let windowed = Array(nights.suffix(rangeDays))

        return renderer.pdfData { context in
            var cursor: CGFloat = 0

            func newPage() {
                context.beginPage()
                cursor = margin
                drawFooter(in: pageRect, margin: margin)
            }

            func ensureSpace(_ height: CGFloat) {
                if cursor + height > pageRect.height - margin - 30 {
                    newPage()
                }
            }

            func draw(_ text: String, font: UIFont, color: UIColor = .black, spacingAfter: CGFloat = 4) {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let bounding = (text as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin],
                    attributes: attributes, context: nil
                )
                ensureSpace(bounding.height + spacingAfter)
                (text as NSString).draw(
                    in: CGRect(x: margin, y: cursor, width: contentWidth, height: bounding.height),
                    withAttributes: attributes
                )
                cursor += bounding.height + spacingAfter
            }

            func drawRow(_ label: String, _ value: String) {
                let font = UIFont.systemFont(ofSize: 11)
                ensureSpace(18)
                (label as NSString).draw(
                    at: CGPoint(x: margin, y: cursor),
                    withAttributes: [.font: font, .foregroundColor: UIColor.darkGray]
                )
                (value as NSString).draw(
                    at: CGPoint(x: margin + 220, y: cursor),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.black]
                )
                cursor += 18
            }

            // --- Title page --------------------------------------------------
            newPage()
            draw("Sleep Report", font: .boldSystemFont(ofSize: 26), spacingAfter: 6)
            draw("\(rangeDays)-day summary, generated \(Date.now.formatted(.dateTime.day().month().year()))",
                 font: .systemFont(ofSize: 13), color: .darkGray, spacingAfter: 4)
            draw("\(windowed.count) nights with data in this range", font: .systemFont(ofSize: 12), color: .darkGray, spacingAfter: 8)
            for row in demographicRows(age: age, sex: biologicalSex, bodyMassIndex: bodyMassIndex) {
                drawRow(row.0, row.1)
            }
            cursor += 10

            guard !windowed.isEmpty else {
                draw("No nights recorded in this range.", font: .systemFont(ofSize: 13), color: .darkGray)
                draw(disclaimer, font: .italicSystemFont(ofSize: 9), color: .gray)
                return
            }

            draw("Overview", font: .boldSystemFont(ofSize: 15), spacingAfter: 8)
            let durations = windowed.map(\.total24hAsleepMinutes)
            let meetingGoal = windowed.filter { $0.total24hAsleepMinutes >= goalMinutes }.count
            drawRow("Nights meeting sleep goal", "\(meetingGoal) of \(windowed.count)")
            if let longest = windowed.max(by: { $0.total24hAsleepMinutes < $1.total24hAsleepMinutes }) {
                drawRow(
                    "Longest night",
                    "\(minutesLabel(longest.total24hAsleepMinutes)) · \(longest.date.formatted(.dateTime.month().day()))"
                )
            }
            if let shortest = windowed.min(by: { $0.total24hAsleepMinutes < $1.total24hAsleepMinutes }) {
                drawRow(
                    "Shortest night",
                    "\(minutesLabel(shortest.total24hAsleepMinutes)) · \(shortest.date.formatted(.dateTime.month().day()))"
                )
            }
            drawRow("Median total sleep", measure(durations, minutesLabel))
            cursor += 6

            for section in Section.allCases where sections.contains(section) {
                ensureSpace(30)
                cursor += 10
                draw(section.rawValue, font: .boldSystemFont(ofSize: 15), spacingAfter: 8)
                drawSection(section, nights: windowed, goalMinutes: goalMinutes, drawRow: drawRow)
                cursor += 6
            }

            cursor += 12
            draw(disclaimer, font: .italicSystemFont(ofSize: 9), color: .gray)
        }
    }

    private static func drawSection(
        _ section: Section,
        nights: [SleepNightFeatures],
        goalMinutes: Double,
        drawRow: (String, String) -> Void
    ) {
        switch section {
        case .sleepTiming:
            // Bedtime and wake time are angles. The rows this replaced took
            // an ordinary median and an ordinary standard deviation of clock
            // readings that had been shifted at 18:00 to make the arithmetic
            // work for a night sleeper -- which moves the discontinuity
            // rather than removing it, and puts it exactly where a shift
            // worker's bedtimes live. `SleepTimingSummary` computes these on
            // the circle, and is in Shared/ so the statistics on a document a
            // clinician may act on are actually tested.
            for row in SleepTimingSummary.make(nights: nights).rows {
                drawRow(row.label, row.value)
            }

        case .sleepDuration:
            // `total24hAsleepMinutes` (main sleep plus naps/secondary
            // episodes), not `timeAsleepMinutes` alone -- the row is
            // labeled "total sleep time", and a clinician comparing this
            // against a patient-reported "I also nap most afternoons"
            // deserves a number that actually includes the nap rather than
            // one that silently doesn't, despite the label's own claim.
            let durations = nights.map(\.total24hAsleepMinutes)
            drawRow("Nights with duration data", "\(durations.count)")
            drawRow("Median total sleep time", measure(durations, minutesLabel))
            if let low = durations.min(), let high = durations.max() {
                drawRow("Range", "\(minutesLabel(low)) – \(minutesLabel(high)) across \(durations.count) nights")
            } else {
                drawRow("Range", "Not available")
            }
            drawRow("Sleep goal", minutesLabel(goalMinutes))
            let efficiency = nights.map(\.sleepEfficiencyPercent)
            drawRow("Median sleep efficiency", measure(efficiency) { String(format: "%.1f%%", $0) })

        case .sleepStages:
            let staged = nights.filter(\.hasStageBreakdown)
            if staged.isEmpty {
                drawRow("Stage data", "Not available for this range")
            } else {
                drawRow("Median deep sleep", measure(staged.map(\.deepMinutes), minutesLabel))
                drawRow("Median REM sleep", measure(staged.map(\.remMinutes), minutesLabel))
                drawRow("Median core/light sleep", measure(staged.map(\.coreMinutes), minutesLabel))
                drawRow("Nights with stage data", "\(staged.count) of \(nights.count)")
            }

        case .awakenings:
            let counts = nights.map { Double($0.wakeCount) }
            drawRow("Nights with awakening data", "\(counts.count)")
            drawRow("Median awakenings per night", measure(counts) { String(format: "%.1f", $0) })
            drawRow("Median awake time", measure(nights.map(\.awakeMinutes), minutesLabel))

        case .heartRateHRV:
            let hr = nights.compactMap(\.avgHeartRate)
            let hrv = nights.compactMap(\.avgHRV)
            if !hr.isEmpty {
                drawRow("Median sleeping heart rate", measure(hr) { "\(Int($0.rounded())) bpm" })
                drawRow("Heart rate nights with data", "\(hr.count) of \(nights.count)")
            }
            if !hrv.isEmpty {
                drawRow("Median HRV (SDNN)", measure(hrv) { "\(Int($0.rounded())) ms" })
                drawRow("HRV nights with data", "\(hrv.count) of \(nights.count)")
            }
            if hr.isEmpty && hrv.isEmpty {
                drawRow("Heart rate / HRV", "Not available for this range")
            }

        case .respiration:
            let rate = nights.compactMap(\.avgRespiratoryRate)
            if rate.isEmpty {
                drawRow("Respiratory rate", "Not available for this range")
            } else {
                drawRow("Median respiratory rate", measure(rate) { String(format: "%.1f breaths/min", $0) })
                drawRow("Nights with data", "\(rate.count) of \(nights.count)")
            }

        case .temperature:
            let deltas = nights.compactMap(\.wristTempDeltaC)
            if deltas.isEmpty {
                drawRow("Wrist temperature", "Not available for this range")
            } else {
                drawRow("Median deviation from baseline", measure(deltas) { String(format: "%+.2f°C", $0) })
                drawRow("Nights with data", "\(deltas.count) of \(nights.count)")
            }

        case .breathingDisturbances:
            let measuredNights = nights.filter { $0.breathingDisturbances != nil }
            if measuredNights.isEmpty {
                drawRow("Breathing disturbances", "Not available on this device/range")
            } else {
                let values = measuredNights.compactMap(\.breathingDisturbances)
                drawRow("Median, % of night", measure(values) { String(format: "%.1f%%", $0) })
                drawRow("Nights with data", "\(values.count) of \(nights.count)")

                // Only Apple's classification is reported, and only against
                // the count of nights that actually carry one.
                //
                // This row previously read "N of M" where M was every
                // measured night and the classification fell back to an
                // in-app 5%-of-night cutoff Zoon invented. On a document
                // headed for a clinician, that presented an uncalibrated
                // in-app heuristic as a classification. If nothing here is
                // classified, the row says so rather than reporting zero.
                let classified = BreathingHealth.classified(measuredNights)
                if classified.isEmpty {
                    drawRow("Nights classified elevated", "Not classified on this device/range")
                } else {
                    let elevated = classified.filter(BreathingHealth.isElevated).count
                    drawRow(
                        "Nights classified elevated (Apple)",
                        "\(elevated) of \(classified.count) classified"
                    )
                }
            }

        case .spO2:
            let spo2 = nights.compactMap(\.avgSpO2)
            if spo2.isEmpty {
                drawRow("Blood oxygen", "Not available on this device/range")
            } else {
                drawRow("Median SpO2", measure(spo2) { String(format: "%.0f%%", $0) })
                drawRow("Nights with data", "\(spo2.count) of \(nights.count)")
            }
        }
    }

    private static func drawFooter(in pageRect: CGRect, margin: CGFloat) {
        let text = "Generated by Zoon -- on-device only, never uploaded" as NSString
        let font = UIFont.systemFont(ofSize: 8)
        text.draw(
            at: CGPoint(x: margin, y: pageRect.height - margin + 6),
            withAttributes: [.font: font, .foregroundColor: UIColor.lightGray]
        )
    }

    private static func minutesLabel(_ minutes: Double) -> String {
        SleepNightFeatures.formatMinutes(abs(minutes))
    }

    /// A median, or the words "Not available".
    ///
    /// Every row here used to end `?? 0`, which prints `0m`, `00:00` or
    /// `0.0%` when there is nothing to report. On a document a clinician may
    /// act on, a plausible-looking zero is the worst possible rendering of
    /// "we do not know" -- it is indistinguishable from a real measurement.
    private static func measure(_ values: [Double], _ format: (Double) -> String) -> String {
        guard let median = Statistics.median(values) else { return "Not available" }
        return format(median)
    }

    static func filename(rangeDays: Int) -> String {
        "Sleep_Report_\(ISO8601DateFormatter.dayString(for: .now, timeZone: .current))_\(rangeDays)_Days.pdf"
    }

    /// Self-reported profile for the title page. Omitted rows stay off the
    /// document rather than printing "Not set" — a clinician report should
    /// not look like a missing-data form.
    static func demographicRows(
        age: Int?,
        sex: DemographicBaseline.Sex,
        bodyMassIndex: Double?
    ) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let age {
            rows.append(("Age (self-reported)", "\(age)"))
        }
        if sex != .unspecified {
            rows.append(("Sex (self-reported)", sex.rawValue.capitalized))
        }
        if let bodyMassIndex {
            rows.append(("BMI (self-reported)", String(format: "%.0f", bodyMassIndex)))
        }
        return rows
    }
}
