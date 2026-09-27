import Foundation

/// Permission preflight is not a usable input. A lane is connected only after its capture
/// engine starts; delivered PCM is tracked separately so a quiet lane can still be ready.
struct CaptureReadiness {
    struct Snapshot: Encodable, Equatable {
        let phase: String
        let connected: [String]
        let receiving: [String]
        let pending: [String]
        let failed: [String: String]

        static let stopped = Self(phase: "stopped", connected: [], receiving: [], pending: [], failed: [:])
    }

    private let requested: Set<String>
    private var connected = Set<String>()
    private var receiving = Set<String>()
    private var failures: [String: String] = [:]

    init(system: Bool) { requested = system ? ["me", "them"] : ["me"] }

    mutating func connect(_ input: String) {
        guard requested.contains(input), failures[input] == nil else { return }
        connected.insert(input)
    }

    mutating func receive(_ input: String) {
        guard requested.contains(input), failures[input] == nil else { return }
        connected.insert(input)
        receiving.insert(input)
    }

    mutating func fail(_ input: String, message: String) {
        guard requested.contains(input) else { return }
        connected.remove(input)
        receiving.remove(input)
        failures[input] = message
    }

    var snapshot: Snapshot {
        let pending = requested.subtracting(connected).subtracting(failures.keys).sorted()
        let phase = connected.isEmpty ? (pending.isEmpty ? "failed" : "starting")
            : (pending.isEmpty && failures.isEmpty ? "active" : "partial")
        return Snapshot(phase: phase, connected: connected.sorted(), receiving: receiving.sorted(),
                        pending: pending, failed: failures)
    }
}
