import Domain
import Foundation
import Synchronization

/// Answers from a script and records what it was asked to send. Nothing
/// leaves the process. The last step repeats when the script runs out.
public final class FakeCloudSpeechTransport: CloudSpeechTransport {
    public enum Step: Sendable {
        case respond(status: Int, body: Data)
        case fail(CloudTransportFailure)
        /// Stays in flight until the calling task is cancelled.
        case hang
    }

    private struct State {
        var steps: [Step]
        var requests: [CloudHTTPRequest] = []
    }

    private let state: Mutex<State>

    public init(_ steps: [Step]) {
        state = Mutex(State(steps: steps))
    }

    public var requests: [CloudHTTPRequest] { state.withLock { $0.requests } }

    public func send(_ request: CloudHTTPRequest) async throws(CloudTransportFailure) -> CloudHTTPResponse {
        let step = state.withLock { state -> Step? in
            state.requests.append(request)
            return state.steps.count > 1 ? state.steps.removeFirst() : state.steps.first
        }
        switch step {
        case .respond(let status, let body):
            return CloudHTTPResponse(status: status, body: body)
        case .fail(let failure):
            throw failure
        case .hang:
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(5))
                } catch {
                    break
                }
            }
            throw .cancelled
        case nil:
            throw .failed
        }
    }
}
