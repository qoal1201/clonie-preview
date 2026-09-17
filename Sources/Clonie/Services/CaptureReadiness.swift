import Foundation

/// Opening a device is not an input receipt. Only delivered PCM marks an input as receiving.
struct CaptureReadiness {
    struct Snapshot: Encodable, Equatable {
        let phase: String
        let receiving: [String]
        let pending: [String]
        let failed: [String: String]

        static let stopped = Self(phase: "stopped", receiving: [], pending: [], failed: [:])
    }

    private let requested: Set<String>
    private var receiving = Set<String>()
    private var failures: [String: String] = [:]

    init(system: Bool) { requested = system ? ["me", "them"] : ["me"] }

    mutating func receive(_ input: String) {
        guard requested.contains(input), failures[input] == nil else { return }
        receiving.insert(input)
    }

    mutating func fail(_ input: String, message: String) {
        guard requested.contains(input) else { return }
        receiving.remove(input)
        failures[input] = message
    }

    var snapshot: Snapshot {
        let pending = requested.subtracting(receiving).subtracting(failures.keys).sorted()
        let phase = receiving.isEmpty ? (pending.isEmpty ? "failed" : "starting")
            : (pending.isEmpty && failures.isEmpty ? "active" : "partial")
        return Snapshot(phase: phase, receiving: receiving.sorted(), pending: pending, failed: failures)
    }
}
