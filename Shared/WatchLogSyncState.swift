import Foundation

/// How far a wrist-logged action has actually got.
///
/// **The bug.** The watch reported success the instant `transferUserInfo`
/// returned. That call hands the payload to WatchConnectivity's queue; it
/// says nothing about whether the phone ever received it, whether the phone
/// could decode it, or whether it was written to the store. A tap in a dead
/// zone, a phone that never reconnects, an envelope the phone rejects as a
/// duplicate — all three showed "Saved".
///
/// Queued is a fine thing to tell someone, and it is honest. "Saved" is a
/// claim about the phone's database and only the phone can make it.
enum WatchLogSyncState: Equatable, Sendable {
    case idle
    /// Handed to WatchConnectivity; the phone may be unreachable. This is
    /// the correct resting state offline, not a failure.
    case queued
    /// The session is active and the transfer is in flight.
    case sending
    /// The phone has confirmed it persisted this exact envelope.
    case saved
    /// The phone rejected it, or it could not be encoded at all.
    case failed(reason: String)

    /// Only one state may say the word.
    var isConfirmed: Bool { self == .saved }

    var label: String {
        switch self {
        case .idle: ""
        case .queued: "Queued"
        case .sending: "Sending"
        case .saved: "Saved"
        case .failed: "Not saved"
        }
    }

    var symbol: String {
        switch self {
        case .idle: ""
        case .queued: "clock.arrow.circlepath"
        case .sending: "arrow.up.circle"
        case .saved: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    /// Whether the wearer should expect this to resolve on its own. A queued
    /// log needs no action; a failed one does.
    var resolvesItself: Bool {
        switch self {
        case .queued, .sending: true
        case .idle, .saved, .failed: false
        }
    }
}

/// Tracks the state of each in-flight wrist log by envelope id.
///
/// Keyed by `WatchActionEnvelope.id`, which the phone echoes back in its
/// acknowledgement — the same identifier `WatchActionReceiptStore` already
/// uses to reject duplicates, so a log the phone deduplicates is confirmed
/// rather than left pending forever. Being told "we already have this" is a
/// successful outcome from the wearer's point of view.
@MainActor
@Observable
final class WatchLogSyncTracker {

    private(set) var states: [UUID: WatchLogSyncState] = [:]

    /// The most recently touched log, which is what a one-line watch UI
    /// shows.
    private(set) var latest: (id: UUID, state: WatchLogSyncState)?

    func record(_ id: UUID, _ state: WatchLogSyncState) {
        states[id] = state
        latest = (id, state)
    }

    func state(for id: UUID) -> WatchLogSyncState {
        states[id] ?? .idle
    }

    /// Marks everything still in flight as failed — used when a session
    /// cannot activate at all, where waiting for an acknowledgement that can
    /// never arrive would leave the row spinning indefinitely.
    func failAllPending(reason: String) {
        for (id, state) in states where state.resolvesItself {
            states[id] = .failed(reason: reason)
            if latest?.id == id { latest = (id, .failed(reason: reason)) }
        }
    }

    func clear() {
        states.removeAll()
        latest = nil
    }
}

/// The phone's verdict on one wrist-logged envelope, phone -> watch.
///
/// Carries the envelope's own identifier rather than a position in a queue:
/// WatchConnectivity may redeliver, reorder, or hold a transfer for hours,
/// so the only reliable way to say which log this is about is to say its id.
struct WatchActionAcknowledgement: Codable, Sendable {
    let id: UUID
    let accepted: Bool
    let reason: String?

    init(id: UUID, accepted: Bool, reason: String? = nil) {
        self.id = id
        self.accepted = accepted
        self.reason = reason
    }

    var state: WatchLogSyncState {
        accepted ? .saved : .failed(reason: reason ?? "Your phone couldn't file this log.")
    }
}
