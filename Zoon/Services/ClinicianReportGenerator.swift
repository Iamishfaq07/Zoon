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
        goalMinutes: Double
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
            draw("\(windowed.count) nights with data in this range", font: .systemFont(ofSize: 12), color: .darkGray, spacingAfter: 18)

            guard !windowed.isEmpty else {
                draw("No nights recorded in this range.", font: .systemFont(ofSize: 13), color: .darkGray)
                draw(disclaimer, font: .italicSystemFont(ofSize: 9), color: .gray)
                return
            }

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
            // Each night's own timezone, not the device's current one -- a
            // clinician report drawn after the user has traveled shouldn't
            // silently recompute historical bedtimes in the wrong zone.
            let bedtimes = nights.map { night -> Double in
                var calendar = Calendar.current
                calendar.timeZone = night.timeZone
                return Statistics.circularMinutesFromMidnight(night.bedtime, calendar: calendar)
            }
            let wakeTimes = nights.map { night -> Double in
                var calendar = Calendar.current
                calendar.timeZone = night.timeZone
                return Statistics.circularMinutesFromMidnight(night.wakeTime, calendar: calendar)
            }
            drawRow("Median bedtime", clockLabel(Statistics.median(bedtimes) ?? 0))
            drawRow("Median wake time", clockLabel(Statistics.median(wakeTimes) ?? 0))
            drawRow("Bedtime variability (SD)", minutesLabel(Statistics.standardDeviation(bedtimes) ?? 0))

        case .sleepDuration:
            // `total24hAsleepMinutes` (main sleep plus naps/secondary
            // episodes), not `timeAsleepMinutes` alone -- the row is
            // labeled "total sleep time", and a clinician comparing this
            // against a patient-reported "I also nap most afternoons"
            // deserves a number that actually includes the nap rather than
            // one that silently doesn't, despite the label's own claim.
            let durations = nights.map(\.total24hAsleepMinutes)
            drawRow("Median total sleep time", minutesLabel(Statistics.median(durations) ?? 0))
            drawRow("Range", "\(minutesLabel(durations.min() ?? 0)) – \(minutesLabel(durations.max() ?? 0))")
            drawRow("Sleep goal", minutesLabel(goalMinutes))
            let efficiency = nights.map(\.sleepEfficiencyPercent)
            drawRow("Median sleep efficiency", String(format: "%.1f%%", Statistics.median(efficiency) ?? 0))

        case .sleepStages:
            let staged = nights.filter(\.hasStageBreakdown)
            if staged.isEmpty {
                drawRow("Stage data", "Not available for this range")
            } else {
                drawRow("Median deep sleep", minutesLabel(Statistics.median(staged.map(\.deepMinutes)) ?? 0))
                drawRow("Median REM sleep", minutesLabel(Statistics.median(staged.map(\.remMinutes)) ?? 0))
                drawRow("Median core/light sleep", minutesLabel(Statistics.median(staged.map(\.coreMinutes)) ?? 0))
                drawRow("Nights with stage data", "\(staged.count) of \(nights.count)")
            }

        case .awakenings:
            let counts = nights.map { Double($0.wakeCount) }
            drawRow("Median awakenings per night", String(format: "%.1f", Statistics.median(counts) ?? 0))
            drawRow("Median awake time", minutesLabel(Statistics.median(nights.map(\.awakeMinutes)) ?? 0))

        case .heartRateHRV:
            let hr = nights.compactMap(\.avgHeartRate)
            let hrv = nights.compactMap(\.avgHRV)
            if !hr.isEmpty {
                drawRow("Median sleeping heart rate", "\(Int((Statistics.median(hr) ?? 0).rounded())) bpm")
            }
            if !hrv.isEmpty {
                drawRow("Median HRV (SDNN)", "\(Int((Statistics.median(hrv) ?? 0).rounded())) ms")
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
                drawRow("Median respiratory rate", String(format: "%.1f breaths/min", Statistics.median(rate) ?? 0))
            }

        case .temperature:
            let deltas = nights.compactMap(\.wristTempDeltaC)
            if deltas.isEmpty {
                drawRow("Wrist temperature", "Not available for this range")
            } else {
                drawRow("Median deviation from baseline", String(format: "%+.2f°C", Statistics.median(deltas) ?? 0))
            }

        case .breathingDisturbances:
            let measuredNights = nights.filter { $0.breathingDisturbances != nil }
            if measuredNights.isEmpty {
                drawRow("Breathing disturbances", "Not available on this device/range")
            } else {
                let values = measuredNights.compactMap(\.breathingDisturbances)
                drawRow("Median, % of night", String(format: "%.1f%%", Statistics.median(values) ?? 0))

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
                drawRow("Median SpO2", String(format: "%.0f%%", Statistics.median(spo2) ?? 0))
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

    private static func clockLabel(_ shiftedMinutes: Double) -> String {
        var minutes = shiftedMinutes
        if minutes < 0 { minutes += 24 * 60 }
        let hour = Int(minutes) / 60 % 24
        let minute = Int(minutes) % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    static func filename(rangeDays: Int) -> String {
        "Sleep_Report_\(ISO8601DateFormatter.dayOnly.string(from: .now))_\(rangeDays)_Days.pdf"
    }
}
