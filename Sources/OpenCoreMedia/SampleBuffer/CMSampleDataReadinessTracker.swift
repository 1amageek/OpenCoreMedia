import Synchronization

final class CMSampleDataReadinessTracker: Sendable {
    private struct State: Sendable {
        var readiness: CMSampleBufferDataReadiness
        var revision: UInt64
    }

    private let state: CMStateLock<State>
    private let coordinator: CMSampleDataReadinessCoordinator?

    init(
        readiness: CMSampleBufferDataReadiness,
        handler: CMSampleBufferMakeDataReadyHandler?
    ) {
        state = CMStateLock(State(readiness: readiness, revision: 0))
        coordinator = handler.map {
            CMSampleDataReadinessCoordinator(handler: $0)
        }
    }

    var readiness: CMSampleBufferDataReadiness {
        state.withLock { $0.readiness }
    }

    func set(
        _ readiness: CMSampleBufferDataReadiness
    ) throws(CMSampleBufferError) {
        try state.withLock { state throws(CMSampleBufferError) in
            try Self.validateTransition(
                from: state.readiness,
                to: readiness
            )
            state.readiness = readiness
            state.revision &+= 1
        }
    }

    func makeReady() async throws(CMSampleBufferError) {
        let snapshot = state.withLock {
            (readiness: $0.readiness, revision: $0.revision)
        }
        guard let coordinator else {
            switch snapshot.readiness {
            case .ready:
                return
            case .notReady:
                throw .dataNotReady
            case .failed(let code):
                throw .dataFailed(code: code)
            }
        }
        let resolved = try await coordinator.resolved(
            from: snapshot.readiness
        )
        let committed = try state.withLock {
            state throws(CMSampleBufferError) in
            guard state.revision == snapshot.revision else {
                return state.readiness
            }
            try Self.validateTransition(
                from: state.readiness,
                to: resolved
            )
            state.readiness = resolved
            state.revision &+= 1
            return resolved
        }
        switch committed {
        case .ready:
            return
        case .notReady:
            throw .dataNotReady
        case .failed(let code):
            throw .dataFailed(code: code)
        }
    }

    private static func validateTransition(
        from current: CMSampleBufferDataReadiness,
        to requested: CMSampleBufferDataReadiness
    ) throws(CMSampleBufferError) {
        switch (current, requested) {
        case (.notReady, _), (.ready, .ready):
            return
        case (.failed(let currentCode), .failed(let requestedCode))
            where currentCode == requestedCode:
            return
        default:
            throw .invalidReadinessTransition(
                from: current,
                to: requested
            )
        }
    }
}
