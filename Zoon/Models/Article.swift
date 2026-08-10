import SwiftUI

/// One piece of bundled, offline sleep-science reading — Apple Health's
/// "Browse" tab, without a server behind it.
///
/// Every word here ships inside the app. There is nowhere for it to be
/// fetched from and nothing to keep in sync with a CMS; the trade is that an
/// article can't be updated without a new build, which is the right trade for
/// an app whose entire pitch is "nothing calls out."
struct Article: Identifiable, Hashable {
    let id: String
    let category: Category
    let title: String
    let subtitle: String
    let symbol: String
    let readMinutes: Int
    /// Paragraphs, in order. Plain strings rather than Markdown or attributed
    /// text: nothing here needs bold, links, or lists, and a plain array is
    /// trivial to typeset consistently.
    let body: [String]
    /// Surfaced under a lightbulb at the end of most articles — the one thing
    /// worth taking away, not a recap of the whole piece.
    let takeaway: String?

    enum Category: String, CaseIterable, Identifiable {
        case fundamentals, recovery, habits, environment

        var id: String { rawValue }

        var label: String {
            switch self {
            case .fundamentals: "Fundamentals"
            case .recovery: "Recovery"
            case .habits: "Habits"
            case .environment: "Environment"
            }
        }

        var tint: Color {
            switch self {
            case .fundamentals: Theme.Metric.sleep
            case .recovery: Theme.Metric.recoveryHigh
            case .habits: Theme.Metric.battery
            case .environment: Theme.Metric.hrv
            }
        }
    }
}

extension Article {

    /// Every bundled article. Ordered as a rough reading path — fundamentals
    /// first, environment last — though the grid presents them by category,
    /// not in this order.
    static let all: [Article] = [
        Article(
            id: "sleep-stages",
            category: .fundamentals,
            title: "The Four Stages of Sleep",
            subtitle: "What Core, Deep, and REM actually do",
            symbol: "moon.stars.fill",
            readMinutes: 4,
            body: [
                "A night of sleep isn't one uniform state — it's a cycle of distinct stages that repeats every 80 to 120 minutes, four to six times a night. Each stage does different physiological work, which is why both how long you sleep and how that time is distributed matter.",
                "Light sleep (what Zoon and Apple Health label Core) is the stage you spend the most time in — usually half the night. It's the transition state between wakefulness and deeper sleep, and where your heart rate and breathing first begin to settle.",
                "Deep sleep is the stage most associated with physical restoration. Growth hormone release peaks here, tissue repairs, and the immune system does a lot of its work. It's concentrated in the first half of the night — which is part of why cutting a night short at the start costs more than cutting it short at the end.",
                "REM (rapid eye movement) sleep is where most vivid dreaming happens, and it's central to memory consolidation and emotional processing. Unlike deep sleep, REM periods lengthen as the night goes on — the last cycle before waking is often the longest.",
                "Awake time, in small amounts, is completely normal. Brief arousals between cycles happen every night for everyone; you just don't usually remember them unless they cross a certain length or you were already close to waking."
            ],
            takeaway: "There's no stage that's simply \"wasted\" — Deep and REM do different jobs, and a short night usually shortchanges whichever one hadn't finished yet."
        ),
        Article(
            id: "sleep-debt",
            category: .fundamentals,
            title: "What Sleep Debt Really Means",
            subtitle: "Why one long night doesn't erase a bad week",
            symbol: "chart.line.downtrend.xyaxis",
            readMinutes: 3,
            body: [
                "Sleep debt is the cumulative shortfall between the sleep you needed and the sleep you got, tracked over days rather than judged night to night. Zoon totals this over a rolling two-week window because a single rough night rarely matters much — a pattern of them does.",
                "The uncomfortable part: debt doesn't repay one-for-one. Research on recovery sleep consistently shows that people who \"catch up\" on a weekend don't fully reverse the cognitive and metabolic effects of a week of short nights — some of the deficit lingers even after total sleep time is restored.",
                "This is also why sleep need isn't just your personal target restated every day. If you're carrying debt, your body's actual need that night is higher than your baseline goal, which is why Zoon's Sleep Need card sometimes shows a target above your set goal — it's accounting for what's still owed.",
                "The practical implication isn't to panic about one short night. It's that consistency compounds in both directions: a stretch of slightly-short nights is a bigger deal than it feels like night to night, and the fix is a stretch of adequate ones, not a single marathon sleep."
            ],
            takeaway: "Treat sleep debt like a trend, not a single night's grade — and pay it back gradually, not in one oversized sleep-in."
        ),
        Article(
            id: "hrv-explained",
            category: .recovery,
            title: "HRV and What It's Actually Measuring",
            subtitle: "The metric behind every recovery score",
            symbol: "waveform.path.ecg",
            readMinutes: 4,
            body: [
                "Heart rate variability is the variation in time between consecutive heartbeats — not your heart rate itself, but how much it fluctuates beat to beat. Counterintuitively, more variability is generally the healthier sign; a heart that adjusts fluidly is one under less sustained strain.",
                "HRV is controlled largely by your autonomic nervous system, specifically the balance between its \"fight or flight\" and \"rest and digest\" branches. When you're stressed, under-recovered, sick, or have been drinking, that balance tips, and HRV tends to drop.",
                "This is why HRV is read relative to *your* baseline rather than a universal number — a healthy HRV for one person might be a concerning drop for another. Zoon needs a few weeks of nights before it can say your HRV is meaningfully high or low, precisely because \"normal\" is personal.",
                "A single low reading usually isn't meaningful on its own — HRV is naturally noisy night to night, affected by everything from alcohol to a hard workout to poor sleep the night before. What's worth paying attention to is a sustained shift over several nights, not one number."
            ],
            takeaway: "One low HRV night is noise. A downward trend across a week is signal worth listening to."
        ),
        Article(
            id: "sleep-consistency",
            category: .habits,
            title: "Why the Same Bedtime Matters More Than a Longer One",
            subtitle: "Your body clock cares about rhythm, not just duration",
            symbol: "arrow.triangle.2.circlepath",
            readMinutes: 3,
            body: [
                "Your circadian rhythm — the internal clock that governs when you feel alert or sleepy — is set largely by consistency: the same wake time, the same light exposure, day after day. It adapts slowly, which means it doesn't reset cleanly just because you slept in.",
                "This is the mechanism behind \"social jetlag\": a mismatch between your weekday and weekend sleep schedule that behaves, physiologically, a lot like crossing time zones without going anywhere. A few hours of drift on weekends can leave you feeling off on Monday in a way that mirrors mild jet lag.",
                "Two people who each average 7.5 hours a night can have very different sleep quality if one keeps a steady schedule and the other's varies by two or three hours night to night. Regularity gives your body a predictable window to prepare for sleep — hormonally and behaviorally — before you even lie down.",
                "This doesn't mean rigid perfection. It means that if you're choosing between an extra hour of sleep on an irregular schedule and a consistent schedule with slightly less total sleep, the consistent one is often the better trade for how you'll actually feel."
            ],
            takeaway: "If your schedule has to give somewhere, protect your wake time first — it's the anchor your body clock uses to set everything else."
        ),
        Article(
            id: "caffeine-and-sleep",
            category: .habits,
            title: "How Long Caffeine Actually Stays With You",
            subtitle: "The half-life problem behind an afternoon coffee",
            symbol: "cup.and.saucer.fill",
            readMinutes: 3,
            body: [
                "Caffeine's half-life — the time it takes your body to clear half of it — is typically 5 to 6 hours, though it varies meaningfully by person (genetics, liver function, and regular caffeine use all shift this). That means a coffee at 4pm can still leave a quarter of its caffeine active in your system at 2am.",
                "Caffeine works by blocking adenosine, a chemical that builds up in your brain through the day and creates the pressure to sleep. Blocking it doesn't remove that pressure — it just masks it temporarily, which is part of why the sleep caffeine displaces can feel unrefreshing even when it isn't obviously disrupted.",
                "Even when caffeine doesn't stop you falling asleep, studies using EEG have shown it can reduce time spent in deep sleep and shift sleep architecture, sometimes without the person noticing any difference in how quickly they dozed off.",
                "There's no single safe cutoff time that works for everyone — it depends on your personal sensitivity and how much you drank. A reasonable starting point many sleep researchers suggest is stopping caffeine 8 to 10 hours before your intended bedtime, then adjusting based on how you actually sleep."
            ],
            takeaway: "Falling asleep fine after coffee doesn't mean caffeine had no effect — it's just as likely to be shaping how deep that sleep was."
        ),
        Article(
            id: "sleep-and-training",
            category: .recovery,
            title: "Why Hard Training Days Change What You Need",
            subtitle: "Strain and sleep need are linked, not separate numbers",
            symbol: "figure.run",
            readMinutes: 3,
            body: [
                "Sleep is when a large share of physical adaptation to training actually happens — muscle repair, glycogen replenishment, and growth hormone release are all concentrated in deep sleep. A hard training day increases the repair workload your body needs sleep to get through.",
                "This is why Zoon's Sleep Need adds time back for a strenuous day: the research linking training load to sleep need isn't just about feeling tired — harder days measurably raise the amount of restorative sleep your body benefits from, particularly deep sleep.",
                "The relationship runs both ways. Under-sleeping after a hard training block doesn't just leave you tired — it measurably slows recovery, raises perceived exertion on the next session, and in athletes has been linked to higher injury rates over a season.",
                "None of this means you need a rigid formula — a general rule that holds up well is treating a genuinely hard day as a cue to protect that night's sleep specifically, rather than assuming your usual schedule automatically covers a heavier load."
            ],
            takeaway: "A hard training day isn't just a reason for an earlier bedtime — it's a reason the sleep you do get matters more than usual."
        ),
        Article(
            id: "bedroom-temperature",
            category: .environment,
            title: "The Temperature That Actually Helps You Sleep",
            subtitle: "Why cooler almost always beats warmer",
            symbol: "thermometer.snowflake",
            readMinutes: 3,
            body: [
                "Your core body temperature naturally drops by 1-2°F as part of falling asleep — it's one of the physiological triggers your body uses to signal that it's time. A bedroom that's too warm works against this process directly, making that drop harder to achieve.",
                "Most sleep researchers point to a range around 65-68°F (18-20°C) as close to ideal for most people, though this varies with what you're used to, what you're wearing, and your bedding. The consistent finding across studies isn't a magic number — it's that too warm reliably hurts sleep more than too cool does.",
                "This is also part of why wrist temperature is a useful signal: a night that runs measurably warmer than your own baseline can reflect anything from a warm room to illness to alcohol, all of which tend to fragment sleep even when you don't consciously wake up more.",
                "A practical note: it's easier to warm up with a blanket than to cool down once you're already too warm. If you're unsure which direction to adjust, erring cooler and adding a layer tends to work better than the reverse."
            ],
            takeaway: "If you only change one thing about your bedroom environment, temperature has the strongest evidence behind it — more than light, noise, or mattress firmness."
        ),
        Article(
            id: "screens-before-bed",
            category: .environment,
            title: "Screens Before Bed: What's Actually Going On",
            subtitle: "It's less about blue light than you might think",
            symbol: "iphone",
            readMinutes: 3,
            body: [
                "The popular explanation for \"screens ruin your sleep\" is blue light suppressing melatonin, and that effect is real — but its size is often overstated relative to typical phone-at-arm's-length use. The bigger factor for most people is simpler: what you're actually doing on the screen.",
                "Engaging content — an argument, a stressful email, a gripping show, an infinite scroll — keeps your mind alert and your stress response mildly activated, which works against the wind-down your body needs before sleep, independent of the light involved.",
                "That said, light does matter for timing: bright light late at night, especially the kind that hits your eyes directly, can shift your circadian rhythm later, making you feel less sleepy at your usual bedtime the following night, not necessarily tonight.",
                "The practical version of this isn't a strict all-or-nothing rule. Dimming your screen, avoiding genuinely stimulating content, and giving yourself even 15-20 minutes of something calmer before bed captures most of the benefit without requiring you to give up screens entirely."
            ],
            takeaway: "What you're watching or reading matters at least as much as the light itself — a calm video is a very different pre-bed choice than a stressful one, blue light aside."
        )
    ]
}
