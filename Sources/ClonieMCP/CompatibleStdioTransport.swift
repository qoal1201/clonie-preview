import Foundation
import Logging
import MCP

/// swift-sdk 0.12.x models experimental client capabilities as [String: String],
/// although MCP permits objects. Clonie implements no experimental client features.
/// Ignore object-valued extensions at initialization; leave all tool traffic intact.
/// Remove this shim when the pinned SDK accepts the standard capability schema.
public actor CompatibleStdioTransport: Transport {
    private let base = StdioTransport()
    public nonisolated var logger: Logging.Logger { base.logger }

    public init() {}

    public func connect() async throws { try await base.connect() }
    public func disconnect() async { await base.disconnect() }
    public func send(_ data: Data) async throws { try await base.send(data) }

    public func receive() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await data in await base.receive() {
                        continuation.yield(Self.acceptingExperimentalCapabilities(data))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func acceptingExperimentalCapabilities(_ data: Data) -> Data {
        guard var message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              message["method"] as? String == "initialize",
              var params = message["params"] as? [String: Any],
              var capabilities = params["capabilities"] as? [String: Any],
              let experimental = capabilities["experimental"] as? [String: Any],
              experimental.values.contains(where: { $0 is [String: Any] }) else { return data }
        // Only standard object values are ignored. Invalid primitive values still
        // reach the SDK's validation, and legacy strings retain their old behavior.
        capabilities["experimental"] = experimental.filter { !($0.value is [String: Any]) }
        params["capabilities"] = capabilities
        message["params"] = params
        return (try? JSONSerialization.data(withJSONObject: message)) ?? data
    }
}
