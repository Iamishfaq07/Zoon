import SwiftUI
import UniformTypeIdentifiers

/// A still of last night for Messages. Duration, window, one line. Not a report.
struct NightShareCardView: View {
    let asleep: String
    let window: String
    let line: String
    let dateLabel: String

    var body: some View {
        ZStack {
            Color(red: 6 / 255, green: 8 / 255, blue: 17 / 255)
            ShareStarField()
            VStack(spacing: 22) {
                Spacer(minLength: 80)
                MoonFill(fill: 0.34, active: true, size: 186)
                Text("\u{2068}زوٗن\u{2069}")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(Theme.Metric.sleep)
                Text(asleep)
                    .font(.system(size: 72, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(window)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .monospacedDigit()
                Text(line)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 72)
                Spacer()
                Text(dateLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .padding(56)
        }
        .frame(width: 1080, height: 1350)
        .environment(\.colorScheme, .dark)
    }
}

/// Stars without TimelineView — ImageRenderer cannot wait on animation ticks.
private struct ShareStarField: View {
    var body: some View {
        Canvas { context, size in
            for i in 0..<40 {
                let u = frac(Double(i) * 0.6180339887)
                let v = frac(Double(i) * 0.4142135623)
                let r = 1.2 + 2.1 * frac(Double(i) * 0.19)
                let x = u * size.width
                let y = v * size.height
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(Color.white.opacity(0.55))
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func frac(_ x: Double) -> Double { x - floor(x) }
}

/// Renders the card to a PNG in caches, then hands it to the system share sheet.
struct ShareLastNightButton: View {
    let night: SleepNightFeatures
    let line: String

    @State private var fileURL: URL?

    var body: some View {
        Group {
            if let fileURL {
                ShareLink(
                    item: fileURL,
                    preview: SharePreview("Last night", image: Image(systemName: "moonphase.waxing.crescent"))
                ) {
                    label
                }
            } else {
                Button {
                    fileURL = renderFile()
                } label: {
                    label
                }
            }
        }
        .task { fileURL = renderFile() }
    }

    private var label: some View {
        Label("Share last night", systemImage: "square.and.arrow.up")
            .font(Theme.label(14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.neutral(0.1), in: Capsule())
    }

    private var window: String {
        "\(night.clockString(night.bedtime))  →  \(night.clockString(night.wakeTime))"
    }

    private func renderFile() -> URL? {
        let card = NightShareCardView(
            asleep: night.formattedTimeAsleep,
            window: window,
            line: line,
            dateLabel: night.dayString(month: .wide)
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1350)
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "zoon-last-night.png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
